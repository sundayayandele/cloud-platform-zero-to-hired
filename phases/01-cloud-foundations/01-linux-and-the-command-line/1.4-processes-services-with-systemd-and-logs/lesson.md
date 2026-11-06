## What you will be able to do

- Explain what a process is, and find which processes are running, using how much CPU and memory.
- Stop a stuck process safely with `kill`, and know when (and when not) to use `kill -9`.
- Run commands in the background and keep them running after you log out.
- Start, stop, restart and enable services with `systemctl`, and write a simple service unit of your own.
- Read logs with `journalctl`, filtered by service, time and priority.
- Work through a "the service is down" ticket in a calm, repeatable order.

## Why this matters at work

"The service is down" is the most common ticket a junior cloud engineer gets. The first five minutes are always the same: is the process running? What do its logs say? Is the machine out of memory, CPU or disk? Did it start again after the last reboot? This topic gives you the commands for each question. On every Linux virtual machine you build on AWS or Azure, `systemd` is what starts your application, restarts it when it crashes and keeps its logs.

## 1. Processes

A **process** is a running program. Each has a **process ID (PID)**, an owner (a user), a parent (the process that started it), and uses some CPU and memory.

```bash
ps aux                     # every process: user, PID, %CPU, %MEM, command
ps aux | grep nginx        # find one program's processes
pgrep -a python            # PIDs and command lines matching "python"
top                        # live view; press q to quit, M to sort by memory, P by CPU
htop                       # a friendlier top (sudo apt install -y htop)
pstree -p                  # processes as a family tree
```

In `top`, the header shows the **load average** (how many processes want the CPU, averaged over 1, 5 and 15 minutes; compare it with the number of CPU cores from `nproc`), total and free **memory**, and **swap** (disk used as overflow memory; heavy swap use makes everything slow).

Two more commands answer "is the machine itself healthy?":

```bash
free -h        # memory: total, used, available
df -h          # disk space on each mounted disk
uptime         # how long since boot, and the load average
```

## 2. Stopping processes: signals

You stop a process by sending it a **signal**:

```bash
kill 4321          # send SIGTERM (15): "please stop" — the program can clean up first
kill -9 4321       # send SIGKILL (9): stopped immediately by the kernel, no clean-up
pkill -f myapp.py  # signal every process whose command line matches
```

Always try a plain `kill` first and wait a few seconds. `kill -9` gives the program no chance to finish writing files, close database connections or release locks, which can leave data damaged. It's the last resort for a process that ignores SIGTERM.

You can only signal your own processes, unless you use `sudo`.

## 3. Foreground, background and staying alive

```bash
sleep 300 &        # & runs it in the background; the shell prints a job number and PID
jobs               # background jobs in this shell
fg %1              # bring job 1 to the foreground
# Ctrl+Z pauses the foreground job; then `bg` lets it continue in the background
```

Background jobs still die when you close the terminal or your SSH connection drops. For a long task on a remote server, run it inside **tmux**, which keeps your session alive on the server:

```bash
tmux new -s work       # start a session called "work"
# ... run your long command ...
# press Ctrl+B then D to detach; log out safely
tmux attach -t work    # later: reattach and see the output
```

On a slow or unstable connection, tmux is essential: a dropped connection no longer kills your work.

For anything that should run **permanently** (a web server, an application, an agent), don't use `&` or tmux. Use a service, below.

## 4. Services with systemd

**systemd** is the first process on almost every modern Linux system (PID 1). It starts everything else at boot and supervises long-running programs called **services** (or **units**).

```bash
systemctl status ssh              # is it running? since when? last log lines
sudo systemctl start nginx        # start now
sudo systemctl stop nginx         # stop now
sudo systemctl restart nginx      # stop and start (drops connections)
sudo systemctl reload nginx       # re-read configuration without stopping (if supported)
sudo systemctl enable nginx       # start automatically at boot
sudo systemctl enable --now nginx # enable and start in one go
systemctl is-active nginx         # prints active / inactive / failed
systemctl list-units --type=service --state=failed   # what has failed?
```

A classic mistake: **start** without **enable**. The service runs today, the server reboots for patching at 3 a.m., and the service doesn't come back. Always check both.

macOS has no systemd, and Codespaces runs in a container without it. WSL has it when enabled (recent Ubuntu on WSL enables it by default; check with `systemctl status`). If `systemctl` doesn't work for you, use a Multipass virtual machine (`multipass launch --name lab 24.04`, then `multipass shell lab`) or Killercoda's free Ubuntu playground in your browser.

## 5. Writing your own service

