## What you will be able to do

- Explain what Git and GitHub are, and why every piece of infrastructure work (scripts, Terraform, pipelines, runbooks) lives in version control.
- Set up Git with your name, email and an SSH key for GitHub.
- Create a repository, stage and commit changes, read the history, and see exactly what changed.
- Keep secrets, build output and local files out of a repository with `.gitignore`, and know what to do if a secret gets committed.
- Push to GitHub, clone a repository, and pull changes made elsewhere.
- Undo mistakes safely: discard changes, unstage, amend, and revert a commit.

## Why this matters at work

Cloud teams manage infrastructure **as code**: networks, servers, permissions and pipelines are described in files, and those files live in Git. That gives an audit trail auditors and regulators ask for ("who opened this firewall port, when, and who approved it?"), a way to undo a bad change in minutes, and the starting point for every automated pipeline in Phase 2. GitHub is also your portfolio: hiring managers for cloud roles open your repositories to see your scripts, your Terraform and how you write commit messages.

## 1. Git and GitHub in plain words

**Git** is a program that records **versions** of a folder. Each saved version is a **commit**: a snapshot of the files, with a message saying why they changed, who changed them and when. You can compare any two versions and go back to any of them.

**GitHub** is a website that hosts Git repositories online: a backup, a place to share and review work, and the trigger for automated pipelines (GitHub Actions). GitLab, Bitbucket and **Azure Repos** (part of Azure DevOps) do the same job; AWS has its own, CodeCommit, but AWS paused it for new customers in 2024, and most AWS teams use GitHub or GitLab. The Git commands are identical everywhere.

You've already used GitHub in the browser for your learning log (topic 1.1). Now you'll use Git from the terminal, which is how you'll work from here on.

## 2. Setting up Git

```bash
git --version                                   # Git is installed on Ubuntu, WSL and Codespaces
git config --global user.name "Ada Obi"
git config --global user.email "ada.obi@example.com"   # the email on your GitHub account
git config --global init.defaultBranch main
git config --global pull.rebase false           # merge when pulling (simplest to start with)
git config --list                               # check
```

To push to GitHub from the terminal, use the SSH key you created in topic 1.5:

1. Copy your **public** key: `cat ~/.ssh/id_ed25519.pub`.
2. On GitHub: **Settings → SSH and GPG keys → New SSH key**, paste it, and save.
3. Test: `ssh -T git@github.com`. It should greet you by username.

In Codespaces, Git is already signed in for you.

## 3. The three places your changes live

| Place | What it is | Commands that move changes |
| --- | --- | --- |
| **Working tree** | The files on your disk, as you edit them | You edit files |
| **Staging area** (the index) | The changes you've chosen for the next commit | `git add` |
| **Repository** | The saved history of commits | `git commit` |

Staging lets you commit related changes together and leave the rest for another commit, so each commit tells one story.

## 4. Your first repository

Turn your scripts folder into a repository:

```bash
mkdir -p ~/ops-scripts && cd ~/ops-scripts
git init                        # creates the hidden .git folder
cp ~/health-report.sh .         # or create a file
git status                      # what's changed, what's staged
git add health-report.sh        # stage one file (git add . stages everything in this folder)
git commit -m "Add daily server health report"
git log --oneline               # the history, one line per commit
```

Then change the script and look at what you changed before committing:

```bash
git diff                        # unstaged changes, line by line
git add health-report.sh
git diff --staged               # what will go into the commit
git commit -m "Report failed services as well as disk and memory"
git log --oneline --graph
git show HEAD                   # the latest commit in full
git log -p -- health-report.sh  # every change ever made to one file
git blame health-report.sh      # who last changed each line, and in which commit
```

## 5. Good commit messages

A commit message explains **why** the change was made; the diff already shows what. Teams read them during incidents ("what changed just before this broke?"), so they matter.

```text
Allow 5432 from the new app security group

The app servers moved to sg-app this morning, but the database
rule still referenced sg-app-old, so connections timed out.
```

- A short first line (about 50–70 characters), in the imperative: "Add", "Fix", "Allow", not "Added" or "fixes".
- A blank line, then more detail if it helps: the reason, the ticket number, anything surprising.
- One logical change per commit. "Fix typo, add backup script and change firewall" is three commits.

## 6. .gitignore and secrets

Some files must never be committed:

