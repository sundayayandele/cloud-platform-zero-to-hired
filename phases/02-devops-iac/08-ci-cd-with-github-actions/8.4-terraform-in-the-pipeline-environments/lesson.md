## What you will be able to do

- Run Terraform from a pipeline instead of a laptop, for AWS, Azure and Google Cloud in one workflow.
- Post a plan on every pull request so reviewers see what will change in the cloud, not only in the code.
- Apply **exactly the plan that was reviewed**, from `main` only, through GitHub **environments** with required approvals.
- Explain why deployments must never be cancelled half-way, and how `concurrency` prevents it.
- Detect drift every night and turn it into an issue someone must decide on.
- Explain the risks of running Terraform in CI (plan files, permissions, state) and how the lab's workflow handles them.

## Why this matters at work

In topic 7.1 you ran `terraform apply` from your own machine. That works for one person; in a team it causes trouble: two people apply at once, someone applies a branch that was never reviewed, a laptop has old provider versions, and nobody can say who changed production last Tuesday. Mature teams make the **pipeline the only way to change infrastructure**: people propose changes in pull requests, reviewers read the plan, and an approved, logged job applies it. Interviewers ask "how do you deploy Terraform safely?" in almost every DevOps and platform interview, and auditors (in banks especially) ask for the approval trail.

## 1. The flow

The lab's `terraform.yml` (in `labs/pipelines/.github/workflows/`) does this:

```text
pull request touching infra/**
  checks: terraform fmt -check, checkov
  plan (matrix: aws, azure, gcp; read-only identities)  ──►  plan posted as a comment on the pull request
merge to main
  checks ──► plan (saved as tfplan, uploaded as an artefact)
          ──► apply, one cloud at a time: waits for an approver on environment dev-aws, dev-azure, dev-gcp
              ──► terraform apply tfplan   (exactly the reviewed plan)
every night at 03:00 UTC
  drift (matrix): plan -detailed-exitcode  ──►  exit code 2? open an issue
```

The repository layout it expects is the one from Module 7:

```text
infra/
  modules/aws-network, azure-network, gcp-network
  envs/dev-aws, dev-azure, dev-gcp      each with its own remote backend (topic 7.3)
```

## 2. Plans on pull requests

```yaml
- id: plan
  run: terraform plan -input=false -no-color -out=tfplan -var owner=pipeline
- name: Post the plan on the pull request
  if: github.event_name == 'pull_request'
  uses: actions/github-script@v7
  env:
    PLAN: ${{ steps.plan.outputs.stdout }}
```

- `-input=false` stops Terraform waiting for a prompt that nobody will answer.
- `-no-color` keeps the comment readable.
- `hashicorp/setup-terraform` wraps `terraform` so a step's output is available as `steps.plan.outputs.stdout`.
- The plan is passed through `env:` and read as `process.env.PLAN`, never pasted into the script with `${{ }}` (the injection problem from topic 8.1).
- The job needs `pull-requests: write` to comment, and nothing more.

Reviewers now see "1 to add, 0 to change, **1 to destroy**" next to the code, and can stop a dangerous change before it merges. Read the plan, not only the diff: a one-line change to a subnet's CIDR can replace the network and everything in it (topic 7.1).

Pull requests use the **plan identities**, which can only read (topic 8.3). Their trust must allow both pull requests and `main` (the plan and drift jobs also run there): two subjects on AWS and Azure (ending `:pull_request` and `:ref:refs/heads/main`, in the immutable format from topic 8.3), or a condition on the repository ID on Google Cloud.

## 3. Environments and approvals

A GitHub **environment** (Settings → Environments) is a named target with rules:

| Rule | Set it to |
| --- | --- |
| **Required reviewers** | One or two people (not the author: tick "Prevent self-review") |
| **Deployment branches and tags** | `main` only |
| **Wait timer** | Optional: minutes to wait before the job may start |
| **Environment secrets and variables** | Values only jobs in this environment can read |

A job that names it waits until a reviewer approves:

```yaml
apply:
  needs: plan
  if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request'
  environment: dev-${{ matrix.cloud }}
  strategy:
    max-parallel: 1        # one cloud at a time, so a problem on the first stops the rest
    matrix:
      cloud: [aws, azure, gcp]
```

The environment also changes the OIDC token's subject to one ending `:environment:dev-aws`, which is what the **apply identities** trust (topic 8.3). So even someone who edits the workflow to skip the environment can't get write access to the cloud: the trust policy refuses the token.

For staging and production, add more environments (`staging-aws`, `prod-aws`) with stricter rules, and apply them in order: dev, then staging after its checks pass, then production after an approval.

## 4. Apply exactly what was reviewed

```yaml
- uses: actions/download-artifact@v4
  with:
    name: tfplan-${{ matrix.cloud }}
- name: Apply exactly the plan that was reviewed
  run: terraform apply -input=false tfplan
```

