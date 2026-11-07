## What you will be able to do

- Explain infrastructure as code (IaC), and why teams describe infrastructure in files instead of clicking or scripting it step by step.
- Compare declarative tools (Terraform, CloudFormation, Bicep) with imperative scripts (your Module 6 CLI scripts).
- Install Terraform and explain providers, resources, the plan/apply cycle and state.
- Write, plan, apply and destroy a small configuration on AWS and on Azure.
- Read a plan: what will be created, changed, replaced or destroyed, and spot a dangerous one before applying.
- Explain why Terraform is the main tool in this course, and where the clouds' own tools fit.
- Do the same on **Google Cloud** with the `google` provider, and compare the three clouds.

## Why this matters at work

In Capstone 1 you built ITL Pay's environment with Bash scripts, and you saw their limits: what if step 7 of 12 fails? How do you change one setting on resources that already exist? How does a reviewer see what a change will do before it happens? Infrastructure as code answers all three. Almost every cloud and DevOps job advert asks for Terraform, and the HashiCorp Terraform Associate certification is one of the most requested. It's also how regulated companies keep control: every change to production is a reviewed pull request with a plan attached.

## 1. From scripts to infrastructure as code

| | CLI scripts (Module 6) | Infrastructure as code |
| --- | --- | --- |
| You write | The **steps**: create this, then that | The **end state**: this is what should exist |
| Re-running | You must make every step idempotent yourself (topic 3.2) | The tool compares what exists with what you want, and changes only the difference |
| Changing a setting | Write new commands, often different from the create commands | Edit one line, run again |
| Seeing the effect first | Hard | A **plan** lists every change before anything happens |
| Deleting everything | A separate script, in the right order | One command, in the right order, worked out by the tool |

IaC tools are **declarative**: you declare the result, and the tool works out the steps. That's the same idea as "make sure this is true" from topic 3.2, done for you.

The main tools:

| Tool | Clouds | Language | Notes |
| --- | --- | --- | --- |
| **Terraform** (HashiCorp) | AWS, Azure, GCP and thousands more through providers | HCL | The most common in job adverts; one language for both clouds. Licensed under the Business Source License since 2023 |
| **OpenTofu** | Same as Terraform | HCL | An open-source fork of Terraform, managed by the Linux Foundation; almost all of this module applies unchanged |
| **CloudFormation** (and CDK) | AWS only | YAML/JSON (CDK: TypeScript, Python...) | Built into AWS, no state file to manage (topic 7.6) |
| **Bicep** (ARM templates) | Azure only | Bicep | Built into Azure (topic 7.6) |
| **Infrastructure Manager** | Google Cloud only | Terraform (HCL) | Google's managed service that runs Terraform for you; Deployment Manager, its older tool, is being retired (topic 7.6) |
| **Pulumi** | Many | General programming languages | Less common in adverts |

