"""Offline tests for triage.py: a fake model and a fake cluster, no API key and no network."""
from __future__ import annotations

from types import SimpleNamespace as NS

import pytest

import triage as t


# --- Fakes -----------------------------------------------------------------------------------------------------

def text(s):
    return NS(type="text", text=s)


def tool(id_, name, **inp):
    return NS(type="tool_use", id=id_, name=name, input=inp)


class FakeClient:
    """Returns scripted responses and records every request, like anthropic.Anthropic().messages.create."""

    def __init__(self, responses):
        self.responses = list(responses)
        self.requests = []
        self.messages = self

    def create(self, **kwargs):
        # Copy the message list, because triage() keeps appending to the same list.
        self.requests.append({**kwargs, "messages": list(kwargs["messages"])})
        return self.responses.pop(0)


def reply(*content, stop="tool_use"):
    return NS(content=list(content), stop_reason=stop)


LOGS = ('{"level":"error","msg":"transfer failed","card":"4111 1111 1111 1111","email":"ada@example.com",'
        '"phone":"+234 803 123 4567","account_number":"0123456789","auth":"Bearer abcdefghijklmnop1234"}\n'
        'psycopg.OperationalError: connection timeout expired; password=hunter2')


# --- Redaction -------------------------------------------------------------------------------------------------

def test_redaction_removes_personal_data_and_credentials():
    out = t.redact(LOGS + " AKIAABCDEFGHIJKLMNOP sk-ant-api03-abcdefghijklmnop")
    for secret in ("4111", "ada@example.com", "803 123", "0123456789", "abcdefghijklmnop1234", "hunter2",
                   "AKIAABCDEFGHIJKLMNOP", "sk-ant-api03"):
        assert secret not in out, secret
    assert "connection timeout expired" in out  # the evidence survives
    assert "[REDACTED:card]" in out and "[REDACTED:email]" in out


def test_redaction_keeps_ordinary_numbers():
    line = "GET /v1/transfers 200 12ms replicas=3 restarts=0 2026-11-07T08:00:00Z"
    assert t.redact(line) == line


# --- The allowlist ---------------------------------------------------------------------------------------------

@pytest.mark.parametrize("cmd", [
    "kubectl -n itlpay get pods -o wide",
    "kubectl logs deploy/itlpay -n itlpay --tail=50",
    "kubectl -n itlpay describe deploy itlpay",
    "kubectl -n itlpay top pods",
    "kubectl events -n itlpay",
    "kubectl -n itlpay rollout history deploy/itlpay",
    "kubectl -n itlpay get pods -l app=itlpay",
])
def test_read_only_commands_are_allowed(cmd):
    assert t.check_command(cmd)[0] == "kubectl"


@pytest.mark.parametrize("cmd", [
    "kubectl -n itlpay delete pod itlpay-0",
    "kubectl -n itlpay rollout undo deploy/itlpay",
    "kubectl -n itlpay scale deploy/itlpay --replicas=0",
    "kubectl -n itlpay get secret itlpay-db -o yaml",
    "kubectl -n itlpay get secrets,pods",
    "kubectl -n itlpay describe secret/itlpay-db",
    "kubectl -n itlpay exec -it itlpay-0 -- sh",
    "kubectl -n itlpay port-forward svc/itlpay 8080",
    "kubectl get pods; rm -rf /",
    "kubectl get pods | sh",
    "kubectl get pods $(whoami)",
    "kubectl --kubeconfig=/tmp/admin get pods",
    "kubectl --as=system:admin get pods",
    "kubectl get --raw /api/v1/namespaces/itlpay/secrets",
    "bash -c 'kubectl get pods'",
    "curl http://metadata.internal",
])
def test_everything_else_is_refused(cmd):
    with pytest.raises(t.Refused):
        t.check_command(cmd)


# --- The loop --------------------------------------------------------------------------------------------------

