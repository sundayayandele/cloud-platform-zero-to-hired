## What you will be able to do

- Explain when to reach for Python instead of Bash.
- Set up a Python project with a virtual environment and pinned dependencies.
- Use Python's basics for operations work: variables, lists, dictionaries, loops, functions and errors.
- Read and write files and JSON, and work with paths using `pathlib`.
- Call REST APIs with `requests`, safely: timeouts, status checks, retries and secrets from the environment.
- Build a small command-line tool with `argparse` and `logging`, and run other programs with `subprocess`.
- Explain how the same skills drive AWS (`boto3`) and Azure (the Azure SDK for Python), ready for Module 6.

## Why this matters at work

Bash is perfect for gluing commands together, but it gets fragile once a task involves JSON, API calls, error handling or more than a page of logic. That's most cloud work: cloud providers are controlled through APIs that speak JSON, and both AWS and Azure publish official Python libraries. Cloud and DevOps job adverts list Python more than any other language. You don't need to become a software developer, but you do need to write small, reliable tools: a cost report, a clean-up of untagged resources, a check that every storage bucket is private.

## 1. Bash or Python?

| Use Bash when... | Use Python when... |
| --- | --- |
| You're mostly running other commands in order | You're processing data: JSON, CSV, API responses |
| It fits on a page | It needs functions, tests and error handling |
| It must run on a bare server with nothing installed | It calls cloud APIs (boto3, Azure SDK) |
| It's a container entry point or a CI step | Others will maintain it, or it'll grow |

Many teams use both: Python for the logic, a two-line Bash wrapper to run it.

## 2. A project with a virtual environment

Never install packages for your tools into the system Python (Ubuntu now blocks it for good reason). Give each project its own **virtual environment**:

```bash
sudo apt install -y python3-venv      # once, on Ubuntu
mkdir url-checker && cd url-checker
python3 -m venv .venv                 # create the environment in .venv/
source .venv/bin/activate             # use it in this terminal (your prompt shows (.venv))
pip install requests pytest
pip freeze > requirements.txt         # record exact versions
deactivate                            # when you're done
```

Anyone else (or a CI pipeline, or a server) recreates the same environment with `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`. Add `.venv/` to `.gitignore`: the environment is rebuilt, never committed.

**Pin versions** in `requirements.txt` (`requests==2.32.3`), so the tool doesn't break when a library releases a new version.

## 3. Python basics for operations

If you've never written Python, work through this section in the interactive shell (`python3`, then type lines; `exit()` to leave).

```python
region = "af-south-1"                      # text (str)
max_retries = 3                            # whole number (int)
threshold = 80.5                           # decimal (float)
enabled = True                             # True / False (bool)

servers = ["web-1", "web-2", "db-1"]       # a list: ordered
servers.append("web-3")
print(len(servers), servers[0], servers[-1])

tags = {"owner": "payments", "env": "prod"}   # a dictionary: key → value
print(tags["owner"])
print(tags.get("cost-centre", "missing"))     # .get gives a default instead of an error

for name in servers:
    if name.startswith("web"):
        print(f"{name} is a web server")       # f-string: values inside {}

untagged = [s for s in servers if s != "db-1"]  # a list comprehension: filter in one line

def percent(used: int, total: int) -> float:
    """Return used as a percentage of total."""
    return used * 100 / total

print(f"{percent(41, 50):.1f}%")              # 82.0%
```

Indentation (4 spaces) is part of the language: it marks which lines belong to an `if`, a loop or a function.

**Errors** are raised as exceptions; catch the ones you expect and let the rest stop the program:

```python
try:
    port = int(user_input)
except ValueError:
    print(f"Not a number: {user_input}")
```

## 4. Files, paths and JSON

`pathlib` handles paths on every operating system:

```python
from pathlib import Path

logs = Path("/var/log")
for f in sorted(logs.glob("*.log")):
    print(f.name, f.stat().st_size)

report = Path("reports") / "today.txt"      # / joins path parts
report.parent.mkdir(parents=True, exist_ok=True)
report.write_text("all good\n", encoding="utf-8")
print(report.read_text(encoding="utf-8"))

with open("/var/log/syslog", encoding="utf-8", errors="replace") as fh:
    for line in fh:                          # reads one line at a time, so huge files are fine
        if "error" in line.lower():
            print(line.rstrip())
```

**JSON** maps straight onto lists and dictionaries, which is why it's everywhere in the cloud:

```python
import json

config = json.loads(Path("urls.json").read_text(encoding="utf-8"))
print(config["checks"][0]["url"])

result = {"server": "web-1", "disk_percent": 82, "ok": False}
Path("result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
```

A command-line tool you'll use alongside Python is **jq**, which filters JSON in the terminal: `aws ec2 describe-instances | jq '.Reservations[].Instances[].InstanceId'` (topic 6.3).

## 5. Calling REST APIs safely

The `requests` library makes HTTP calls (topic 2.4) from Python:

```python
import os
import requests

r = requests.get("https://open.er-api.com/v6/latest/USD", timeout=10)
r.raise_for_status()                      # turn 4xx/5xx into an exception
rates = r.json()                          # parse the JSON body
print("USD to NGN:", rates["rates"]["NGN"])

token = os.environ["GITHUB_TOKEN"]        # secrets come from the environment, never the code
r = requests.get("https://api.github.com/user/repos",
                 headers={"Authorization": f"Bearer {token}"}, timeout=10)
```

