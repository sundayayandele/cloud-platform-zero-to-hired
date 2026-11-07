## What you will be able to do

- Explain **drift**, find it with `terraform plan`, and decide whether to undo it or adopt it.
- Bring existing, hand-made resources under Terraform with `import` blocks, and generate starting code for them.
- Refactor safely: rename resources and move them into modules with `moved` blocks, so nothing is destroyed.
- Stop managing a resource without deleting it, with `removed` blocks.
- Replace a broken resource on purpose with `-replace`.
- Use the older `terraform state mv / rm / import` commands when needed, with a backup.
- Do the same on **Google Cloud** with the `google` provider, and compare the three clouds.

## Why this matters at work

You'll rarely start with an empty cloud account. Most companies have years of resources created by hand, by old scripts or by other tools, and the job is to bring them under control without an outage. And infrastructure code changes constantly: modules get reorganised, names get fixed. Done naively, a rename in code means Terraform destroys and recreates the real resource, which for a database or a network is an incident. Knowing drift, imports and refactoring is what lets you change infrastructure code confidently.

## 1. Drift

**Drift** is when the real infrastructure no longer matches the code: someone changed a security rule in the console during an incident, a script added a tag, a resource was deleted by hand.

`terraform plan` detects it: it refreshes state from the cloud and shows how to bring reality **back to the code**:

```text
  # module.network.aws_vpc_security_group_ingress_rule.app_from_lb will be created
  + resource "aws_vpc_security_group_ingress_rule" "app_from_lb" { ... }     # someone deleted it by hand

  # aws_s3_bucket_public_access_block.statements will be updated in-place
  ~ resource "aws_s3_bucket_public_access_block" "statements" {
      ~ block_public_policy = false -> true                                     # someone weakened it
    }
```

For each drifted item, decide:

- **Undo it** (most common): apply the plan, so the code wins. Then find out who changed it and why, because the reason may need a code change too.
- **Adopt it**: if the manual change was right (an emergency fix), put the same change in the code, through a pull request, and the plan becomes clean.

To see drift without proposing changes, `terraform plan -refresh-only` shows only what changed in the real world and can update state to match, without touching resources. Run a scheduled plan (topic 8.4) every night on production and alert when it isn't clean: that's drift detection.