def test_tool_output_is_redacted_before_the_model_sees_it():
    ran = []
    client = FakeClient([
        reply(text("Checking logs."), tool("t1", "kubectl_readonly", command="kubectl -n itlpay logs deploy/itlpay")),
        reply(text("Database timeouts."), stop="end_turn"),
    ])
    result = t.triage("ITLPayHighErrorRate firing; contact ada@example.com", client,
                      runner=lambda argv: ran.append(argv) or LOGS)
    assert ran == [["kubectl", "-n", "itlpay", "logs", "deploy/itlpay"]]
    sent = str(client.requests[1]["messages"])
    assert "4111" not in sent and "hunter2" not in sent and "ada@example.com" not in sent
    assert "connection timeout expired" in sent
    assert "ada@example.com" not in str(client.requests[0]["messages"])  # the alert is redacted too
    assert result.summary == "Database timeouts." and result.stopped == "end_turn"


def test_refused_commands_never_run_and_the_model_is_told():
    ran = []
    client = FakeClient([
        reply(tool("t1", "kubectl_readonly", command="kubectl -n itlpay get secret itlpay-db -o yaml")),
        reply(text("I can't read Secrets."), stop="end_turn"),
    ])
    t.triage("alert", client, runner=lambda argv: ran.append(argv) or "")
    assert ran == []
    result_block = client.requests[1]["messages"][-1]["content"][0]
    assert result_block["is_error"] is True and "Refused" in result_block["content"]


def test_proposals_wait_for_a_human_and_are_never_run_by_the_tool():
    ran, asked = [], []
    client = FakeClient([
        reply(tool("t1", "propose_action", command="kubectl -n itlpay rollout undo deploy/itlpay",
                   reason="errors began with the last rollout", risk="medium")),
        reply(text("Proposed a rollback."), stop="end_turn"),
    ])
    rejected = t.triage("alert", client, runner=lambda argv: ran.append(argv) or "",
                        approve=lambda p: asked.append(p.command) or False)
    assert asked == ["kubectl -n itlpay rollout undo deploy/itlpay"]
    assert ran == [] and rejected.proposals[0].approved is False

    client = FakeClient([
        reply(tool("t1", "propose_action", command="kubectl -n itlpay rollout undo deploy/itlpay",
                   reason="r", risk="medium")),
        reply(text("ok"), stop="end_turn"),
    ])
    approved = t.triage("alert", client, runner=lambda argv: ran.append(argv) or "", approve=lambda p: True)
    assert approved.proposals[0].approved is True and ran == []  # approved means "a human will run it"


def test_without_an_approver_nothing_is_approved():
    client = FakeClient([reply(tool("t1", "propose_action", command="x", reason="r", risk="high")),
                         reply(text("done"), stop="end_turn")])
    assert t.triage("alert", client).proposals[0].approved is False


def test_the_loop_stops_after_max_turns():
    looping = [reply(tool(f"t{i}", "kubectl_readonly", command="kubectl get pods")) for i in range(10)]
    result = t.triage("alert", FakeClient(looping), runner=lambda argv: "ok", max_turns=3)
    assert result.turns == 3 and result.stopped == "max_turns"


def test_audit_log_records_each_step_without_personal_data():
    events = []
    client = FakeClient([
        reply(tool("t1", "kubectl_readonly", command="kubectl -n itlpay logs deploy/itlpay"),
              tool("t2", "kubectl_readonly", command="kubectl delete pod x")),
        reply(text("done"), stop="end_turn"),
    ])
    t.triage("alert for ada@example.com", client, runner=lambda argv: LOGS, audit=events.append)
    kinds = [e["event"] for e in events]
    assert kinds == ["start", "ran", "refused", "end"]
    assert "ada@example.com" not in str(events)


def test_requests_use_the_current_model_with_tools():
    client = FakeClient([reply(text("ok"), stop="end_turn")])
    t.triage("alert", client)
    req = client.requests[0]
    assert req["model"] == "claude-opus-5-5"
    assert {tl["name"] for tl in req["tools"]} == {"kubectl_readonly", "propose_action"}


def test_redaction_handles_json_keys():
    out = t.redact('{"password":"s3cr3t-value","api_key": "abc123xyz","account_number":"0123456789","ok":true}')
    assert "s3cr3t" not in out and "abc123xyz" not in out and "0123456789" not in out
    assert '"ok":true' in out