- **secrets**: passwords, API tokens, private keys, `.env` files with credentials, cloud access keys;
- **generated files**: virtual environments (`.venv/`), `__pycache__/`, build output;
- **state and local files**: Terraform state (Phase 2), editor settings, `.DS_Store`.

List them in a `.gitignore` file at the root of the repository **before** the first `git add`:

```text
# .gitignore
.env
*.pem
*.key
.venv/
__pycache__/
.terraform/
*.tfstate
*.tfstate.*
.DS_Store
```

GitHub has ready-made templates (choose one when creating a repository, or see `github/gitignore`).

**If a secret is committed**, assume it's stolen, even if you notice within a minute and even in a private repository. Automated scanners watch public repositories constantly, and anyone with access to the repository can read the history. The order of work is:

1. **Revoke or rotate** the secret straight away (create a new key, disable the old one).
2. Check the logs for any use of it (CloudTrail, the Azure Activity Log, the service's own logs).
3. Then remove it from the code, and, if needed, from the history (with a tool such as `git filter-repo`, coordinated with the team, because it rewrites history).

Deleting the file in a new commit doesn't remove it: it's still in the history. GitHub's **secret scanning and push protection** (on by default for public repositories) blocks many known secret formats at push time; Phase 2 adds `gitleaks` to every pipeline.

## 7. GitHub: push, clone and pull

Create an empty repository on GitHub called `ops-scripts` (no README, so it doesn't conflict), then connect your local one:

```bash
git remote add origin git@github.com:YOUR-USERNAME/ops-scripts.git
git push -u origin main         # -u: remember origin/main as this branch's upstream
```

From now on, `git push` sends new commits. Elsewhere (another machine, a server, a codespace):

```bash
git clone git@github.com:YOUR-USERNAME/ops-scripts.git
cd ops-scripts
# ... later, after changes were pushed from somewhere else ...
git pull                        # fetch new commits and merge them into your branch
```

`git fetch` downloads new commits without changing your files; `git pull` is `fetch` followed by a merge. If someone else pushed first, your push is rejected: pull, check the result, then push again.

## 8. Undoing things safely

| Situation | Command |
| --- | --- |
| Throw away unstaged edits to a file | `git restore file` |
| Unstage a file (keep the edits) | `git restore --staged file` |
| Fix the last commit's message, or add a forgotten file, **before pushing** | `git add file && git commit --amend` |
| Undo a commit that's **already pushed** | `git revert <commit>`: makes a new commit that reverses it |
| See what any file looked like at an old commit | `git show <commit>:path/to/file` |
| Find a commit you "lost" | `git reflog` lists everywhere HEAD has been |

The rule: **never rewrite history that others have already pulled** (`--amend`, `reset --hard` and force-push on a shared branch). Use `git revert` instead, which adds a new commit and keeps the record honest. That's also what auditors want: the history shows the mistake and the fix.

## Practice

1. Set up Git and your SSH key for GitHub, and prove `ssh -T git@github.com` works.
2. Create the `ops-scripts` repository with your Module 3 scripts, a `.gitignore` and a short README. Make at least four commits, each with a good message, and push to GitHub.
3. Clone the repository into a second folder (or a codespace), make a change there, push it, then `git pull` it into the first folder.
4. Commit a fake secret on purpose in a **throwaway local** repository (for example `API_TOKEN=not-a-real-token` in `.env`), then delete the file in a new commit. Show with `git log -p` that the "secret" is still in the history. Write in your learning log what you'd do if it were real.
5. Make a bad commit, push it, and undo it with `git revert`. Look at the history and explain why this is better than rewriting it.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Git and Github Explained in 7 Minutes | Git and Github Tutorial (2026)](https://www.youtube.com/watch?v=y-an0v208A0) · Tech With Diego · 8 min. Git and GitHub explained in seven minutes.
- [Git and GitHub Tutorial for Beginners](https://www.youtube.com/watch?v=tRZGeaHPoaw) (optional, longer) · Kevin Stratvert · 46 min. A complete Git and GitHub tutorial for beginners.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Introduction to Git](https://learn.microsoft.com/training/modules/intro-to-git/)
- [Introduction to GitHub](https://learn.microsoft.com/training/modules/introduction-to-github/)
- [Describe how Git manages source control](https://learn.microsoft.com/training/modules/describe-how-git-manages-source-control/)

**AWS (AWS Skill Builder):**

- [Getting Started with DevOps on AWS](https://skillbuilder.aws/learn/R4B13K95YQ/getting-started-with-devops-on-aws/38NHHYRV1R)

