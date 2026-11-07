## What you will be able to do

- Write, run and share a Bash script, with a shebang line and the right permissions.
- Use variables, command substitution and arguments (`$1`, `$@`, `$#`).
- Make decisions with `if`, `test` (`[[ ]]`) and exit codes, and handle several cases with `case`.
- Repeat work with `for` and `while` loops, including reading a file line by line.
- Organise a script into functions, and print clear messages and a usage line.
- Turn a set of commands you type every week into a script a teammate can run.

## Why this matters at work

Cloud engineers automate anything they do more than twice: checking disk space on twenty servers, rotating logs, creating users, collecting diagnostics during an incident, tagging cloud resources. Bash is installed on every Linux server, every build runner and every container you'll touch, so a Bash script runs anywhere without installing anything. Even in teams that use Terraform and Python for most things, the glue between steps (in CI pipelines, container entry points and server start-up scripts on AWS and Azure) is usually Bash.

## 1. Your first script

Create `hello.sh`:

```bash
#!/usr/bin/env bash
# hello.sh: greet the user and show where we are
echo "Hello, $USER"
echo "You are on $(hostname), in $(pwd)"
```

Run it:

```bash
chmod +x hello.sh      # make it executable (topic 1.3)
./hello.sh             # run it from the current folder
bash hello.sh          # or run it with bash explicitly
```

The first line, the **shebang** (`#!`), says which program runs the script. `#!/usr/bin/env bash` finds `bash` wherever it is installed, which is more portable than `#!/bin/bash`. Use Bash, not plain `sh`, for the scripts in this course; some features below are Bash-only.

You run it as `./hello.sh` because the current folder isn't searched for commands (that's a security feature). To run your scripts by name from anywhere, put them in `~/bin` or `~/.local/bin`, which Ubuntu adds to your `PATH`.

## 2. Variables

```bash
name="ITL Pay"           # no spaces around =
region="af-south-1"
echo "Deploying $name to $region"
echo "Backup file: ${name}-backup.tar.gz"   # braces separate the name from the text after it
```

Rules that catch everyone:

- **No spaces around `=`**. `name = "x"` runs a command called `name`.
- **Always put variables in double quotes** when you use them: `"$name"`. Topic 3.2 explains why; for now, just do it.
- Single quotes keep text **exactly** as typed: `echo '$HOME'` prints `$HOME`; `echo "$HOME"` prints `/home/ada`.
- By convention, your own variables are lowercase; **environment variables** (shared with programs you start) are UPPERCASE: `PATH`, `HOME`, `USER`. Make one with `export`:

```bash
export AWS_REGION="af-south-1"   # programs started from here (like the AWS CLI) can read it
```

**Command substitution** puts a command's output into a variable:

```bash
today=$(date +%F)                # 2026-11-06
free_gb=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')
echo "Free space on / today ($today): ${free_gb} GB"
```

**Arithmetic** uses `$(( ))`:

```bash
count=5
count=$((count + 1))
echo $((free_gb * 1024)) MB
```

## 3. Arguments

Values passed to a script are in numbered variables:

| Variable | Meaning |
| --- | --- |
| `$0` | The script's own name |
| `$1`, `$2`, ... | The first, second, ... argument |
| `$#` | How many arguments there are |
| `"$@"` | All arguments, each kept separate (use this form) |

```bash
#!/usr/bin/env bash
# greet.sh NAME [GREETING]
name="$1"
greeting="${2:-Hello}"          # default to "Hello" if $2 is empty
echo "$greeting, $name"
```

`${2:-Hello}` means "use `$2`, or `Hello` if it's empty or missing". It's the neatest way to give defaults.

## 4. Exit codes and decisions

Every command finishes with an **exit code**: `0` means success, anything else means failure. `$?` holds the last one:

```bash
grep -q "ERROR" app.log
echo $?        # 0 if found, 1 if not found, 2 if the file is missing
```

`if` runs a command and checks its exit code:

```bash
if grep -q "ERROR" app.log; then
    echo "Errors found"
else
    echo "No errors"
fi
```

