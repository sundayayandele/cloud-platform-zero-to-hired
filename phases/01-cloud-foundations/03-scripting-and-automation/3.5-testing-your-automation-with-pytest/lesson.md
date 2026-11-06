## What you will be able to do

- Explain why automation code needs tests, and what makes a test worth having.
- Write and run tests with **pytest**: assertions, test files, fixtures and parametrised tests.
- Test code that calls networks or clouds without calling them, by passing in or replacing ("faking") those parts.
- Test failure paths: bad input, timeouts, errors and exit codes.
- Check Bash scripts with `shellcheck` and simple tests with `bats`.
- Run tests and linters automatically on every push, ready for Module 4's pipelines.

## Why this matters at work

Automation changes production. A clean-up script with an off-by-one bug deletes the wrong backups; a cost report that crashes on an empty page hides a bill. Tests are how you change a script with confidence, and how a reviewer knows your change won't break it. Teams increasingly treat infrastructure code like application code: every change goes through tests and a pipeline before it runs (Phase 2's Terraform tests and policy checks are the same idea). Showing tests in your portfolio repositories tells an employer you can be trusted with production.

## 1. What to test in automation code

Not everything needs a test. Focus on:

- **Decisions:** "is this file old enough to delete?", "is this resource missing an owner tag?", "did this check pass?"
- **Parsing:** turning command output, JSON or config files into values.
- **Failure paths:** bad config, network errors, timeouts, empty results. These are where scripts break at 3 a.m.
- **Exit codes:** schedulers and pipelines act on them, so they're part of your tool's contract.

Keep the logic in **small functions** that take inputs and return outputs. A function that decides "delete or keep" is easy to test; a 200-line script that decides and deletes in one go isn't. That's the most important design idea in this topic.

## 2. pytest basics

Install pytest in your project's virtual environment (topic 3.4): `pip install pytest`.

pytest finds files named `test_*.py`, runs every function whose name starts with `test_`, and reports which **assertions** failed:

```python
# tests/test_disk.py
from health import percent, needs_attention

def test_percent():
    assert percent(41, 50) == 82.0

def test_needs_attention_at_limit():
    assert needs_attention(used_percent=80, limit=80) is True

def test_ok_below_limit():
    assert needs_attention(used_percent=79, limit=80) is False
```

```bash
pytest              # run all tests
pytest -q           # quieter
pytest -k limit     # only tests with "limit" in the name
pytest -x           # stop at the first failure
pytest -v           # list each test
```

When an assertion fails, pytest shows the values on both sides, so you can usually see the bug without adding prints. Test the **edges**: exactly at the limit, zero, empty lists, the largest value.

## 3. Checking errors are raised

```python
import pytest
from health import percent

def test_percent_of_zero_total_is_an_error():
    with pytest.raises(ZeroDivisionError):
        percent(1, 0)
```

`pytest.raises` passes only if the code inside raises that error. You can also check the message: `pytest.raises(SystemExit, match="needs 'name' and 'url'")`.

## 4. Parametrised tests: one test, many cases

```python
import pytest
from cleanup import should_delete

@pytest.mark.parametrize("age_days, keep_days, expected", [
    (31, 30, True),
    (30, 30, False),     # exactly the limit: keep
    (0, 30, False),
    (400, 365, True),
])
def test_should_delete(age_days, keep_days, expected):
    assert should_delete(age_days, keep_days) is expected
```

Each row runs as a separate test, and pytest reports which row failed.

## 5. Fixtures: temporary files and folders

A **fixture** gives a test something it needs. pytest has useful ones built in; `tmp_path` is a fresh empty folder for each test, deleted afterwards:

```python
import json

def test_bad_config_exits_2(tmp_path):
    cfg = tmp_path / "urls.json"
    cfg.write_text("{not json")
    assert checker.main([str(cfg)]) == 2
```

Never test against real folders like `/var/backups` or your home folder. A test that deletes files must only ever see files it created itself.

## 6. Testing without the network or the cloud

Tests must be **fast, repeatable and free**: they can't depend on a website being up, or create real cloud resources (which cost money and need credentials). Replace the outside world with a **fake**.

The simplest way is to design for it: let the function accept the thing that does the calling. In `labs/url-checker/checker.py`, `check()` takes a `session` argument, which is `requests` in real use. The tests pass a fake instead:

