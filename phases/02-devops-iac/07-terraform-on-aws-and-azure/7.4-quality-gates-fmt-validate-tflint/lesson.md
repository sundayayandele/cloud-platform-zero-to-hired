## What you will be able to do

- Run Terraform's own checks: `fmt`, `validate` and `test`.
- Lint configurations with **tflint**, including the AWS and Azure rule sets.
- Scan for security misconfigurations with **checkov**, read findings, fix the real ones and record a reason for the rest.
- Protect important resources with `lifecycle` rules (`prevent_destroy`, `ignore_changes`, `create_before_destroy`).
- Review a Terraform pull request: the plan, the risks, and the questions to ask.
- Put all of this together into a set of quality gates that every change must pass (wired into a pipeline in topic 8.4).
- Do the same on **Google Cloud** with the `google` provider, and compare the three clouds.

## Why this matters at work

Infrastructure mistakes are expensive and public: a storage bucket left open, a security group allowing the whole internet, a database replaced because someone renamed it. Teams catch these **before** they reach the cloud, with automated checks on every pull request and a human review of the plan. Security teams and auditors increasingly require it: "every infrastructure change is scanned and reviewed" is a control on most bank and PCI DSS checklists. Being the engineer who sets up those gates, and who can tell a real finding from a false alarm, is valuable.

## 1. Terraform's own checks

```bash
terraform fmt -check -recursive    # fails if any file isn't formatted the standard way (run `terraform fmt -recursive` to fix)
terraform validate                 # syntax, types and references are correct (needs `terraform init -backend=false` first)
```

Both are fast, need no cloud credentials, and should run on every commit. Formatting matters more than it seems: when everyone formats the same way, diffs show only real changes.

**`terraform test`** (Terraform 1.6+) runs tests written in HCL, in `tests/*.tftest.hcl`. A plan-only test checks a module's logic without creating anything:

```hcl
# modules/aws-network/tests/layout.tftest.hcl
variables {
  name = "test"
  cidr = "10.20.0.0/16"
}

run "subnets_follow_the_plan" {
  command = plan
  assert {
    condition     = aws_subnet.app[0].cidr_block == "10.20.16.0/20"
    error_message = "The first app subnet should be 10.20.16.0/20"
  }
}

run "rejects_three_zones" {
  command = plan
  variables {
    zone_count = 3
  }
  expect_failures = [var.zone_count]
}
```

`terraform test` from the module folder runs it. Plan-only tests still need a provider that can initialise, so on AWS they need credentials or `mock_provider` blocks (Terraform 1.7+); topic 8.4 runs them in the pipeline with keyless credentials.

## 2. tflint: catching mistakes Terraform doesn't

**tflint** finds problems `validate` can't: an instance type that doesn't exist, an Azure VM size with a typo, deprecated syntax, unused variables, missing version constraints.

```bash
# Install: see github.com/terraform-linters/tflint, or run it in Docker:
docker run --rm -v "$PWD":/w -w /w ghcr.io/terraform-linters/tflint:v0.55.0 --chdir=modules/aws-network
```

Add the cloud rule sets in a `.tflint.hcl`, so it knows each provider's valid values:

```hcl
plugin "aws" {
  enabled = true
  version = "0.38.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "azurerm" {
  enabled = true
  version = "0.28.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

plugin "google" {
  enabled = true
  version = "0.31.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
```