For comparisons, use `[[ ]]` (Bash's test command):

```bash
if [[ -f /etc/nginx/nginx.conf ]]; then echo "nginx is configured"; fi
if [[ ! -d /var/backups/itlpay ]]; then mkdir -p /var/backups/itlpay; fi
if [[ "$env" == "prod" ]]; then echo "Careful: production"; fi
if (( free_gb < 5 )); then echo "Low disk space"; fi
```

| Test | True when |
| --- | --- |
| `-f path` | It's a regular file |
| `-d path` | It's a directory |
| `-e path` | It exists |
| `-x path` | It's executable |
| `-z "$var"` | The variable is empty |
| `-n "$var"` | The variable isn't empty |
| `"$a" == "$b"` | Strings are equal (`!=` for not equal) |
| `(( a > b ))` | Numbers compare (`<`, `>=`, `==`, ...) inside `(( ))` |

You can chain with `&&` (run the next only if this succeeded) and `||` (only if it failed):

```bash
mkdir -p "$dir" && cd "$dir"
[[ -n "$1" ]] || { echo "Usage: $0 NAME" >&2; exit 1; }
```

`>&2` sends a message to **standard error**, which is where error messages belong. `exit 1` stops the script with a failure code, so whatever called it (a pipeline, cron, another script) knows it failed.

`case` handles several choices cleanly:

```bash
case "$1" in
    start)   echo "Starting" ;;
    stop)    echo "Stopping" ;;
    status)  systemctl status myapp ;;
    *)       echo "Usage: $0 {start|stop|status}" >&2; exit 1 ;;
esac
```

## 5. Loops

**for** goes through a list:

```bash
for env in dev staging prod; do
    echo "Checking $env"
done

for file in /var/log/*.log; do
    echo "$file: $(wc -l < "$file") lines"
done

for i in {1..5}; do echo "Attempt $i"; done
```

**while** repeats as long as a command succeeds. Here it retries a health check until it passes or gives up:

```bash
attempt=1
until curl -sf http://localhost:8080/health > /dev/null; do
    if (( attempt >= 10 )); then echo "App didn't become healthy" >&2; exit 1; fi
    echo "Waiting for the app (attempt $attempt)..."
    sleep 3
    attempt=$((attempt + 1))
done
echo "App is healthy"
```

(`until` is `while` with the condition reversed.) Waiting for something to be ready, with a limit, is one of the most common patterns in deployment scripts.

**Reading a file line by line**: the correct form is:

```bash
while IFS= read -r server; do
    echo "Checking $server"
done < servers.txt
```

`IFS=` keeps spaces at the start and end of lines, and `-r` stops backslashes being treated specially. Don't use `for line in $(cat file)`: it splits on every space, not on lines.

## 6. Functions

Functions name a block of code so you can reuse it and read the script top to bottom:

```bash
log() {
    echo "$(date '+%F %T') $*"
}

check_disk() {
    local mount="$1" limit="$2"
    local used
    used=$(df --output=pcent "$mount" | tail -1 | tr -dc '0-9')
    if (( used >= limit )); then
        log "WARNING: $mount is ${used}% full (limit ${limit}%)"
        return 1
    fi
    log "OK: $mount is ${used}% full"
}

check_disk / 80
check_disk /var 90
```

- Arguments to a function are `$1`, `$2`... inside it, like a script's.
- `local` keeps a variable inside the function, so it can't clash with others.
- `return` sets the function's exit code (0 for success).

## 7. A complete example: a server health report

Put it all together in `health-report.sh`, a script you might run on every server each morning:

```bash
#!/usr/bin/env bash
# health-report.sh [DISK_LIMIT_PERCENT]
# Prints a short health report and exits 1 if anything needs attention.

limit="${1:-80}"
problems=0

log() { echo "$(date '+%F %T') $*"; }

log "Health report for $(hostname)"

# Disk usage on every real file system
while read -r mount pct; do
    used="${pct%\%}"                      # strip the % sign
    if (( used >= limit )); then
        log "DISK  $mount is ${used}% full"
        problems=$((problems + 1))
    fi
done < <(df --output=target,pcent -x tmpfs -x devtmpfs | tail -n +2)

# Memory: available as a percentage of total
read -r total avail < <(free -m | awk '/^Mem:/ {print $2, $7}')
avail_pct=$((avail * 100 / total))
if (( avail_pct < 10 )); then
    log "MEMORY only ${avail_pct}% available"
    problems=$((problems + 1))
fi

# Failed services
failed=$(systemctl list-units --type=service --state=failed --no-legend 2>/dev/null | wc -l)
if (( failed > 0 )); then
    log "SERVICES $failed failed"
    problems=$((problems + 1))
fi

if (( problems == 0 )); then
    log "All checks passed"
else
    log "$problems problem(s) found"
    exit 1
fi
```

Two new pieces: `${pct%\%}` removes a trailing `%` from the value (Bash can trim text without calling other programs), and `< <(command)` feeds a command's output into a `while` loop without starting a separate shell, so `problems` keeps its value after the loop.

## Practice

1. Write `greet.sh` from section 3. Make it print a usage message to standard error and exit 1 when no name is given.
2. Write `check-url.sh URL` that prints `UP` and exits 0 if `curl -sf` succeeds, or prints `DOWN` and exits 1 if not. Run it against `https://itlearning.tech` and a URL that doesn't exist, and check `$?` each time.
3. Create `servers.txt` with three host names (for example `localhost`, `itlearning.tech`, `no-such-host.example`). Write a loop that reads it and reports whether each name resolves (`getent hosts`).
4. Write `wait-for-port.sh HOST PORT [TRIES]` that waits until a TCP port accepts connections (use `nc -z`), with a limit, and exits 1 if it never does. Test it with `python3 -m http.server 8000` started a few seconds later in another terminal.
5. Run `health-report.sh` from section 7 with a limit of `1` so it reports problems. Then extend it with one check of your own (for example, "the `ssh` service is active", or "load average is below the number of CPUs").
6. Put your scripts in a folder `scripts/` in your learning-log repository, with a one-line description of each in the README.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [you need to learn BASH Scripting RIGHT NOW!! // EP 1](https://www.youtube.com/watch?v=SPwyp2NG-bE) · NetworkChuck · 12 min. A first Bash script, from zero.
- [Bash Scripting Tutorial for Beginners](https://www.youtube.com/watch?v=tK9Oc6AEnR4) (optional, longer) · freeCodeCamp.org · 48 min. A complete Bash scripting course for beginners.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Guided project: Manage Azure resources with Cloud Shell and the Azure CLI](https://learn.microsoft.com/training/modules/guided-project-manage-resources-cloud-shell-cli/)

**AWS (AWS Skill Builder):**

- [AWS Command Line Interface (AWS CLI) Getting Started](https://skillbuilder.aws/learn/HNQT94X934/aws-command-line-interface-aws-cli-getting-started/QHT6C7ZHDA)

