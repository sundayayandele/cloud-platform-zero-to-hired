import json

import pytest
import requests

import checker


class FakeResponse:
    def __init__(self, status_code):
        self.status_code = status_code


class FakeSession:
    """Stands in for `requests`: returns a fixed status, or raises an error."""
    def __init__(self, status=200, error=None):
        self.status, self.error, self.calls = status, error, []

    def get(self, url, timeout, allow_redirects):
        self.calls.append((url, timeout))
        if self.error:
            raise self.error
        return FakeResponse(self.status)


def test_expected_status_is_ok():
    r = checker.check("api", "https://x.example", expect=200, session=FakeSession(200))
    assert r.ok and r.status == 200 and r.error == ""


def test_unexpected_status_fails():
    r = checker.check("api", "https://x.example", expect=200, session=FakeSession(503))
    assert not r.ok and r.status == 503


@pytest.mark.parametrize("error", [requests.ConnectionError(), requests.Timeout()])
def test_network_errors_fail_without_crashing(error):
    r = checker.check("api", "https://x.example", session=FakeSession(error=error))
    assert not r.ok and r.status is None and r.error == type(error).__name__


def test_timeout_is_passed_on():
    s = FakeSession(200)
    checker.check("api", "https://x.example", timeout=2.5, session=s)
    assert s.calls == [("https://x.example", 2.5)]


def test_load_checks_rejects_missing_url(tmp_path):
    cfg = tmp_path / "urls.json"
    cfg.write_text(json.dumps({"checks": [{"name": "no-url"}]}))
    with pytest.raises(SystemExit, match="needs 'name' and 'url'"):
        checker.load_checks(cfg)


def test_bad_config_exits_2(tmp_path):
    cfg = tmp_path / "urls.json"
    cfg.write_text("{not json")
    assert checker.main([str(cfg)]) == 2


def test_report_and_exit_code(tmp_path, monkeypatch):
    cfg = tmp_path / "urls.json"
    cfg.write_text(json.dumps({"checks": [{"name": "a", "url": "https://a.example"},
                                          {"name": "b", "url": "https://b.example"}]}))
    statuses = {"https://a.example": 200, "https://b.example": 500}
    monkeypatch.setattr(checker, "check", lambda name, url, expect, timeout:
                        checker.Result(name, url, statuses[url] == expect, statuses[url], 1))
    report = tmp_path / "report.json"
    assert checker.main([str(cfg), "--report", str(report)]) == 1
    data = json.loads(report.read_text())
    assert [r["ok"] for r in data] == [True, False]