This course uses Terraform for all three clouds, so you learn one language and three providers, and topic 7.6 teaches you to read CloudFormation and Bicep (and Google's Infrastructure Manager, which runs Terraform itself) because you'll meet them at work.

## 2. Installing Terraform

```bash
# Ubuntu / WSL: HashiCorp's official repository
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
terraform version
```

On macOS, `brew tap hashicorp/tap && brew install hashicorp/tap/terraform`. In Codespaces, AWS CloudShell and Azure Cloud Shell, Terraform is often already installed (`terraform version`). Install the **HashiCorp Terraform** extension in VS Code for highlighting and completion.

Terraform signs in to the clouds the same way the CLIs do (topic 6.3): your AWS profile or SSO session, and your `az login`. Nothing extra to configure.

## 3. Providers, resources and HCL

A Terraform configuration is a folder of `.tf` files in **HCL** (HashiCorp Configuration Language). Your first one creates a private, tagged storage bucket on AWS:

```hcl
# main.tf
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "af-south-1"
  default_tags {
    tags = { owner = "ada", purpose = "topic-7.1", managed_by = "terraform" }
  }
}

resource "aws_s3_bucket" "statements" {
  bucket = "itlpay-statements-ada-7-1"
}

resource "aws_s3_bucket_public_access_block" "statements" {
  bucket                  = aws_s3_bucket.statements.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

- A **provider** is a plugin that talks to one platform's API: `hashicorp/aws`, `hashicorp/azurerm`, and thousands of others (GitHub, Cloudflare, Kubernetes, Datadog). `version = "~> 6.0"` allows 6.x updates but not 7.0, which may contain breaking changes.
- A **resource** is one thing to manage. Its address is `TYPE.NAME`: `aws_s3_bucket.statements`. The name is yours; it's how you refer to it elsewhere.
- **References** connect resources: `aws_s3_bucket.statements.id` uses the bucket's ID. Terraform reads these references to work out the **order**: the bucket first, then its public access block.
- `default_tags` tags every AWS resource the provider creates, which is how you satisfy topic 6.1's tagging rule without repeating it.

The same on Azure:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "00000000-0000-0000-0000-000000000000"   # your subscription: az account show --query id -o tsv
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-topic-7-1"
  location = "southafricanorth"
  tags     = { owner = "ada", purpose = "topic-7.1", managed_by = "terraform" }
}

resource "azurerm_storage_account" "statements" {
  name                            = "itlstmtada71"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  tags                            = azurerm_resource_group.lab.tags
}
```

The azurerm provider needs the empty `features {}` block and, since version 4, the `subscription_id`. Notice that the storage account takes its location and tags from the resource group by reference, so they can't drift apart.

And on Google Cloud:

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = "cpe-lab-ada"            # your project ID: gcloud config get-value project
  region  = "africa-south1"
  default_labels = { owner = "ada", purpose = "topic-7-1", managed_by = "terraform" }
}

resource "google_storage_bucket" "statements" {
  name                        = "itlpay-statements-ada-7-1"
  location                    = "africa-south1"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning {
    enabled = true
  }
}
```

Terraform on Google Cloud signs in with **Application Default Credentials**: run `gcloud auth application-default login` once (topic 6.3). `default_labels` labels every resource that supports labels, like AWS's `default_tags`.

## 4. The workflow: init, plan, apply, destroy

```bash
terraform init        # download the providers, set up the backend (topic 7.3); once per folder, and after changes to providers
terraform fmt         # format the files the standard way
terraform validate    # check syntax and references, without touching the cloud
terraform plan -out=tfplan     # compare the files with reality, show what would change, and save that plan
terraform apply tfplan         # do exactly what the saved plan said
terraform destroy              # delete everything this configuration manages (it shows a plan and asks first)
```

Always apply a **saved plan** (`-out`, then `apply tfplan`). That way, what you reviewed is exactly what runs, even if someone changed something in between; Terraform refuses to apply a plan that's out of date.

## 5. Reading a plan

```text
Terraform will perform the following actions:

  # aws_s3_bucket.statements will be created
  + resource "aws_s3_bucket" "statements" {
      + bucket = "itlpay-statements-ada-7-1"
      + arn    = (known after apply)
      ...
    }

  # aws_security_group.db must be replaced
-/+ resource "aws_security_group" "db" {
      ~ name = "itlpay-sg-db" -> "itlpay-dev-sg-db" # forces replacement
    }

