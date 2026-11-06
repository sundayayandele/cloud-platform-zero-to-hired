## What you will be able to do

- Move around the Linux file system and explain what the main top-level folders (`/etc`, `/var/log`, `/home`, `/tmp`) are for.
- Create, copy, move, rename and delete files and folders safely, using absolute and relative paths.
- Read files of any size with `cat`, `less`, `head` and `tail`, and follow a log as it grows with `tail -f`.
- Find files with `find` and text inside files with `grep`.
- Chain commands with pipes (`|`) and send output to files with redirection (`>`, `>>`, `2>`).
- Answer real questions about a log file in one line: "how many errors today?", "which IP address made the most requests?"

## Why this matters at work

Most of a cloud engineer's troubleshooting is reading text: configuration files, logs, command output. When a payment service starts failing at 9 a.m., the first question is "what changed and what do the logs say?", and the answer usually comes from `grep`, `tail` and a couple of pipes, on a server with no graphical tools at all. People who can slice a 2 GB log file in seconds are the people teams call first.

## 1. The file system is one tree

Linux has no drive letters. Everything hangs from one **root** folder, written `/`. Disks, USB sticks and network storage are attached ("mounted") somewhere inside that tree.

| Folder | What lives there |
| --- | --- |
| `/home/ada` | Your home folder (shortcut: `~`). Your files go here |
| `/root` | The home folder of the `root` (administrator) user |
| `/etc` | System-wide configuration files, as plain text |
| `/var/log` | Log files |
| `/var/lib` | Data that services keep (databases, Docker images) |
| `/tmp` | Temporary files; may be emptied on reboot |
| `/usr/bin`, `/bin` | Programs (commands) |
| `/opt` | Software installed outside the package manager |
| `/proc`, `/sys` | Live information about the running system, shown as files |
| `/mnt`, `/media` | Places where extra disks are mounted |

A **path** names a file. An **absolute path** starts at `/` and works from anywhere: `/etc/hostname`. A **relative path** starts from where you are now: if you're in `/etc`, then `hostname` means the same file. Two special names help: `.` is "this folder" and `..` is "the folder above".

```bash
pwd                 # where am I?
cd /var/log         # go to an absolute path
cd ..               # up one level: now in /var
cd ~                # home (just `cd` does the same)
cd -                # back to the previous folder
ls                  # list this folder
ls -la              # long format, including hidden files (names starting with .)
ls -lh /var/log     # human-readable sizes (K, M, G)
tree -L 2 ~         # a tree view, 2 levels deep (sudo apt install -y tree)
```

In `ls -l` output, the first character tells you the type: `-` is a file, `d` a directory (folder), `l` a symbolic link (a shortcut to another path).

## 2. Creating, copying, moving and deleting

```bash
mkdir lab                     # make a folder
mkdir -p lab/app/config       # make nested folders in one go
touch lab/notes.txt           # create an empty file (or update its time)
cp lab/notes.txt lab/notes.bak        # copy a file
cp -r lab lab-copy                    # copy a folder and everything in it
mv lab/notes.bak lab/app/             # move a file
mv lab-copy lab-old                   # rename (a move within the same folder)
rm lab/app/notes.bak                  # delete a file
rm -r lab-old                         # delete a folder and its contents
rmdir lab/app/config                  # delete an empty folder
```

**There is no recycle bin.** `rm` deletes straight away. Three habits protect you:

- Run `ls` with the same path first, to see exactly what will be deleted.
- Use `rm -i` (asks before each file) when you're unsure.
- Never run `rm -rf` with a path built from a variable you haven't checked; topic 3.2 shows how a missing variable has deleted whole servers.

Names with spaces need quotes: `mkdir "my notes"`, or better, avoid spaces in names you create (`my-notes`).

**Wildcards** match many names at once. The shell expands them before the command runs:

```bash
ls /var/log/*.log      # every name ending in .log
ls report-202?.csv     # ? matches one character
ls app-{dev,prod}.yaml # braces: app-dev.yaml app-prod.yaml
```

## 3. Reading files

```bash
cat /etc/hostname          # print a whole (short) file
less /var/log/syslog       # page through a long file: space, b, /search, n, q
head -n 20 access.log      # first 20 lines
tail -n 50 access.log      # last 50 lines
tail -f /var/log/syslog    # follow: show new lines as they arrive (Ctrl+C to stop)
wc -l access.log           # count lines
file mystery.bin           # what kind of file is it?
du -sh /var/log            # how much space a folder uses
df -h                      # free space on each mounted disk
```

`tail -f` is the command you'll run most during incidents: open the service's log, make a request, and watch what it writes.