Prevent drift at the source: give people **read-only** access to production consoles, and make the pipeline the only way to change things (Capstone 2's rule). Emergency "break-glass" access exists but is logged and reviewed.

## 2. Importing existing resources

`import` brings a resource that already exists under Terraform's management, without recreating it. The modern way (Terraform 1.5+) is an `import` block in code, so it goes through review like any change:

```hcl
import {
  to = aws_s3_bucket.legacy_exports
  id = "itlpay-exports-2023"                # the real resource's ID: for S3 the bucket name, for most AWS resources the ID
}

import {
  to = azurerm_storage_account.legacy
  id = "/subscriptions/<sub>/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/itllegacy2023"
}
```

Azure IDs are full resource paths (`az storage account show -n itllegacy2023 --query id -o tsv`).

You still need the matching `resource` block. Terraform can write a first draft for you:

```bash
terraform plan -generate-config-out=generated.tf
```

Read `generated.tf` carefully: it includes every attribute, often with defaults you don't need. Tidy it into normal code, then plan until it shows **"1 to import, 0 to add, 0 to change, 0 to destroy"**, and apply. After the import, the `import` block can be deleted.

Importing a whole estate is done in small batches, one service or network at a time, each with a clean plan before the next. Tools such as `aztfexport` (Azure) and Former2 (AWS) generate code for many resources at once; treat their output as a starting point, like `-generate-config-out`.

## 3. Refactoring with moved blocks

Renaming a resource in code changes its address. Without help, Terraform sees "the old one is gone, a new one appeared", and plans destroy plus create:

```text
  # aws_db_instance.db will be destroyed
  # aws_db_instance.itlpay will be created
Plan: 1 to add, 0 to change, 1 to destroy.
```

A `moved` block tells Terraform it's the same object:

```hcl
moved {
  from = aws_db_instance.db
  to   = aws_db_instance.itlpay
}
```

Now the plan shows the move and **no** destroy. The same works for moving resources into a module, and for `count` to `for_each`:

```hcl
moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.this
}

moved {
  from = azurerm_storage_container.this[0]
  to   = azurerm_storage_container.this["statements"]
}
```

Keep `moved` blocks in the code for a while (every environment and every teammate's state needs to apply them once), then remove them in a later cleanup. In modules others use, keep them longer.

## 4. Removing from management without deleting

Sometimes a resource should stay, but Terraform should stop managing it (another team takes it over; it moves to another configuration):

```hcl
removed {
  from = aws_s3_bucket.legacy_exports
  lifecycle {
    destroy = false          # forget it; don't delete it
  }
}
```

The plan shows it will be removed from state only. (Deleting the `resource` block **without** a `removed` block would destroy the real bucket.)

## 5. Replacing something on purpose

When a resource is broken in a way Terraform can't see (a VM with a corrupted disk, a certificate that needs reissuing), force a replacement:

```bash
terraform plan -replace='module.app.aws_instance.app[0]' -out=tfplan
terraform apply tfplan
```

Combined with `create_before_destroy` (topic 7.4) and a load balancer, that's a safe way to replace a server.

## 6. The older state commands

You'll meet these in existing runbooks and older teams. They change state immediately, without a plan or a review, so prefer the blocks above:

```bash
terraform state pull > backup-$(date +%F-%H%M).tfstate    # ALWAYS take a backup first, store it safely
terraform state mv 'aws_db_instance.db' 'aws_db_instance.itlpay'
terraform state rm 'aws_s3_bucket.legacy_exports'
terraform import aws_s3_bucket.legacy_exports itlpay-exports-2023
```

If you must use them: work on a copy of the configuration's state first if you can, make sure nobody else is running Terraform (the lock helps), take the backup, run one command at a time, and run `terraform plan` after each to confirm it shows no unexpected changes.

## Practice

1. Apply the network lab on AWS. In the console, delete the rule that lets the load balancer reach the app tier, and add a tag by hand. Run `terraform plan`: undo the rule deletion, and adopt the tag into code.
2. Create a storage account by hand in Azure (CLI), then import it into a configuration with an `import` block and `-generate-config-out`. Tidy the generated code and reach a clean plan.
3. In a copy of the network module, rename `aws_security_group.db` to `aws_security_group.database`. Show the destroy/create plan, then add a `moved` block and show the clean plan.
4. Move the AWS bucket you created in topic 7.1 into a `modules/aws-bucket` module (your exercise from topic 7.2) using `moved`, with no destroy in the plan.
5. Write a runbook (topic 4.3) for "someone changed production by hand during an incident": how you find the drift, decide, and fix it.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Exploring the Import Block in Terraform 1.5](https://www.youtube.com/watch?v=znfh_00EDZ0) · Ned in the Cloud · 24 min. Bringing existing resources into Terraform with import blocks.
- [Using Moved Blocks in Terraform](https://www.youtube.com/watch?v=fDPB7xbckVM) · Ned in the Cloud · 18 min. Refactoring safely with moved blocks.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Enforce governance with Azure Policy and resource locks](https://learn.microsoft.com/training/modules/enforce-governance-azure-policy-resource-locks/)

**AWS (AWS Skill Builder):**

- [AWS Config Getting Started](https://skillbuilder.aws/learn/HUGPFMV5AJ/aws-config-getting-started/WC7YDT5MNB)

**Terraform (HashiCorp's free tutorials):**

- [Manage resource drift](https://developer.hashicorp.com/terraform/tutorials/state/resource-drift)
- [Import Terraform configuration](https://developer.hashicorp.com/terraform/tutorials/state/state-import)
- [Use configuration to move resources](https://developer.hashicorp.com/terraform/tutorials/configuration-language/move-config)

