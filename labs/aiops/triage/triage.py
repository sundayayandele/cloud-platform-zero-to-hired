#!/usr/bin/env python3
"""An incident-triage assistant for ITL Pay (topic 17.1), built to be safe by design.

    export ANTHROPIC_API_KEY=...            # from your own Anthropic Console account; never commit it
    python3 triage.py --alert "ITLPayHighErrorRate: 5xx ratio 4% for 10m in namespace itlpay"

What it does, and what it may never do:

- The model investigates with READ-ONLY kubectl commands from an allowlist (get, describe, logs, top, events).
  It can't read Secrets, exec into pods, port-forward or change anything. Commands run without a shell.
- Everything sent to the model (the alert and every command's output) is REDACTED first: card numbers, account
  numbers, phone numbers, email addresses, tokens and keys never leave your cluster.
- The model may PROPOSE a change (a rollback, a scale-up). A human approves or rejects each proposal. Approved
  commands are printed for the on-call engineer to run; this tool never runs a change itself.
- Every step is written to an audit log (JSON lines), and the loop stops after a fixed number of turns.

The tests (test_triage.py) use a fake model and a fake cluster, so they run offline with no API key.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Any, Callable

MODEL = "claude-opus-5-5"
MAX_TURNS = 8
MAX_OUTPUT_CHARS = 6000

SYSTEM = """You are an incident-triage assistant for ITL Pay, a payments API on Kubernetes (namespace itlpay).
Investigate the alert with the read-only kubectl tool, then give the on-call engineer:
1. a short summary of what is happening and the evidence for it (quote the commands and output you used);
2. the most likely cause, with your confidence, and what would prove or disprove it;
3. at most two proposed actions through the propose_action tool (for example a rollback), each with its risk.
You can't change anything yourself. Data marked [REDACTED:...] was removed on purpose; don't try to recover it.
If the evidence is unclear, say so rather than guess."""

TOOLS = [
    {
        "name": "kubectl_readonly",
        "description": (
            "Run one read-only kubectl command and get its output. Allowed verbs: get, describe, logs, top, events "
            "(and 'rollout status' / 'rollout history'). Secrets, exec, port-forward, proxy and every change are "
            "refused. Example: 'kubectl -n itlpay get pods -o wide'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {"command": {"type": "string", "description": "The full kubectl command"}},
            "required": ["command"],
        },
    },
    {
        "name": "propose_action",
        "description": (
            "Propose a change for a human to approve, such as 'kubectl -n itlpay rollout undo deploy/itlpay'. "
            "It is NOT run by you; the on-call engineer decides."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string"},
                "reason": {"type": "string"},
                "risk": {"type": "string", "enum": ["low", "medium", "high"]},
            },
            "required": ["command", "reason", "risk"],
        },
    },
]

# --- Redaction -------------------------------------------------------------------------------------------------

_REDACTIONS: list[tuple[str, re.Pattern[str]]] = [
    ("private-key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.S)),
    ("jwt", re.compile(r"\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]{8,}\b")),
    ("bearer-token", re.compile(r"(?i)\bbearer\s+[\w\-.~+/=]{12,}")),
    ("aws-access-key", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("api-key", re.compile(r"\bsk-[\w-]{16,}\b")),
    ("secret", re.compile(r"(?i)\b(password|passwd|pwd|secret|token|api[_-]?key)\"?\s*[=:]\s*(\"[^\"]*\"|'[^']*'|[^\s,}]+)")),
    ("email", re.compile(r"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b")),
    ("card", re.compile(r"\b(?:\d[ -]?){12,18}\d\b")),
    ("phone", re.compile(r"(?<![\w.])\+?(?:234|27|233|254|256|255|250)[ -]?\d{2,3}[ -]?\d{3}[ -]?\d{3,4}\b")),
    ("account-number", re.compile(r"(?i)\b(account|acct|nuban)(_?(no|number|id))?\"?\s*[=:]\s*\"?\d{8,}\"?")),
]


def redact(text: str) -> str:
    """Replace personal data and credentials with [REDACTED:kind] before anything leaves the cluster."""
    for kind, pattern in _REDACTIONS:
        if kind == "secret":
            text = pattern.sub(lambda m: f"{m.group(1)}=[REDACTED:secret]", text)
        elif kind == "account-number":
            text = pattern.sub(lambda m: f"{m.group(1)}=[REDACTED:account-number]", text)
        else:
            text = pattern.sub(f"[REDACTED:{kind}]", text)
    return text


# --- The read-only allowlist -----------------------------------------------------------------------------------

READ_VERBS = {"get", "describe", "logs", "top", "events"}
ROLLOUT_READ = {"status", "history"}
FORBIDDEN_RESOURCES = {"secret", "secrets", "sealedsecret", "sealedsecrets", "externalsecret", "externalsecrets"}
FORBIDDEN_FLAGS = ("--kubeconfig", "--token", "--as", "--as-group", "--server", "--context", "--raw", "--username",
                   "--password", "--client-key", "--client-certificate", "--certificate-authority", "--insecure")
FLAGS_WITH_VALUE = {"-n", "--namespace", "-o", "--output", "-l", "--selector", "-c", "--container", "--tail",
                    "--since", "--field-selector", "--sort-by"}
SHELL_CHARS = set(";|&$`<>\\\n(){}")


class Refused(ValueError):
    pass


def check_command(command: str) -> list[str]:
    """Return argv if the command is an allowed read-only kubectl command; raise Refused otherwise."""
    if any(c in SHELL_CHARS for c in command):
        raise Refused("shell characters aren't allowed")
    try:
        argv = shlex.split(command)
    except ValueError as e:
        raise Refused(f"can't parse: {e}") from None
    if not argv or argv[0] != "kubectl":
        raise Refused("only kubectl is allowed")
    words: list[str] = []
    skip = False
    for arg in argv[1:]:
        if skip:
            skip = False
            continue
        low = arg.lower()
        if low.startswith(FORBIDDEN_FLAGS):
            raise Refused(f"flag {arg.split('=')[0]} isn't allowed")
        if arg in FLAGS_WITH_VALUE:
            skip = True
            continue
        if arg.startswith("-"):
            continue
        words.append(low)
    if not words:
        raise Refused("no verb")
    verb = words[0]
    if verb == "rollout":
        if len(words) < 2 or words[1] not in ROLLOUT_READ:
            raise Refused("only 'rollout status' and 'rollout history' are allowed")
    elif verb not in READ_VERBS:
        raise Refused(f"'{verb}' isn't a read-only verb")
    for w in words[1:]:
        for part in re.split(r"[,/]", w):
            if part.split(".")[0] in FORBIDDEN_RESOURCES:
                raise Refused("Secrets can't be read")
    return argv


def run_kubectl(argv: list[str]) -> str:
    """Run an already-checked command, with no shell and a timeout."""
    p = subprocess.run(argv, capture_output=True, text=True, timeout=30, check=False)
    return (p.stdout + (("\n" + p.stderr) if p.stderr else "")).strip() or "(no output)"


# --- The loop --------------------------------------------------------------------------------------------------

@dataclass
class Proposal:
    command: str
    reason: str
    risk: str
    approved: bool = False


@dataclass
class Result:
    summary: str
    proposals: list[Proposal] = field(default_factory=list)
    turns: int = 0
    stopped: str = ""


def _audit(log: Callable[[dict], None] | None, **event: Any) -> None:
    if log:
        log({"time": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), **event})


def triage(alert: str, client: Any, *, runner: Callable[[list[str]], str] = run_kubectl,
           approve: Callable[[Proposal], bool] | None = None, audit: Callable[[dict], None] | None = None,
           max_turns: int = MAX_TURNS) -> Result:
    """Investigate an alert with the model. `client` is anthropic.Anthropic() or a fake with the same shape."""
    messages: list[dict] = [{"role": "user", "content": f"Alert:\n{redact(alert)}"}]
    result = Result(summary="")
    _audit(audit, event="start", alert=redact(alert))
    for turn in range(1, max_turns + 1):
        result.turns = turn
        response = client.messages.create(
            model=MODEL, max_tokens=8000, system=SYSTEM, tools=TOOLS, messages=messages,
            thinking={"type": "adaptive"},
        )
        messages.append({"role": "assistant", "content": response.content})
        text = "\n".join(b.text for b in response.content if b.type == "text").strip()
        if response.stop_reason != "tool_use":
            result.summary, result.stopped = text, response.stop_reason
            break
        tool_results = []
        for block in response.content:
            if block.type != "tool_use":
                continue
            content, is_error = _handle_tool(block.name, block.input, runner, result, audit)
            tool_results.append({"type": "tool_result", "tool_use_id": block.id, "content": content,
                                 "is_error": is_error})
        messages.append({"role": "user", "content": tool_results})
    else:
        result.stopped = "max_turns"
        result.summary = "Stopped after the maximum number of turns; hand over to a human with the evidence so far."
    _audit(audit, event="end", stopped=result.stopped, turns=result.turns)

    for proposal in result.proposals:
        proposal.approved = bool(approve and approve(proposal))
        _audit(audit, event="decision", command=proposal.command, approved=proposal.approved)
    return result


def _handle_tool(name: str, args: dict, runner, result: Result, audit) -> tuple[str, bool]:
    if name == "kubectl_readonly":
        command = str(args.get("command", ""))
        try:
            argv = check_command(command)
        except Refused as e:
            _audit(audit, event="refused", command=command, reason=str(e))
            return f"Refused: {e}. Use a read-only kubectl command.", True
        output = redact(runner(argv))[:MAX_OUTPUT_CHARS]
        _audit(audit, event="ran", command=command, chars=len(output))
        return output, False
    if name == "propose_action":
        p = Proposal(str(args.get("command", "")), str(args.get("reason", "")), str(args.get("risk", "")))
        result.proposals.append(p)
        _audit(audit, event="proposed", command=p.command, risk=p.risk)
        return "Recorded for the on-call engineer to approve or reject. It has not been run.", False
    return f"Unknown tool {name}", True


# --- Command line ----------------------------------------------------------------------------------------------

def _ask(p: Proposal) -> bool:
    print(f"\nProposed ({p.risk} risk): {p.command}\n  why: {p.reason}")
    return input("  Approve? Type 'yes' to approve: ").strip().lower() == "yes"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--alert", required=True, help="the alert text, as your alerting sends it")
    ap.add_argument("--audit-log", default="triage-audit.jsonl")
    args = ap.parse_args(argv)
    import anthropic  # only needed for real runs; the tests use a fake client

    with open(args.audit_log, "a", encoding="utf-8") as f:
        result = triage(args.alert, anthropic.Anthropic(), approve=_ask,
                        audit=lambda e: f.write(json.dumps(e) + "\n"))
    print("\n" + result.summary)
    approved = [p for p in result.proposals if p.approved]
    if approved:
        print("\nApproved; run these yourself, then watch the dashboards:")
        for p in approved:
            print(f"  {p.command}")
    print(f"\n({result.turns} turns, stopped: {result.stopped}; audit log: {args.audit_log})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