```python
class FakeResponse:
    def __init__(self, status_code):
        self.status_code = status_code

class FakeSession:
    """Stands in for `requests`: returns a fixed status, or raises an error."""
    def __init__(self, status=200, error=None):
        self.status, self.error = status, error

    def get(self, url, timeout, allow_redirects):
        if self.error:
            raise self.error
        return FakeResponse(self.status)

def test_unexpected_status_fails():
    r = checker.check("api", "https://x.example", expect=200, session=FakeSession(503))
    assert not r.ok and r.status == 503

@pytest.mark.parametrize("error", [requests.ConnectionError(), requests.Timeout()])
def test_network_errors_fail_without_crashing(error):
    r = checker.check("api", "https://x.example", session=FakeSession(error=error))
    assert not r.ok and r.status is None
```

When you can't change the design, pytest's **`monkeypatch`** fixture replaces a function or attribute just for one test:

```python
def test_report_and_exit_code(tmp_path, monkeypatch):
    monkeypatch.setattr(checker, "check", lambda name, url, expect, timeout:
                        checker.Result(name, url, url.endswith("a.example"), 200, 1))
    ...
```

`monkeypatch.setenv("GITHUB_TOKEN", "test-token")` sets an environment variable for one test, which is how you test code that reads secrets, without real secrets.

For cloud code later, there are dedicated fakes: **moto** pretends to be AWS for `boto3` in tests, and **LocalStack** runs a local imitation of many AWS services. For Azure, **Azurite** emulates Azure Storage. You'll use them in Module 6.

Run the URL checker's tests now:

```bash
cd labs/url-checker
.venv/bin/pytest -v
```

All 8 should pass in well under a second, with no network calls.

## 7. Testing Bash scripts

For Bash, the first line of defence is **shellcheck** (topic 3.2), which finds most bugs without running anything. For behaviour, **bats** (Bash Automated Testing System) runs scripts and checks their output and exit codes:

```bash
sudo apt install -y bats
```

```bash
# tests/check-url.bats
@test "prints usage and exits 2 without arguments" {
    run ./check-url.sh
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage"* ]]
}

@test "reports DOWN for a URL that can't be reached" {
    run ./check-url.sh http://127.0.0.1:9
    [ "$status" -eq 1 ]
    [[ "$output" == *"DOWN"* ]]
}
```

```bash
bats tests/
```

## 8. Run the checks on every push

Tests only protect you if they run. In Module 4 you'll add a GitHub Actions workflow that runs on every push and pull request; this is what it will look like for the URL checker:

```yaml
# .github/workflows/checks.yml
name: checks
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install -r labs/url-checker/requirements.txt
      - run: cd labs/url-checker && pytest -q
      - run: shellcheck scripts/*.sh
```

A red cross on a pull request then means "don't merge yet", and nobody has to remember to run the tests.

## Practice

1. Set up `labs/url-checker`, run its tests, then break `check()` on purpose (for example, compare `r.status_code != expect`) and watch which tests fail. Undo it.
2. Add a test for a URL that redirects: the fake returns `301`, and the check expects `200`. Should it pass or fail? Decide, test it, and explain in a comment.
3. Write `cleanup.py` with a function `should_delete(age_days, keep_days)` and a function `files_to_delete(folder, keep_days)` that uses file modification times. Test both, using `tmp_path` and `os.utime` to make files look old.
4. Write a test that uses `monkeypatch.setenv` to check that your `rates.py` (topic 3.4) fails with a clear message when a required environment variable is missing (add one, for example `RATES_API_URL`).
5. Write two bats tests for your `check-url.sh` from topic 3.1, and make `shellcheck` pass on it.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [getting started with pytest (beginner - intermediate) anthony explains #518](https://www.youtube.com/watch?v=mzlH8lp4ISA) · anthonywritescode · 13 min. Getting started with pytest.
- [Please Learn How To Write Tests in Python… • Pytest Tutorial](https://www.youtube.com/watch?v=EgpLj86ZHFQ) (optional, longer) · Tech With Tim · 33 min. Writing tests in Python with pytest, in depth.

## Further learning (free)

Free, self-paced courses from the two clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn and a free AWS Builder ID for AWS Skill Builder to track your progress.

**Azure (Microsoft Learn):**

- [Build continuous integration workflows by using GitHub Actions](https://learn.microsoft.com/training/modules/github-actions-ci/)

**AWS (AWS Skill Builder):**

- [Getting Started with DevOps on AWS](https://skillbuilder.aws/learn/R4B13K95YQ/getting-started-with-devops-on-aws/38NHHYRV1R)

