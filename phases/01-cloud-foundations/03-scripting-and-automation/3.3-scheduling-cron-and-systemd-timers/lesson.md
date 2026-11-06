## What you will be able to do

- Schedule a script with **cron**, and read and write cron schedules such as `30 2 * * 1-5`.
- Explain cron's environment (a short `PATH`, no terminal, a different shell) and avoid the bugs it causes.
- Capture a scheduled job's output and know where to look when it didn't run.
- Schedule jobs with **systemd timers** instead, and explain when each is the better choice.
- Handle time zones, overlapping runs and missed runs.
- Know the cloud equivalents: Amazon EventBridge Scheduler and Azure Functions timer triggers, and scheduled pipelines.

## Why this matters at work

Backups, log clean-up, certificate checks, reports, data refreshes and cost reports all run on a schedule. A scheduled job that silently stops working is one of the most dangerous failures in operations: nobody notices that backups stopped until the day they're needed. Knowing how to schedule reliably, and how to prove a job ran, is basic hygiene for a cloud engineer.

## 1. cron: the classic scheduler

**cron** runs commands at set times. Each user has a **crontab** (cron table):

```bash
crontab -l          # list your scheduled jobs
crontab -e          # edit them (choose nano if asked)
sudo crontab -l     # root's jobs
ls /etc/cron.d/     # system-wide job files (installed by packages and admins)
```

A crontab line is five time fields, then the command:

```text
┌───────── minute (0–59)
│ ┌─────── hour (0–23)
│ │ ┌───── day of month (1–31)
│ │ │ ┌─── month (1–12)
│ │ │ │ ┌─ day of week (0–7; 0 and 7 are Sunday)
│ │ │ │ │
30 2 * * 1-5  /home/ada/bin/backup.sh
```

| Schedule | Meaning |
| --- | --- |
| `*/5 * * * *` | Every 5 minutes |
| `0 * * * *` | Every hour, on the hour |
| `30 2 * * *` | 02:30 every day |
| `30 2 * * 1-5` | 02:30 Monday to Friday |
| `0 6 1 * *` | 06:00 on the 1st of every month |
| `0 9,17 * * *` | 09:00 and 17:00 every day |
| `@reboot` | Once, when the machine starts |