The rules that separate a reliable tool from a fragile one:

- **Always set a `timeout`.** Without one, a call to a server that never answers waits forever, and so does your scheduled job.
- **Check the status** with `raise_for_status()` or by comparing `r.status_code`.
- **Retry only what's safe to retry**: timeouts and `429`/`503` responses, with a growing delay between attempts. Don't blindly retry a `POST` that creates a payment (topic 2.4's idempotency).
- **Never put secrets in code or Git.** Read them from environment variables or a secret store (AWS Secrets Manager, Azure Key Vault in Module 6).
- **Handle paging.** APIs return large lists in pages; follow the "next" link or token until there are no more.

A simple retry with backoff:

```python
import time

def get_with_retry(url: str, attempts: int = 4) -> requests.Response:
    for i in range(attempts):
        try:
            r = requests.get(url, timeout=10)
            if r.status_code not in (429, 502, 503, 504):
                return r
        except (requests.ConnectionError, requests.Timeout):
            pass
        time.sleep(2 ** i)                 # wait 1, 2, 4, 8 seconds
    raise RuntimeError(f"Gave up on {url} after {attempts} attempts")
```

## 6. A real tool: the URL checker

The course repository has a complete example in `labs/url-checker/`: `checker.py` reads a list of URLs from `urls.json`, checks each one, logs the results and writes a JSON report. Read it now; it's about 90 lines. It uses everything in this topic, plus three standard pieces every tool should have:

- **`argparse`** for command-line options, with `--help` for free:

  ```python
  p = argparse.ArgumentParser(description="Check that a list of URLs are up")
  p.add_argument("config", type=Path)
  p.add_argument("--timeout", type=float, default=5.0)
  args = p.parse_args()
  ```

- **`logging`** instead of `print` for messages, with timestamps and levels (`DEBUG`, `INFO`, `WARNING`, `ERROR`), so `--verbose` can turn on detail.
- **Exit codes** like a good Bash script: `0` all passed, `1` some checks failed, `2` bad configuration. A scheduler or pipeline can act on them.

```bash
cd labs/url-checker
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python checker.py urls.json --report report.json
echo $?
```

## 7. Running other programs: subprocess

Sometimes the easiest way to get information is an existing command. `subprocess.run` runs it and gives you the output:

```python
import subprocess

out = subprocess.run(["df", "--output=pcent", "/"], capture_output=True, text=True, check=True)
used = int(out.stdout.splitlines()[1].strip().rstrip("%"))
```

Pass the command as a **list** (not one string with `shell=True`): then file names with spaces, or text from users, can't be misread as extra commands. `check=True` raises an error if the command fails, like `set -e` in Bash.

## 8. The same skills on AWS and Azure

In Module 6 you'll use the clouds' Python libraries. They look like this (no need to run them yet):

```python
# AWS: list S3 buckets
import boto3
s3 = boto3.client("s3")
for b in s3.list_buckets()["Buckets"]:
    print(b["Name"])

# Azure: list storage accounts
from azure.identity import DefaultAzureCredential
from azure.mgmt.storage import StorageManagementClient
client = StorageManagementClient(DefaultAzureCredential(), subscription_id)
for acct in client.storage_accounts.list():
    print(acct.name)
```

Both find credentials automatically from the environment, your CLI login, or (on a cloud VM) its role or managed identity, so keys never appear in the code. The patterns from this topic (loops over JSON-like results, paging, timeouts, retries, exit codes) are exactly what you'll use with them.

## Practice

1. Set up `labs/url-checker` in a virtual environment and run it. Add two URLs of your own to `urls.json`, including one that should fail, and read the report.
2. Write `rates.py` that gets today's USD rates from `https://open.er-api.com/v6/latest/USD` and prints the rates for NGN, GHS, KES and ZAR, with a timeout and a clear error if the API is down.
3. Write `big_files.py FOLDER --min-mb 50` that lists files larger than the limit, largest first, using `pathlib` and `argparse`.
4. Rewrite `health-report.sh` (topic 3.1) as `health_report.py`, producing a JSON report. Which version is easier to extend, and why?
5. Read a JSON file of fake cloud resources (make one with ten entries, each with `name`, `type` and `tags`) and print every resource missing an `owner` tag. This is a real job you'll do in Phase 3 (FinOps).

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [Python Virtual Environments - Full Tutorial for Beginners](https://www.youtube.com/watch?v=Y21OR1OPC9A) · Tech With Tim · 9 min. Python virtual environments, from scratch.
- [Python Requests Tutorial: Request Web Pages, Download Images, POST Data, Read JSON, and More](https://www.youtube.com/watch?v=tb8gHvYlCFs) · Corey Schafer · 25 min. Calling web APIs and reading JSON with Python requests.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Write your first Python code](https://learn.microsoft.com/training/modules/write-first-python-code/)
- [Work with data in Python](https://learn.microsoft.com/training/modules/work-with-data-python/)

**AWS (AWS Skill Builder):**

- [Build with AWS Command Line Interface (AWS CLI)](https://skillbuilder.aws/learn/AVW7M7MTWY/build-with-aws-command-line-interface-aws-cli/BBYQYTJG3M)

