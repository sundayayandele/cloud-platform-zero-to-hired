## What you will be able to do

- Start every script with strict mode (`set -euo pipefail`) and explain what each part catches.
- Quote correctly, and explain how unquoted variables and empty variables have deleted real servers.
- Check inputs, fail early with a clear message, and clean up with `trap`.
- Write **idempotent** scripts: safe to run twice, or a hundred times, with the same result.
- Add a dry-run mode and confirmation for dangerous actions.
- Check scripts automatically with `shellcheck`, and log what a script did.

## Why this matters at work

A script runs the same commands much faster than a person, including the wrong ones. A famous early bug in a popular program's install script ran `rm -rf "$STEAMROOT/"*` with an empty variable on some machines, which became `rm -rf /*` and deleted users' files. Cloud teams run scripts against production at 3 a.m., in pipelines nobody is watching, and on hundreds of servers at once. A script that stops at the first error, refuses bad input and can safely be run again is the difference between automation that people trust and automation that causes incidents.

## 1. Strict mode

Put this at the top of every script, straight after the shebang:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

| Setting | What it does | The bug it prevents |
| --- | --- | --- |
| `-e` | Exit as soon as a command fails | The script carries on after `cd /backups` failed, and deletes files in the wrong folder |
| `-u` | Treat using an unset variable as an error | A typo like `$BAKUP_DIR` silently becomes empty |
| `-o pipefail` | A pipeline fails if **any** command in it fails, not just the last | `pg_dump ... \| gzip > backup.gz` "succeeds" with an empty backup because only `gzip`'s exit code counted |

