## What you will be able to do

- Work on a **branch**, keep it up to date with `main`, and merge it.
- Resolve a merge conflict calmly.
- Open a **pull request** (PR), write a description a reviewer can act on, and respond to review comments.
- Review someone else's infrastructure change: what to look for, and how to comment helpfully.
- Protect `main` with branch protection rules and required checks.
- Add a GitHub Actions workflow that runs `shellcheck` and `pytest` on every push and pull request.

## Why this matters at work

In a professional cloud team, nobody changes production alone. Every change to a script, a firewall rule or a Terraform file goes through a pull request: someone else reviews it, automated checks run, and only then is it merged and applied. This "four-eyes" rule is required by bank regulators, by PCI DSS for card payments and by most security standards. It catches mistakes before they cost money, and it's how teams share knowledge. Being good at pull requests (small, clear, well tested) is one of the fastest ways to earn trust in a new job.

## 1. Branches

A **branch** is a separate line of work. `main` holds the agreed, working version; you make each change on its own branch, so half-finished work never lands in `main`.

```bash
git switch -c add-backup-check        # create a branch and switch to it
# ... edit, add, commit ...
git push -u origin add-backup-check   # publish the branch to GitHub
git branch                            # list local branches (* marks the current one)
git switch main                       # go back to main
```

Name branches after the change: `fix-db-firewall-rule`, `add-cost-report`, `ticket-142-rotate-logs`.

Keep branches **short-lived** (a day or two). Long-lived branches drift away from `main` and become painful to merge.

## 2. Merging and staying up to date

While you work, others merge into `main`. Bring their changes into your branch regularly:

```bash
git switch main && git pull           # update your local main
git switch add-backup-check
git merge main                        # bring main's new commits into your branch
```