When in doubt, check a schedule at [crontab.guru](https://crontab.guru), which explains it in plain English.

Files in `/etc/cron.d/` have one extra field, the **user** to run as:

```text
30 2 * * * backup /usr/local/bin/itlpay-backup.sh
```

## 2. cron's environment: the classic bugs

A script that works perfectly when you run it can fail under cron, because cron runs it **differently**:

| Under cron | The bug | The fix |
| --- | --- | --- |
| A minimal `PATH` (often just `/usr/bin:/bin`) | `aws: command not found`, because the CLI is in `/usr/local/bin` | Use full paths, or set `PATH=...` at the top of the crontab or script |
| No terminal, no login files (`.bashrc` isn't read) | Environment variables you set in your shell are missing | Set them in the script, or load a config file explicitly |
| The default shell is `/bin/sh`, not Bash | Bash-only syntax in the crontab line fails | Keep crontab lines simple; put logic in a script with a Bash shebang |
| `%` has a special meaning in crontab lines | `date +%F` in the crontab line breaks | Escape it as `\%`, or move the command into a script |
| The working folder is the user's home | Relative paths point somewhere unexpected | Use absolute paths, or `cd` at the start of the script |

The safest pattern is a crontab line that only calls a script, and a script (with strict mode, topic 3.2) that sets up everything it needs.

## 3. Output and proof that it ran

Cron emails a job's output to the user, which on most servers goes nowhere. Send output to a log file instead:

```text
30 2 * * * /usr/local/bin/itlpay-backup.sh >> /var/log/itlpay-backup.log 2>&1
```

Or send it to the system journal with a tag, so it sits with everything else:

```text
30 2 * * * /usr/local/bin/itlpay-backup.sh 2>&1 | systemd-cat -t itlpay-backup
```

Then `journalctl -t itlpay-backup` shows every run.

When a job didn't run, check in this order:

1. **Did cron start it?** `journalctl -u cron --since today` (Ubuntu) shows each job it launched.
2. **Did it fail?** Look at the job's own log.
3. **Was the schedule what you think?** Paste it into crontab.guru. Check the **time zone** (section 6).
4. **Is the job in the right crontab** (yours, root's, or `/etc/cron.d/` with a user field)?

Logs prove a job ran; they don't tell you when it **stopped** running. For important jobs, add a **"dead man's switch"**: at the end of a successful run, the job checks in with a monitoring service (for example writing a timestamp a monitoring system watches, or calling a heartbeat URL). If no check-in arrives on time, someone is alerted. Phase 3 builds this into the platform's monitoring.

## 4. systemd timers

On modern Linux, **systemd timers** do the same job with some advantages. A timer is two files: a **service** (what to run) and a **timer** (when).

`/etc/systemd/system/itlpay-backup.service`:

```ini
[Unit]
Description=ITL Pay database backup

[Service]
Type=oneshot
User=backup
ExecStart=/usr/local/bin/itlpay-backup.sh
```

`/etc/systemd/system/itlpay-backup.timer`:

```ini
[Unit]
Description=Run the ITL Pay backup every night

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now itlpay-backup.timer
systemctl list-timers                       # all timers: next run, last run
sudo systemctl start itlpay-backup.service  # run it now, to test
journalctl -u itlpay-backup.service         # output of every run
systemd-analyze calendar "Mon..Fri 02:30"   # check a schedule and see the next run times
```

| | cron | systemd timer |
| --- | --- | --- |
| Setup | One line | Two small files |
| Logs | You arrange them | Automatic, in the journal, per run |
| Missed runs (machine was off) | Skipped | `Persistent=true` runs it at the next boot |
| Overlapping runs | Possible; you add `flock` (topic 3.2) | A service can't be started twice at once |
| Spreading load across many servers | You add `sleep $((RANDOM % 600))` | `RandomizedDelaySec=` |
| Resource limits, sandboxing, running as a user | You arrange them | Built-in unit options |
| Portability | Everywhere, including containers and macOS | Linux with systemd |

A good rule: for anything important on a Linux server, use a timer. Cron is fine for quick personal jobs and is still everywhere, so you must be able to read it.

## 5. Overlaps and missed runs

Two classic scheduling failures:

- **Overlap:** a job scheduled every 5 minutes sometimes takes 7. Two copies run at once and corrupt each other's work. Timers prevent this; with cron, use `flock`:

  ```text
  */5 * * * * flock -n /var/lock/sync.lock /usr/local/bin/sync.sh
  ```

- **Missed runs:** the server was off or rebooting at 02:30. Cron skips that night. A timer with `Persistent=true` catches up after boot. For jobs where a missed run matters (backups), you also want the dead man's switch from section 3.

## 6. Time zones

Servers usually run on **UTC**, and that's the right choice: logs from servers in different regions line up, and there's no daylight-saving confusion. Nigeria uses West Africa Time (UTC+1, no daylight saving), so `30 2 * * *` on a UTC server runs at 03:30 in Lagos.

```bash
timedatectl                      # the machine's time zone and whether the clock is synchronised
date -u                          # the time in UTC
TZ=Africa/Lagos date             # the time in Lagos
```

systemd timers can take a time zone in the schedule: `OnCalendar=*-*-* 02:30:00 Africa/Lagos`. Whatever you choose, write the time zone in the job's description, and make sure the clock is synchronised (`timedatectl` should say *System clock synchronized: yes*); a wrong clock also breaks TLS certificates (topic 2.4) and cloud API calls.

## 7. Scheduling in the cloud

You'll often schedule work without any server of your own:

| Need | AWS | Azure |
| --- | --- | --- |
| Run code on a schedule, serverless | **EventBridge Scheduler** triggering a Lambda function | **Azure Functions** with a **timer trigger** |
| Start or stop VMs at set times (to save money) | EventBridge Scheduler with Systems Manager automation | **Start/stop VMs** automation, or Azure Automation runbooks |
| Run a script on many VMs on a schedule | **Systems Manager** State Manager / Run Command | **Azure Automation** or Azure Machine Configuration |
| Scheduled pipeline jobs | GitHub Actions `schedule:` (cron syntax), CodePipeline | GitHub Actions `schedule:`, Azure Pipelines schedules |

They all use the same ideas: a schedule (often in cron syntax, sometimes with six fields including seconds on Azure Functions), something to run, logs, and alerts when a run fails. One saving used by almost every cloud team, and by you in Module 6, is a schedule that **stops development machines every evening** and starts them in the morning.

## Practice

1. Schedule a job with cron that appends the date and the free disk space to `~/disk.log` every 2 minutes. Check it's working after 6 minutes, then remove it.
2. Deliberately break it: use a command that isn't in cron's `PATH` (for example a script in `~/bin`) without the full path. Find the failure in `journalctl -u cron` or your log file, and fix it.
3. Turn `health-report.sh` (topic 3.1) into a systemd timer that runs every 15 minutes. Use `systemctl list-timers` and `journalctl -u` to prove it ran at least twice.
4. Use `systemd-analyze calendar` to check these schedules and see the next run times: every weekday at 07:00 Lagos time; the first Monday of each month at 09:00; every 10 minutes.
5. In your learning log, write how you would make sure the nightly database backup really runs every night, and how you'd find out within a day if it stopped.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [Linux/Mac Tutorial: Cron Jobs - How to Schedule Commands with crontab](https://www.youtube.com/watch?v=QZJ1drMQz1A) · Corey Schafer · 19 min. Scheduling commands with cron and crontab.
- [Introduction to systemd timers](https://www.youtube.com/watch?v=DixhIrgMy3M) · tutoriaLinux · 13 min. An introduction to systemd timers.

## Further learning (free)

Free, self-paced courses from the two clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn and a free AWS Builder ID for AWS Skill Builder to track your progress.

**Azure (Microsoft Learn):**

- [Automate development tasks by using GitHub Actions](https://learn.microsoft.com/training/modules/github-actions-automate-tasks/)

**AWS (AWS Skill Builder):**

- [AWS Systems Manager Getting Started](https://skillbuilder.aws/learn/1AG8ZGZN4Z/aws-systems-manager-getting-started/PKCXBQX7M5)