To edit files in the terminal, use **nano** (easy: the shortcuts are shown at the bottom; Ctrl+O saves, Ctrl+X exits). You'll also meet **vim** on servers; learn at least how to get out of it: press Esc, type `:q!` and Enter to quit without saving, or `:wq` to save and quit.

## 4. Finding files and text

`find` searches for files by name, type, size or age:

```bash
find ~ -name "*.txt"                   # .txt files under your home folder
find /var/log -type f -size +100M      # files bigger than 100 MB
find /tmp -type f -mtime +7            # files not changed for over 7 days
find . -name "*.log" -mmin -30         # logs changed in the last 30 minutes
```

`grep` searches **inside** files for lines that match:

```bash
grep "ERROR" app.log            # lines containing ERROR
grep -i "timeout" app.log       # ignore upper/lower case
grep -c "ERROR" app.log         # count matching lines
grep -n "ERROR" app.log         # show line numbers
grep -v "health" access.log     # lines that do NOT match
grep -r "db_host" /etc/myapp/   # search every file in a folder
grep -E "ERROR|FATAL" app.log   # either word (extended pattern)
```

## 5. Pipes and redirection: the real power

Every command reads from **standard input** and writes to **standard output** (normal results) and **standard error** (error messages). You can connect them.

A **pipe** (`|`) sends one command's output into the next command:

```bash
grep "ERROR" app.log | wc -l                 # how many errors?
ls -l /var/log | sort -k5 -n | tail -5       # the 5 largest entries
history | grep docker                        # docker commands you've run
```

**Redirection** sends output to a file:

```bash
grep "ERROR" app.log > errors.txt      # write (replaces the file)
grep "WARN" app.log >> errors.txt      # append (adds to the end)
find / -name "*.conf" 2> /dev/null     # throw away error messages
some-command > out.txt 2>&1            # both output and errors into one file
```

`/dev/null` is a special file that discards everything written to it.

A few more tools make pipes useful:

| Command | What it does |
| --- | --- |
| `sort` | Sort lines (`-n` numerically, `-r` reverse, `-k3` by the 3rd column) |
| `uniq -c` | Collapse repeated adjacent lines and count them (sort first) |
| `cut -d' ' -f1` | Take the 1st field, splitting on spaces |
| `awk '{print $9}'` | Print the 9th whitespace-separated column |
| `tr` | Translate or delete characters |
| `tee file` | Write to a file **and** pass output on down the pipe |

## 6. Worked example: questions about a web server log

Each line of a typical web server **access log** looks like this:

```text
102.89.34.11 - - [06/Nov/2026:09:14:02 +0100] "POST /api/v1/transfers HTTP/1.1" 500 312 "-" "okhttp/4.12"
```

The fields are: client IP address, two unused fields, time, the request, the **status code** (here `500`, a server error), the response size, the referrer and the client program.

```bash
# How many requests failed with a 5xx server error?
awk '$9 ~ /^5/' access.log | wc -l

# Which 5 IP addresses sent the most requests?
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -5

# Which endpoints return 500 most often?
awk '$9 == 500 {print $7}' access.log | sort | uniq -c | sort -rn | head

# Errors between 09:00 and 09:59 today
grep "06/Nov/2026:09:" access.log | awk '$9 >= 500' | wc -l
```

Read each pipeline from left to right and say what each stage does. That's how you'll build your own.

## Practice

Download the practice log provided with this topic on itlearning.tech (`access.log`, about 10,000 lines), or generate the same file yourself with `python3 labs/access-log/generate.py > access.log` from the course repository. Then, each in **one line** of commands:

1. Count the total number of requests.
2. Count the requests that returned `404`.
3. List the top 3 client IP addresses and how many requests each made.
4. Find the most common endpoint that returned a `5xx` error.
5. Save every line containing `POST` to `posts.txt`, then add every `PUT` line to the same file without overwriting it.
6. Find every file under `/etc` whose name ends in `.conf` and that was changed in the last 30 days. Throw away the "Permission denied" errors.
7. In your learning log, write down the pipeline you're proudest of and explain each stage.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [Linux PIPES and REDIRECTS: Command Line Ninja Skillz](https://www.youtube.com/watch?v=Kdr0OrCPtyk) · Shawn Powers · 17 min. Pipes and redirection with clear examples.
- [Linux Crash Course - The grep Command](https://www.youtube.com/watch?v=Tc_jntovCM0) · Learn Linux TV · 15 min. The grep command in depth.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Introduction to Azure Cloud Shell (practise the commands in the browser)](https://learn.microsoft.com/training/modules/intro-to-azure-cloud-shell/)

**AWS (AWS Skill Builder):**

- [Edit Files Visually in AWS CloudShell](https://skillbuilder.aws/learn/GSCTVGSKGR/edit-files-visually-in-aws-cloudshell/DKJKGXECCQ)