`-e` has exceptions you should know: it doesn't trigger for commands inside an `if` condition, or on the left of `&&` and `||`. That's what you want (`if grep -q ...` shouldn't kill the script when nothing matches), but it means you still check important results deliberately.

When a command is **allowed** to fail, say so explicitly:

```bash
grep -c "ERROR" app.log || true          # 0 matches shouldn't stop the script
rm -f /tmp/old.lock                      # -f: no error if it doesn't exist
```

## 2. Quoting: the most important habit

Without quotes, Bash **splits** a variable's value on spaces and **expands** wildcards in it:

```bash
file="monthly report.csv"
rm $file          # tries to delete "monthly" and "report.csv": two wrong files
rm "$file"        # deletes the one file you meant
```

And an **empty** variable can turn a careful command into a disaster:

```bash
backup_dir=""                      # meant to be /var/backups/itlpay, but a setting was missing
rm -rf "$backup_dir"/*            # becomes rm -rf /*
```

Defences, in order:

```bash
set -u                                            # an unset variable stops the script
rm -rf "${backup_dir:?backup_dir is empty}"/*     # :? stops the script if it's empty or unset
[[ "$backup_dir" == /var/backups/* ]] || { echo "Refusing to clean $backup_dir" >&2; exit 1; }
```

`${var:?message}` is the simplest guard: if `var` is empty or unset, Bash prints the message and exits.

The rules:

- Quote every variable: `"$var"`, `"${var}"`, `"$@"`.
- Quote command substitutions: `"$(date +%F)"`.
- Use **arrays** for lists of things, especially options and file names:

```bash
opts=(--archive --compress --delete)
files=("monthly report.csv" "notes.txt")
rsync "${opts[@]}" "${files[@]}" lab:/srv/reports/
```

## 3. Check inputs and fail early

Validate everything before you change anything:

```bash
usage() { echo "Usage: $0 ENV (dev|staging|prod)" >&2; exit 2; }

[[ $# -eq 1 ]] || usage
env="$1"
case "$env" in dev|staging|prod) ;; *) usage ;; esac

command -v aws >/dev/null || { echo "The AWS CLI isn't installed" >&2; exit 1; }
[[ -r config/"$env".env ]] || { echo "No config for $env" >&2; exit 1; }
```

`command -v` checks a tool exists before the script depends on it. Use exit code `2` for "you called me wrongly" and `1` for "something failed", so callers can tell them apart.

## 4. Cleaning up with trap

Scripts create temporary files and lock files. If they stop half-way (an error, Ctrl+C), the mess stays. `trap` runs a command whenever the script exits, for whatever reason:

```bash
workdir=$(mktemp -d)                     # a unique, private temporary folder
trap 'rm -rf "$workdir"' EXIT

curl -sf -o "$workdir/rates.json" https://api.example/rates
# ... process the file ...
# The folder is removed when the script ends, even after an error
```

Never use fixed names like `/tmp/data.json` for temporary files: two runs would overwrite each other, and other users could interfere. `mktemp` gives a unique name with safe permissions.

A **lock** stops two copies of a script running at once (for example, a backup still running when the next one is scheduled):

```bash
exec 9> /var/lock/itlpay-backup.lock
flock -n 9 || { echo "Another backup is running" >&2; exit 1; }
```

## 5. Idempotent scripts: safe to run twice

An **idempotent** action gives the same result whether you run it once or many times. That matters because scripts get re-run: after a failure half-way, by a teammate who isn't sure it ran, or by a pipeline on every deploy. Write each step as "make sure this is true", not "do this":

| Not idempotent | Idempotent |
| --- | --- |
| `mkdir /srv/app` (fails the second time) | `mkdir -p /srv/app` |
| `useradd app` (fails if the user exists) | `id app &>/dev/null \|\| useradd --system app` |
| `echo "vm.swappiness=10" >> /etc/sysctl.conf` (adds a duplicate line each run) | `grep -qxF "vm.swappiness=10" /etc/sysctl.conf \|\| echo "vm.swappiness=10" >> /etc/sysctl.conf` |
| `ln -s /srv/app/v2 /srv/app/current` (fails if the link exists) | `ln -sfn /srv/app/v2 /srv/app/current` |
| `aws s3 mb s3://itlpay-logs` (fails if it exists) | Check first: `aws s3api head-bucket --bucket itlpay-logs 2>/dev/null \|\| aws s3 mb s3://itlpay-logs` |

This "check the current state, then change only what's different" idea is exactly what Terraform and Ansible do for you in Phase 2. Learning it in Bash first makes those tools make sense.

## 6. Dry runs and confirmation for dangerous actions

For anything that deletes or changes a lot, let people see what would happen first:

```bash
dry_run=true
[[ "${1:-}" == "--apply" ]] && dry_run=false

run() {
    if $dry_run; then echo "DRY RUN: $*"; else "$@"; fi
}

for f in /var/backups/itlpay/*.gz; do
    if [[ $(find "$f" -mtime +30) ]]; then
        run rm -- "$f"
    fi
done
$dry_run && echo "Nothing deleted. Run with --apply to delete."
```

Dry-run by default, `--apply` to act, is a good pattern for clean-up scripts. For production, ask for confirmation too:

```bash
if [[ "$env" == "prod" ]]; then
    read -r -p "Type the environment name to confirm: " answer
    [[ "$answer" == "prod" ]] || { echo "Cancelled"; exit 1; }
fi
```

`rm -- "$f"`: the `--` means "no more options", so a file whose name starts with `-` can't be mistaken for an option.

## 7. shellcheck and logging

**shellcheck** reads a script and points out bugs: missing quotes, unused variables, `$(cat file)` loops, and dozens more. Use it on every script, and in CI (Module 4):

```bash
sudo apt install -y shellcheck
shellcheck backup.sh
```

Fix every warning, or, if you're sure a warning is wrong, disable it for that one line with a comment explaining why (`# shellcheck disable=SC2086 # word splitting wanted here`).

Make scripts **say what they're doing**, with timestamps, to standard error, so the output can be read during an incident and kept in logs:

```bash
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >&2; }
log "Starting backup of $db to $target"
```

When a script runs from cron or systemd (topic 3.3), its output ends up in the journal or a log file, and those log lines are often the only record of what happened.

## 8. The template

Start new scripts from this:

```bash
#!/usr/bin/env bash
# name.sh: one line saying what it does
# Usage: name.sh [--apply] ARG
set -euo pipefail

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
usage() { echo "Usage: $0 [--apply] ARG" >&2; exit 2; }

apply=false
[[ "${1:-}" == "--apply" ]] && { apply=true; shift; }
[[ $# -eq 1 ]] || usage
arg="$1"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

log "Starting with $arg (apply=$apply)"
# ... the work, written as "make sure this is true" steps ...
log "Done"
```

## Practice

1. Take `health-report.sh` from topic 3.1, add strict mode, and run `shellcheck` on it. Fix every warning.
2. In a test folder, create `report 1.txt` and `report 2.txt`. Write a loop that deletes them **without** quotes and see what happens (use `echo rm` instead of `rm` so nothing is really deleted). Then fix it.
3. Write `make-user.sh USERNAME` that creates a system user, a folder `/srv/USERNAME` owned by it, and a line in `/etc/sudoers.d/` **only if** each doesn't already exist. Run it three times and show the result is the same each time. (Use a test machine: Multipass, WSL or Codespaces.)
4. Write `clean-old-backups.sh` that, in dry-run mode by default, lists `.gz` files older than 7 days in a folder passed as an argument, refuses any folder outside `/var/backups/`, and deletes only with `--apply`.
5. Demonstrate `pipefail`: run `false | true; echo $?` with and without `set -o pipefail` and explain the difference in your learning log.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [Bash Script BEST Practices You Need to Know, According to Google](https://www.youtube.com/watch?v=Y_erZnIhgKg) · Better Stack · 4 min. Bash best practices, based on Google's style guide.
- [Write Safer Scripts Using Shellcheck](https://www.youtube.com/watch?v=lHsftCXdjQU) · Mark Alexander · 3 min. Using shellcheck to find bugs in scripts.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Maintain a secure repository by using GitHub best practices](https://learn.microsoft.com/training/modules/maintain-secure-repository-github/)

**AWS (AWS Skill Builder):**

- [Getting Started with DevOps on AWS](https://skillbuilder.aws/learn/R4B13K95YQ/getting-started-with-devops-on-aws/38NHHYRV1R)