Suppose you have a small Python web app at `/opt/hello/app.py` that should always be running. First create a system user for it (topic 1.3), so it doesn't run as `root`:

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin hello
sudo mkdir -p /opt/hello
sudo tee /opt/hello/app.py > /dev/null <<'EOF'
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"hello from systemd\n")
HTTPServer(("0.0.0.0", 8080), H).serve_forever()
EOF
```

Then describe the service in a **unit file**:

```bash
sudo tee /etc/systemd/system/hello.service > /dev/null <<'EOF'
[Unit]
Description=Hello web app
After=network-online.target

[Service]
User=hello
ExecStart=/usr/bin/python3 /opt/hello/app.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload          # tell systemd about the new file
sudo systemctl enable --now hello
systemctl status hello
curl localhost:8080
```

`Restart=on-failure` means systemd restarts the app if it crashes, after 5 seconds. Test it: find the PID with `systemctl status hello`, run `sudo kill -9` on it, and watch systemd bring it back.

## 6. Logs with journalctl

systemd collects the output of every service in the **journal**:

```bash
journalctl -u hello                    # all logs for one service
journalctl -u hello -f                 # follow new lines (like tail -f)
journalctl -u hello --since "10 min ago"
journalctl -u hello --since today -p err   # only errors and worse
journalctl -b                          # since the last boot
journalctl -b -1 -p err                # errors from the boot before (why did it crash?)
journalctl --disk-usage                # how much space the journal uses
```

Priorities, from worst to least serious, are `emerg`, `alert`, `crit`, `err`, `warning`, `notice`, `info` and `debug`. `-p err` shows `err` and everything worse.

Many programs also write their own log files in `/var/log` (for example `/var/log/nginx/error.log`). Check both the journal and those files.

Logs grow forever unless they are **rotated**: `logrotate` (configured in `/etc/logrotate.d/`) renames old logs, compresses them and deletes the oldest. A full disk caused by an unrotated log is one of the most common outages in this job.

## 7. A routine for "the service is down"

Work through these in order, and write down what you find as you go:

1. **Is it running?** `systemctl status myapp`. Look at the state, the time it started, and the last log lines.
2. **What do the logs say?** `journalctl -u myapp --since "30 min ago"`. Read the **first** error, not the last; later errors are often caused by the first.
3. **Is the machine healthy?** `df -h` (disk full?), `free -h` (out of memory?), `uptime` and `top` (CPU overloaded?).
4. **Was it killed for memory?** `journalctl -k | grep -i "out of memory"` shows the kernel's OOM killer stopping processes.
5. **Did something change?** A new release, a configuration edit, a package upgrade (`/var/log/apt/history.log`), a reboot (`uptime`, `last reboot`).
6. **Fix, then confirm:** restart if appropriate, check `systemctl is-active`, make a real request (`curl`), and check `is-enabled` so it survives the next reboot.
7. **Write it up:** what broke, how you found it, what you did, and what would stop it happening again. This becomes your runbook (topic 4.3).

## Practice

1. Build the `hello` service from section 5. Kill it with `kill -9` and show that systemd restarts it. Then disable it, reboot (`sudo reboot`, or `wsl --shutdown` on Windows) and show it no longer starts.
2. Break it on purpose: change `ExecStart` to a path that doesn't exist, reload and restart. Use `systemctl status` and `journalctl` to find the error, and fix it.
3. Start `sleep 1000 &`, find its PID three different ways (`jobs -l`, `pgrep`, `ps aux | grep`), and stop it with a plain `kill`.
4. Start a tmux session, run `top` in it, detach, close the terminal, open a new one and reattach.
5. Write your own "service is down" checklist in your learning log, in your own words, from section 7.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [How To Manage Linux Services with systemctl and journalctl | Sysadmin Basics](https://www.youtube.com/watch?v=3kl62YSU9XA) · Akamai Developers · 14 min. Managing services with systemctl and reading logs with journalctl.
- [Linux Crash Course - The ps Command](https://www.youtube.com/watch?v=wYwGNgsfN3I) · Learn Linux TV · 15 min. Finding and understanding processes with ps.
- [Linux Crash Course - systemd: Using the systemctl command](https://www.youtube.com/watch?v=5JVBpXiYMKo) · Learn Linux TV · 26 min. Everything systemctl does, with examples.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Guided Project: Deploy and administer Linux virtual machines on Azure](https://learn.microsoft.com/training/modules/guided-project-deploy-administer-linux-virtual-machines-azure/)

**AWS (AWS Skill Builder):**

- [AWS Systems Manager Getting Started](https://skillbuilder.aws/learn/1AG8ZGZN4Z/aws-systems-manager-getting-started/PKCXBQX7M5)

