## What you will be able to do

- Explain what a cloud engineer does day to day, and why almost all of that work happens on Linux, in a terminal.
- Get a working Linux command line on your own computer (Windows, macOS or Linux) or in your browser with GitHub Codespaces, without paying anything.
- Open a terminal, run your first commands, and read what the prompt is telling you.
- Find help for any command with `--help`, `man` and `tldr`.
- Explain how this course works: the weekly rhythm, labs on two clouds, quizzes, capstones and the two certificate routes.
- Keep a learning log in a GitHub repository from week 1.

## Why this matters at work

Cloud engineers spend their days on Linux machines they will never see: virtual machines in a data centre in Cape Town, Dublin or Virginia, containers on a Kubernetes cluster, build runners in GitHub. There is no screen and no mouse, only a terminal. Most servers on AWS and Azure run Linux (even on Azure, Microsoft's own cloud, Linux runs on most virtual machines), and every tool in this course (Docker, Terraform, the AWS and Azure command-line tools, Kubernetes) is driven from a terminal. The faster and calmer you are at the command line, the faster you fix things when production is down at 2 a.m.

## 1. What a cloud and platform engineer does

A **cloud engineer** builds and runs the infrastructure that applications live on: networks, servers, databases, storage and the rules about who can reach what. A **DevOps engineer** builds the pipelines that test and ship software safely, many times a day. A **platform engineer** turns all of that into a self-service platform, so that developers can create a new service in minutes without filing a ticket. A **site reliability engineer (SRE)** keeps it all running, measures how reliable it is, and leads the response when it breaks.

This course takes you through all four, in that order:

| Phase | You learn to | First job it prepares you for |
| --- | --- | --- |
| 1. Cloud Foundations (weeks 1–13) | Use Linux, networks, scripts, Git, containers, and the core services of AWS and Azure | Cloud support, junior Linux or cloud administrator |
| 2. DevOps and Infrastructure as Code (weeks 14–24) | Build infrastructure with Terraform and ship it through pipelines; run Kubernetes | Junior DevOps or cloud engineer |
| 3. Platform Engineering and SRE (weeks 25–34) | Build a self-service platform, set reliability targets, lead incidents, control costs | Platform engineer or SRE |

A typical day in a junior cloud role looks like this: read the overnight alerts, fix a server that has run out of disk space, review a colleague's change to the network, add a new storage bucket for a team (with the right access rules), answer a developer who can't reach the database, and write down what you did so the next person can repeat it. Every one of those tasks starts in a terminal.

## 2. Why two clouds

You will learn **AWS and Azure side by side**. AWS has the most cloud job adverts worldwide. Azure is strong with banks, telecoms and government across Nigeria and the rest of Africa, and with many European employers. The ideas are the same on both (a private network, a virtual machine, a storage bucket, a permission); only the names and the buttons differ. So every cloud topic in this course has four steps:

1. **The idea**, explained without any vendor.
2. **The AWS lab**: build it.
3. **The Azure lab**: build the same thing, and pass the same checks.
4. **The comparison**: names, defaults, costs, and one place where the two differ.

You won't open a cloud account until Module 6 (week 10). Modules 1 to 5 run entirely on your own computer or in Codespaces, for free.

## 3. Getting a Linux command line

You need a **terminal** (a window where you type commands) connected to a **Linux shell** (the program that reads your commands; ours is **Bash**). Pick the option that matches your computer. All of them are free.

### Windows 10 or 11: WSL

**WSL** (Windows Subsystem for Linux) runs a real Ubuntu Linux inside Windows.

1. Click **Start**, type `PowerShell`, right-click **Windows PowerShell** and choose **Run as administrator**.
2. Run:

   ```powershell
   wsl --install -d Ubuntu-24.04
   ```

3. Restart when asked. Ubuntu opens and asks you for a **Linux username and password**. Choose a short lowercase username (for example `ada`). The password doesn't show while you type; that's normal. Write it down: you'll need it for `sudo` in topic 1.3.
4. From now on, open **Ubuntu** from the Start menu (or install **Windows Terminal** from the Microsoft Store and choose the Ubuntu tab).

If `wsl --install` fails, your computer may need **virtualisation** turned on in its firmware settings (often called *Intel VT-x* or *AMD-V*). Ask in *Questions and help* with the exact error message.

### macOS

macOS already has a terminal and a Unix shell. Open **Terminal** (press Cmd+Space, type `Terminal`). The default shell is `zsh`, which accepts almost everything in this module. Two differences to know: some commands have slightly different options on macOS (they come from BSD, not GNU), and there is no `systemd`. For topics 1.4 and 1.5, install **Multipass** (free, from [multipass.run](https://multipass.run)) and run `multipass launch --name lab 24.04` then `multipass shell lab`: that gives you a real Ubuntu virtual machine.

### Linux

If you already run Ubuntu, Fedora or another distribution, open **Terminal**. You're ready.

### No admin rights, an old computer, or a Chromebook: GitHub Codespaces

**Codespaces** gives you a Linux machine in your browser. GitHub's free plan includes a monthly allowance of free hours, which is enough for this module if you stop the codespace when you finish each session.

1. Create a GitHub account at [github.com](https://github.com) if you haven't got one. Choose a professional username, because employers will see it.
2. Create a new repository called `cloud-learning-log` (tick **Add a README file**).
3. On the repository page, click **Code → Codespaces → Create codespace on main**.
4. A VS Code editor opens in your browser, with a **terminal** at the bottom. That terminal is Ubuntu Linux.
5. When you finish, click the green **Codespaces** button at the bottom left and choose **Stop current codespace**, so it doesn't use up your free hours.

Codespaces runs inside a container, so it has no `systemd`: for topic 1.4 only, use Killercoda's free Ubuntu playground in the browser ([killercoda.com/playgrounds](https://killercoda.com/playgrounds), sessions of about an hour) or Multipass. Codespaces needs a steady connection while you use it. If your connection is slow or expensive, WSL or a local Linux install is better: once installed, it works offline.

## 4. Your first commands

Open your terminal. You'll see a **prompt**, something like:

```text
ada@laptop:~$
```

It tells you **who** you are (`ada`), **which machine** you're on (`laptop`), **where** you are (`~` means your home folder) and that you're an ordinary user (`$`; a `#` would mean you are the all-powerful `root` user, which topic 1.3 explains). Type each command below and press Enter.

```bash
whoami          # your username
hostname        # the machine's name
pwd             # print working directory: where you are
date            # the date and time
uname -a        # the kernel and system details
cat /etc/os-release   # which Linux distribution and version
echo "Hello, cloud"    # print text
history         # the commands you've run
clear           # clear the screen (or press Ctrl+L)
```

Everything after `#` is a **comment**: the shell ignores it. In this course, comments explain what a command does; you don't need to type them.

A few keys save hours:

| Key | What it does |
| --- | --- |
| Tab | Completes a command or file name. Press it twice to see the options |
| ↑ and ↓ | Scroll through earlier commands |
| Ctrl+C | Stops the command that is running (use it when something hangs) |
| Ctrl+R | Searches your history: type part of an old command |
| Ctrl+A / Ctrl+E | Jump to the start / end of the line |
| Ctrl+D | Logs out of the shell (closes the session) |

A command has a **name**, then **options** (also called flags, starting with `-` or `--`), then **arguments** (what to act on):

```bash
ls -l --human-readable /etc
#  name  options          argument
```

Short options can be combined: `ls -l -a` is the same as `ls -la`.

## 5. Finding help without leaving the terminal

Nobody remembers every option. Professionals look things up constantly; the skill is knowing where.

```bash
ls --help          # a short summary of options (most GNU commands)
man ls             # the full manual page; press q to quit, / to search
tldr ls            # short, practical examples (install below)
type cd            # is it a program, a shell built-in or an alias?
```

Install `tldr` on Ubuntu or WSL with `sudo apt update && sudo apt install -y tldr`, then run `tldr --update` once. On macOS, use `brew install tldr` if you have Homebrew.

When a command fails, read the **error message** slowly, from the start. "No such file or directory", "Permission denied" and "command not found" each point to a different cause, and you'll learn to tell them apart this week. When you ask for help, paste the exact command and the exact error, as text, not as a photo of the screen.

## 6. How this course works

- **Weekly rhythm:** each week has two or three topics. For each topic: read the lesson, watch the videos, do the practice tasks, then take the topic quiz on itlearning.tech. Every Monday you'll get a message with that week's plan.
- **Labs:** "break and fix" labs give you a broken system and a ticket, like at work. Each cloud lab has an AWS version and an Azure version.
- **Capstones:** at the end of each phase you build a complete system and defend it. Capstone 1 (week 13) deploys ITL Pay, a small payments system, on both clouds.
- **Exam:** a timed end-of-phase exam in Safe Exam Browser, plus a timed scripting test.
- **Certificates:** a free **Self-Study** certificate (a recorded defence on GitHub, automated checks, and a quick check by the administrator) or a **Mentor-Verified** certificate with paid mentorship (live sessions with a mentor).
- **Asking for help:** post in *Questions and help* on itlearning.tech. Say what you tried, paste the exact command and error, and say which computer and operating system you're using.

## 7. Your learning log

Employers hiring for cloud roles look for evidence that you can learn, write things down and fix problems. Start a **learning log** now and keep it all course:

1. In your `cloud-learning-log` repository on GitHub, click the `README.md` file, then the pencil icon.
2. Add a heading for week 1 and three short lines: what you learned, one command you found useful and why, and one thing that confused you.
3. Click **Commit changes**.

Add an entry every week. Module 4 teaches you to do this from the terminal with Git; for now, the browser is fine.

## Practice

1. Get a terminal working with one of the options in section 3. Run every command in section 4, and write down what `cat /etc/os-release` says.
2. Use `man` to find out what `ls -t` and `ls -r` do. Then run `ls -ltr /etc` and explain the order of the output in one sentence.
3. Use Ctrl+R to find and re-run your `uname -a` command without retyping it.
4. Run `type cd`, `type ls` and `type echo`. Which are shell built-ins and which are programs on disk?
5. Run a command that doesn't exist (for example `lss`). Copy the exact error message into your learning log, and explain what it means.
6. Start your learning log with your week-1 entry.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [How to install Linux on Windows 11 with WSL for Beginners](https://www.youtube.com/watch?v=zZf4YH4WiZo) · Devtamin · 4 min. Installing Linux on Windows 11 with WSL, step by step.
- [60 Linux Commands you NEED to know (in 10 minutes)](https://www.youtube.com/watch?v=gd7BXuUQ91w) · NetworkChuck · 11 min. 60 everyday Linux commands, quickly, so the names feel familiar.
- [100+ Linux Things you Need to Know](https://www.youtube.com/watch?v=LKCVKw9CzFo) · Fireship · 12 min. A fast tour of the Linux ideas you'll meet all course.

## Further learning (free)

Free, self-paced courses from the two clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn and a free AWS Builder ID for AWS Skill Builder to track your progress.

**Azure (Microsoft Learn):**

- [Developing in the Windows Subsystem for Linux with Visual Studio Code](https://learn.microsoft.com/training/modules/developing-in-wsl/)
- [Introduction to Azure Cloud Shell](https://learn.microsoft.com/training/modules/intro-to-azure-cloud-shell/)
- [Code with GitHub Codespaces](https://learn.microsoft.com/training/modules/code-with-github-codespaces/)

**AWS (AWS Skill Builder):**

- [Getting Started with AWS Cloud Essentials](https://skillbuilder.aws/learn/Y738EQQD49/getting-started-with-aws-cloud-essentials/YEWD5RAWZJ)
- [Edit Files Visually in AWS CloudShell](https://skillbuilder.aws/learn/GSCTVGSKGR/edit-files-visually-in-aws-cloudshell/DKJKGXECCQ)