Then `tflint --init` downloads them. (Check the rule sets' current versions before you copy these numbers.)

## 3. checkov: security and compliance scanning

**checkov** reads Terraform (and CloudFormation, Bicep, Kubernetes, Dockerfiles) and checks hundreds of security rules: encryption, public access, logging, least privilege. Other tools do the same job (Trivy's `config` scanner, which you met in topic 5.4, and tfsec, now part of Trivy).

```bash
docker run --rm -v "$PWD":/w -w /w bridgecrew/checkov:3.2.330 -d modules --compact
```

Here's what checkov reported on the **first version** of the course's own network modules, and what was done about each finding. This is exactly the judgement you'll need at work:

| Finding | Real problem? | What was done |
| --- | --- | --- |
| `CKV2_AWS_12` The VPC's default security group doesn't restrict all traffic | **Yes.** Every VPC has a default group that lets its members talk to each other; anything launched without a group gets it | Added an `aws_default_security_group` with no rules |
| `CKV2_AZURE_31` The public subnet has no NSG | **Yes.** Defence in depth: the public tier should accept only HTTPS | Added `nsg-public` allowing 443 from the internet |
| `CKV2_AWS_11` VPC flow logs aren't enabled | **Yes**, for production (topic 6.4 explains why you want them) | Left to the caller for now, with a skip comment; adding them is this topic's exercise 3 |
| `CKV2_AWS_5` Security groups aren't attached to anything | **No.** The module creates the groups; the callers attach them to instances, load balancers and databases | Skipped, with the reason |
| `CKV2_AWS_19` An Elastic IP isn't attached to an EC2 instance | **No.** It belongs to the NAT gateway | Skipped, with the reason |
| `CKV2_AZURE_31` on `AzureBastionSubnet` and the Application Gateway subnet | **No, not here.** Both services need specific NSG rules; a generic NSG would break them | Skipped, with the reason; the rules come with those services (topics 6.5, 6.8) |

A skip is written next to the resource, with the reason:

```hcl
resource "aws_eip" "nat" {
  # checkov:skip=CKV2_AWS_19: this address belongs to the NAT gateway, not an instance
  count  = var.nat_gateway ? 1 : 0
  domain = "vpc"
}
```

After the changes: **65 passed, 0 failed, 7 skipped**. When the Google Cloud module was added later, checkov found one more real point (Private Google Access was off on the public subnet), which was fixed: all three modules now give **86 passed, 0 failed, 7 skipped**. tflint also caught an input the Google module declared but never used. The rules for skipping:

- Skip **one check on one resource**, never a check everywhere.
- **Always write the reason**, so a reviewer (or an auditor) can agree or disagree.
- Revisit skips: "left to the caller for now" is a to-do, not a permanent answer.

## 4. Lifecycle rules: guard rails in the code

Some resources must never be destroyed by accident, and some attributes are changed by other systems on purpose:

```hcl
resource "aws_db_instance" "itlpay" {
  # ...
  lifecycle {
    prevent_destroy = true                       # any plan that would destroy this fails
    ignore_changes  = [engine_version]           # minor upgrades applied by AWS in the maintenance window aren't drift
  }
}

resource "aws_launch_template" "app" {
  # ...
  lifecycle {
    create_before_destroy = true                 # build the replacement before removing the old one: no gap
  }
}
```

Use `prevent_destroy` on databases, state buckets, Key Vaults and anything holding data. To really delete such a resource, someone must first remove the guard in a reviewed pull request, which is the point. Also use the clouds' own protections: RDS deletion protection, Azure resource locks (`azurerm_management_lock`), S3 Object Lock.

`ignore_changes` is powerful and easy to misuse: ignoring too much hides real drift (topic 7.5). Ignore only attributes that something else is meant to manage, and say what.

## 5. Reviewing a Terraform pull request

The pull request should include the **plan output** (the pipeline posts it automatically in topic 8.4). Review it like this:

1. **Read the summary line.** "3 to add, 1 to change, 0 to destroy" is very different from "0 to add, 0 to change, 12 to destroy".
2. **Find every destroy and replace.** For each one: does it hold data or carry traffic? Is that intended? Is there a `moved` block missing (topic 7.5)?
3. **Check the security-relevant changes**: firewall rules (`0.0.0.0/0`, `*`), public access settings, IAM and RBAC (`*` actions, Owner, Contributor at subscription scope), encryption and logging switched off.
4. **Check the scanners' results** in the pull request: new checkov findings, new skips and their reasons.
5. **Check the code**: hard-coded IDs, secrets, missing tags, missing descriptions, module versions pinned.
6. **Check the environment**: is this change going to the right state and account or subscription?

A good review comment: "Line 42 replaces `aws_db_instance.itlpay` because the identifier changed. That deletes the production database. Can we keep the old identifier, or add a `moved` block?"

## 6. The quality gates

Every infrastructure pull request in this course (and in Capstone 2) must pass:

| Gate | Tool | Blocks the merge when |
| --- | --- | --- |
| Formatting | `terraform fmt -check -recursive` | Any file isn't formatted |
| Correctness | `terraform validate` | Syntax or references are wrong |
| Linting | `tflint` with the AWS, Azure and Google rule sets | Invalid values, deprecated syntax |
| Security | `checkov` | Any failed check without a written skip reason |
| Tests | `terraform test` | A module's tests fail |
| Plan review | `terraform plan`, posted to the PR, and a human approval | Always needs an approval; destroys and replaces need a second reviewer |

In topic 8.4 you'll run these in GitHub Actions on every pull request, with the plan posted as a comment.

## Practice

1. Run `fmt`, `validate`, `tflint` and `checkov` on the course's network modules. Confirm you get the same results as in section 3.
2. Make the AWS module fail checkov on purpose (for example, open port 22 to `0.0.0.0/0` on the app group). Read the finding, then remove it.
3. Fix `CKV2_AWS_11`: add a `flow_logs` option to `modules/aws-network` that sends REJECT flow logs to a CloudWatch log group with a 30-day retention (you'll need an IAM role for the service). Remove the skip comment, and rerun checkov.
4. Add the `layout.tftest.hcl` test from section 1 (with a `mock_provider "aws" {}` block so it runs without credentials) and make it pass with `terraform test`.
5. Review this plan summary and write the comment you'd leave: `Plan: 1 to add, 0 to change, 1 to destroy` where the destroy is `module.db.aws_db_instance.itlpay` and the add is `module.database.aws_db_instance.itlpay`.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [8 Terraform Best Practices that will improve your TF workflow immediately](https://www.youtube.com/watch?v=gxPykhPxRW0) · TechWorld with Nana · 9 min. Eight Terraform best practices for a team workflow.
- [Scan Terraform Code for Security Issues with Checkov | Automate IaC Security in CI/CD](https://www.youtube.com/watch?v=0e4t588Lv1Y) · Cloudamy · 8 min. Scanning Terraform for security issues with checkov.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Implement security controls in infrastructure as code](https://learn.microsoft.com/training/modules/implement-security-controls-infrastructure-as-code/)

**AWS (AWS Skill Builder):**

- [AWS CloudFormation Stacks - Troubleshooting](https://skillbuilder.aws/learn/RXN7Y5H87R/aws-cloudformation-stacks--troubleshooting/9EESANBHDE)

**Terraform (HashiCorp's free tutorials):**

- [Write Terraform tests](https://developer.hashicorp.com/terraform/tutorials/configuration-language/test)
- [Terraform Associate (003) exam preparation](https://developer.hashicorp.com/terraform/tutorials/certification-003)