(Some teams use `git rebase main` instead, which replays your commits on top of `main` for a straight history. Either is fine; follow your team's rule, and never rebase a branch others are using.)

## 3. Merge conflicts

A **conflict** happens when two branches changed the same lines differently. Git stops and marks the file:

```text
<<<<<<< HEAD
retention_days=30
=======
retention_days=14
>>>>>>> main
```

The part above `=======` is your branch; below is the other. To resolve it:

1. Open the file and decide what the right result is. Sometimes it's one side, sometimes a combination. **Ask** the other author if you're not sure: a conflict is a conversation about intent.
2. Delete the markers so the file is correct.
3. `git add` the file, then `git commit` to finish the merge.
4. Run the tests again before pushing.

`git status` lists conflicted files; `git merge --abort` puts everything back if you want to start again.

## 4. Pull requests

A **pull request** asks for your branch to be merged into `main`, and is where review happens. Push your branch, then on GitHub click **Compare & pull request** (or use the GitHub CLI: `gh pr create`).

A good PR description answers four questions:

```markdown
## What
Adds a nightly check that the newest backup is less than 26 hours old.

## Why
Backups silently stopped for 3 weeks in October (incident 2026-10-14).

## How I tested it
- `pytest -q`: 6 new tests, including "no backups at all" and "backup 27 hours old"
- Ran it on staging: correctly alerted on a deliberately old backup

## Risk and rollback
Read-only: it only reads file times. Roll back by reverting this PR.
```

Keep PRs **small**: under about 300 changed lines is easy to review well; 2,000 lines gets a rubber stamp. Split big work into steps.

Use a **draft** PR to show work in progress and get early feedback. Link the ticket. Add screenshots or command output for anything a reviewer can't easily run.

## 5. Reviewing a change

When you review, look at the change from production's point of view:

| Look for | Examples in infrastructure code |
| --- | --- |
| **Safety** | Could this delete or expose something? `rm -rf` with a variable; a firewall rule open to `0.0.0.0/0`; a public storage bucket |
| **Secrets** | Tokens, keys or passwords in the diff, even in examples or comments |
| **Least privilege** | Permissions wider than needed (`*` actions, Owner roles, `chmod 777`) |
| **Failure handling** | Strict mode, timeouts, exit codes, what happens if a step fails half-way |
| **Can it be re-run?** | Idempotent steps (topic 3.2) |
| **Tests and evidence** | Are there tests for the new behaviour? Did the author show it working? |
| **Clarity** | Will someone understand this at 3 a.m. during an incident? |

How to comment well:

- Be specific and kind. Ask questions rather than issue orders: "What happens here if `backup_dir` is empty?" teaches more than "wrong".
- Say how important each comment is: "**Blocking:** this opens SSH to the internet" versus "**Nit:** typo in the log message".
- Approve when it's good enough and safe, not when it's how you'd have written it.

As the author, answer every comment (with a change or a reason), and don't take review personally. Everyone's code gets comments.

## 6. Merging a PR

When the review is approved and the checks pass, merge on GitHub. Three options:

- **Merge commit**: keeps all your commits plus a merge commit.
- **Squash and merge**: combines the PR into one commit on `main`. Popular, because `main` then has one clear commit per change.
- **Rebase and merge**: puts your commits on `main` one by one, without a merge commit.

Then delete the branch (GitHub offers a button), and update your local copy: `git switch main && git pull`.

## 7. Protecting main

**Branch protection** (or the newer **rulesets**) enforces the process so nobody can skip it, by accident or under pressure. In the repository: **Settings → Rules → Rulesets** (or **Settings → Branches → Add branch protection rule**) for `main`:

- **Require a pull request before merging**, with at least **1 approval**.
- **Require status checks to pass** (the workflow in section 8).
- **Block force pushes** and **block deletion** of `main`.
- Optionally, **require review from code owners**: a `CODEOWNERS` file names who must review which folders (for example, the network team for `network/`).

On a personal repository you're the only person, so you can't approve your own PRs; turn on the required checks anyway, and practise the PR flow. In teams, these settings are usually managed centrally for every repository.

## 8. Checks on every push: GitHub Actions

**GitHub Actions** runs workflows defined in `.github/workflows/*.yml` on GitHub's machines. Add this to your `ops-scripts` repository as `.github/workflows/checks.yml`:

```yaml
name: checks
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  shell:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: shellcheck
        run: |
          shopt -s globstar nullglob
          files=(**/*.sh)
          if (( ${#files[@]} )); then shellcheck "${files[@]}"; else echo "No shell scripts"; fi

  python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install -r requirements.txt
      - run: pytest -q
```

Commit it on a branch and open a PR: GitHub runs both jobs and shows a green tick or a red cross on the PR. Click **Details** to see each step's output. Then, in the branch rule, mark `shell` and `python` as **required checks**.

Notes:

- `permissions: contents: read` gives the workflow only the access it needs: least privilege applies to pipelines too.
- `on: pull_request` runs the checks on the merged result of the PR, before it's merged.
- Add a **badge** to your README so visitors see the status: `![checks](https://github.com/YOUR-USERNAME/ops-scripts/actions/workflows/checks.yml/badge.svg)`.

This is the first piece of the CI/CD pipelines you'll build in Phase 2, where the same idea runs Terraform plans, security scans and deployments.

## Practice

1. On a branch, add a new check to `health-report.sh`, push, and open a PR with a description that answers the four questions in section 4. Merge it with **Squash and merge**.
2. Create a conflict on purpose: change the same line on two branches, merge one, then merge `main` into the other. Resolve it and finish the merge.
3. Add the workflow from section 8 (create `requirements.txt` and at least one test if your repository has none). Open a PR that deliberately breaks `shellcheck`, watch it go red, fix it, watch it go green.
4. Turn on a branch rule for `main`: require a PR, require the two checks, block force pushes. Try to push straight to `main` and read the error.
5. Review a classmate's PR in the forum (or the sample PR linked on the topic page). Leave at least one blocking and one non-blocking comment, using the table in section 5.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [How to create a pull request in 4 min | GitHub for Beginners](https://www.youtube.com/watch?v=nCKdihvneS0) · GitHub · 4 min. Creating a pull request, from GitHub.
- [How to Review a Pull Request in GitHub the RIGHT Way](https://www.youtube.com/watch?v=lSnbOtw4izI) · CoderDave · 4 min. How to review a pull request well.
- [How to use GitHub Actions | GitHub for Beginners](https://www.youtube.com/watch?v=BQrohJ3PT7I) · GitHub · 8 min. Your first GitHub Actions workflow, from GitHub.

## Further learning (free)

Free, self-paced courses from the two clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn and a free AWS Builder ID for AWS Skill Builder to track your progress.

**Azure (Microsoft Learn):**

- [Manage repository changes by using pull requests on GitHub](https://learn.microsoft.com/training/modules/manage-changes-pull-requests-github/)
- [Settle competing commits by using merge conflict resolution on GitHub](https://learn.microsoft.com/training/modules/resolve-merge-conflicts-github/)
- [Build continuous integration workflows by using GitHub Actions](https://learn.microsoft.com/training/modules/github-actions-ci/)

**AWS (AWS Skill Builder):**

- [Getting Started with DevOps on AWS](https://skillbuilder.aws/learn/R4B13K95YQ/getting-started-with-devops-on-aws/38NHHYRV1R)