Plan: 2 to add, 0 to change, 1 to destroy.
```

| Symbol | Meaning | How careful to be |
| --- | --- | --- |
| `+` | Create | Normal |
| `~` | Update in place | Check the changed values |
| `-/+` or `+/-` | **Replace**: destroy and create again (`forces replacement` shows which attribute caused it) | **Stop and think.** Replacing a database or a disk deletes its data; replacing a network breaks everything in it |
| `-` | Destroy | **Stop and think** |
| `<=` | Read a data source | Normal |

Read the summary line first ("2 to add, 0 to change, 1 to destroy"). Any **destroy** or **replace** of something that holds data or carries traffic needs a second person to look before anyone applies it. Many incidents begin with "the plan said replace, and nobody read it". Topic 7.4 shows how to protect important resources so Terraform refuses to destroy them.

## 6. State: how Terraform knows what exists

After `apply`, Terraform writes a **state file** (`terraform.tfstate`): a map from each resource address in your files to the real resource's ID and attributes. On the next plan, it compares three things: your files, the state, and what the cloud API reports.

Three rules you must know now (topic 7.3 goes further):

- **Don't edit the state file by hand**, and don't delete it: Terraform would forget it manages those resources, and try to create them again.
- **The state can contain secrets** (for example a generated database password) in plain text. **Never commit it to Git**: add `*.tfstate*` and `.terraform/` to `.gitignore`.
- **One state per environment, shared safely**: a state file on your laptop works for a lab, but a team needs remote state with locking (topic 7.3).

## 7. Your first lab, on both clouds

1. Create three folders, `aws-7-1/`, `azure-7-1/` and `gcp-7-1/`, each with the `main.tf` from section 3 (change the names to something unique).
2. In each: `terraform init`, `terraform fmt`, `terraform validate`, `terraform plan -out=tfplan`, `terraform apply tfplan`.
3. Check in each console that the storage exists, is private and has the tags.
4. Change one tag in each file, plan again, and read the `~` update.
5. Change the S3 bucket's name and plan: read the `-/+` replace, and **don't apply it**.
6. `terraform destroy` in all three folders.

## Practice

1. Do the lab in section 7 on all three clouds, and paste the plans' summary lines into your learning log.
2. Run `terraform plan` again straight after an apply. Why does it say "No changes"?
3. In the AWS folder, delete the bucket's public access block in the console, then run `terraform plan`. What does Terraform want to do, and why? (This is **drift**, topic 7.5.)
4. Look inside `terraform.tfstate` with `terraform state list` and `terraform state show aws_s3_bucket.statements` (not a text editor). What does it record?
5. Write a short ADR (topic 4.3): "Use Terraform for all three clouds rather than CloudFormation, Bicep and Infrastructure Manager." Include at least two reasons for and one against.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Terraform in 100 Seconds](https://www.youtube.com/watch?v=tomUWcQ0P3k) · Fireship · 2 min. Terraform in 100 seconds.
- [Terraform Explained](https://www.youtube.com/watch?v=HmxkYNv1ksg) · IBM Technology · 9 min. What Terraform is and how it works, from IBM.
- [Terraform explained in 15 mins | Terraform Tutorial for Beginners](https://www.youtube.com/watch?v=l5k1ai_GBDE) · TechWorld with Nana · 18 min. Terraform's core ideas: providers, resources, state and the workflow.
- [Learn Terraform with Google Cloud Platform – Infrastructure as Code Course](https://www.youtube.com/watch?v=VCayKl82Lt8) (optional, longer) · freeCodeCamp.org · 52 min. Terraform with Google Cloud, a full course.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Introduction to infrastructure as code using Terraform](https://learn.microsoft.com/training/modules/terraform-introduction-to-infrastructure-as-code/)
- [Fundamentals of Terraform on Azure (learning path)](https://learn.microsoft.com/training/paths/terraform-fundamentals/)

**AWS (AWS Skill Builder):**

- [AWS CloudFormation Getting Started](https://skillbuilder.aws/learn/RH22P2RXU4/aws-cloudformation-getting-started/KEK5BT6HSE)
- [Faster and Safer Infrastructure Deployment with AWS CloudFormation and CDK](https://skillbuilder.aws/learn/V8MQ93JRH6/faster-and-safer-infrastructure-deployment-with-aws-cloudformation-and-cdk/7WDJCSKBQV)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Getting Started with Terraform for Google Cloud](https://www.skills.google/course_templates/443)
- [Associate Cloud Engineer Certification (learning path)](https://www.skills.google/paths/11)

**Terraform (HashiCorp's free tutorials):**

- [Get started with Terraform on AWS](https://developer.hashicorp.com/terraform/tutorials/aws-get-started)
- [Get started with Terraform on Azure](https://developer.hashicorp.com/terraform/tutorials/azure-get-started)