Running a plain `terraform apply` in the apply job would compute a **new** plan, which may differ from what the reviewer approved (someone changed the cloud, a provider was updated). Applying the **saved plan file** applies only those changes. If the state has changed since the plan was made, Terraform refuses with "Saved plan is stale", and you plan again. That's what you want.

Three cautions about plan files:

- A plan file can contain **sensitive values** (passwords, keys from data sources). Keep artefacts short-lived (`retention-days: 1`) and the repository's access tight.
- If the approval waits longer than the artefact's retention, the apply job fails to download it: re-run the workflow to plan again.
- Pin the Terraform version (`terraform_version: "1.11.4"`) and commit `.terraform.lock.hcl` (topic 7.1), so the plan and apply jobs use identical versions.

## 5. Never cancel a deployment

```yaml
concurrency:
  group: terraform-${{ github.ref }}
  cancel-in-progress: false
```

In topic 8.1, `cancel-in-progress: true` saved minutes on tests. For Terraform it would be dangerous: cancelling an apply half-way can leave resources half-created and the state lock held (topic 7.3). With `false`, a second run **waits** for the first to finish. The remote backend's lock is the second line of defence if anything else runs Terraform at the same time.

## 6. Drift detection

Topic 7.5 explained drift: someone changes the cloud by hand, and the code no longer describes reality. The `drift` job runs every night:

```yaml
- id: drift
  run: |
    set +e
    terraform plan -input=false -no-color -detailed-exitcode -var owner=pipeline > plan.txt
    code=$?
    echo "code=$code" >> "$GITHUB_OUTPUT"
    if [ "$code" -eq 1 ]; then cat plan.txt; exit 1; fi
- if: steps.drift.outputs.code == '2'
  run: gh issue create --title "Drift detected in dev-$CLOUD" ...
```

`-detailed-exitcode` returns **0** for no changes, **1** for an error and **2** when there are changes. `set +e` lets the script read the code instead of stopping. The job sets `terraform_wrapper: false` because the wrapper changes exit codes. An issue is better than a red run nobody looks at: it has an owner and a decision (**undo** the hand change by applying, or **adopt** it by changing the code).

The drift job uses the read-only plan identity: it reports, it never fixes.

## 7. The clouds' own options

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Managed Terraform runs | (none built in; teams use CodeBuild or GitHub Actions) | Azure Pipelines with the Terraform tasks | **Infrastructure Manager** runs Terraform for you, with state stored by Google |
| Approvals | CodePipeline manual approval actions | Azure Pipelines environments with approvals and checks | Cloud Build approvals; Cloud Deploy promotions |
| Specialist services across clouds | HCP Terraform (HashiCorp), Spacelift, env0, Atlantis (self-hosted, comments-driven) | | |

The pattern is the same everywhere: plan on proposal, review, approved apply of the saved plan, drift checks. Learn it once with GitHub Actions.

## Practice

1. Add `infra/` (your modules and `envs/dev-*` from Module 7, each with a remote backend) and `terraform.yml` to your repository. Create the variables from the lab README and the three environments with yourself as a required reviewer.
2. Open a pull request that adds a tag to the network on one cloud. Check the plan comment shows `~ update in-place` with only that change.
3. Merge it. Watch the apply job wait for approval, approve it, and check the change in the cloud console. Save the run's link in your learning log as evidence.
4. Make drift on purpose: add a tag by hand in one console. Run the workflow manually (`workflow_dispatch`) and check an issue is opened. Then decide: undo or adopt, and close the issue with your reason.
5. Try to make the pipeline apply a branch other than `main`, by any route you can think of (edit the `if:`, run it manually from a branch). Write down what stopped each attempt.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Terraform Driven GitOps using GitHub Actions](https://www.youtube.com/watch?v=29SwRSb4BO8) · HashiCorp, an IBM Company · 14 min. HashiCorp on running Terraform from GitHub Actions: plans on pull requests, applies on merge.
- [GitHub Actions: Approvals, Environments and Visualization DEEP DIVE](https://www.youtube.com/watch?v=w_37LDOy4sI) · CoderDave · 14 min. GitHub environments and approvals in depth.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**AWS (AWS Skill Builder):**

- [AWS CodePipeline Getting Started (manual approval actions)](https://skillbuilder.aws/learn/YNKCTVMQ9M/aws-codepipeline-getting-started/UGBY22FZ6P)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Implement DevOps Workflows in Google Cloud (skill badge)](https://www.skills.google/course_templates/716)
- [Getting Started with Terraform for Google Cloud](https://www.skills.google/course_templates/443)

**Terraform (HashiCorp's free tutorials):**

- [Automate Terraform with GitHub Actions](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
- [Running Terraform in automation](https://developer.hashicorp.com/terraform/tutorials/automation/automate-terraform)

