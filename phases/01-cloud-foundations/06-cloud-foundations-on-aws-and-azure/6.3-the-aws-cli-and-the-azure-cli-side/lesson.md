## What you will be able to do

- Install and sign in to the **AWS CLI** and the **Azure CLI**, including in Codespaces and the browser-based **CloudShell** of each cloud.
- Use profiles (AWS) and subscriptions (Azure) to work with more than one account safely.
- Read the structure of each CLI's commands, and find help for any command.
- Filter and format output with `--query` (JMESPath), `--output` and `jq`.
- Write safe, idempotent Bash scripts that create, tag, list and delete resources on both clouds.
- Explain where the CLI stops being the right tool, and Terraform (Phase 2) takes over.
- Do the same on **Google Cloud**, and compare the three clouds.

## Why this matters at work

The web consoles are fine for exploring, but real work is repeatable: the same steps in dev, staging and production, written down, reviewed and run by scripts and pipelines. The command-line tools are how you script both clouds, how you investigate quickly during incidents ("list every security group that allows port 22 from anywhere"), and what you'll use in every remaining topic of this module and in Capstone 1. Interviewers often ask candidates to describe how they'd find or change something with the CLI.

## 1. Installing and signing in

The easiest start needs no installation: each cloud has a browser terminal, already signed in, with both CLIs and common tools:

- **AWS CloudShell:** the terminal icon at the top of the AWS console.
- **Azure Cloud Shell:** the `>_` icon at the top of the Azure portal (choose Bash).

To install locally (Ubuntu/WSL; see each vendor's guide for other systems):

```bash
# AWS CLI v2
curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install && aws --version

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash && az version
```

(Downloading and running an install script with `sudo` means trusting its source; these are the vendors' official install methods. Read them first if you're unsure.)

Sign in **as your everyday user, never as root/Global Administrator day to day** (topic 6.1):

```bash
# AWS, with IAM Identity Center (recommended): short-lived credentials, refreshed by signing in again
aws configure sso                    # once: start URL, region, account, role; saves a named profile
aws sso login --profile learn
aws sts get-caller-identity --profile learn      # who am I?

# Azure
az login                             # opens a browser (use `az login --use-device-code` in a terminal-only machine)
az account list -o table             # subscriptions you can see
az account set --subscription "Azure for Students"
az account show -o table             # which one am I using?
```

Avoid long-lived access keys (`aws configure` with a key and secret) except where there's no alternative; if you must use them while learning, give them the narrowest permissions and delete them when done.

## 2. Profiles and subscriptions: knowing where you are

The most dangerous CLI mistake is running a command in the **wrong account or subscription**. Make your current context obvious:

```bash
export AWS_PROFILE=learn                       # every aws command now uses this profile
export AWS_REGION=af-south-1
aws configure list                             # shows profile, region and where each came from

az account set --subscription "<name or id>"
az config set defaults.location=southafricanorth defaults.group=rg-lab-6-3
```

Before any command that changes something, check `aws sts get-caller-identity` or `az account show`. Scripts should check too (section 5).

## 3. How the commands are built

```text
aws  <service> <operation>      [--options]       aws ec2 describe-instances --region af-south-1
az   <group> [<subgroup>] <verb> [--options]       az vm list --resource-group rg-itlpay
```

| Find help | AWS | Azure |
| --- | --- | --- |
| List services or groups | `aws help` | `az --help` |
| A service's operations | `aws ec2 help` | `az vm --help` |
| One command's options and examples | `aws ec2 describe-instances help` | `az vm create --help` |
| Interactive help and completion | `aws --cli-auto-prompt` | `az interactive` |
| Find a command by keyword | Search the AWS CLI reference | `az find "create storage account"` |

Both CLIs map closely to the cloud's API, so the operation names match the documentation.

## 4. Getting exactly the output you want

Both CLIs return JSON by default and can show tables or plain text:

```bash
aws ec2 describe-regions --output table
az account list-locations --output table
```

Both support **`--query`**, using the JMESPath language, to pick out fields:

```bash
# AWS: instance IDs and states
aws ec2 describe-instances \
  --query "Reservations[].Instances[].{id:InstanceId, state:State.Name, type:InstanceType}" --output table

# Azure: VM names and sizes in a resource group
az vm list -g rg-itlpay --query "[].{name:name, size:hardwareProfile.vmSize}" -o table

# A single value for scripts, with no quotes
vpc_id=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=itlpay --query "Vpcs[0].VpcId" --output text)
rg_id=$(az group show -n rg-itlpay --query id -o tsv)
```

Use `--output text` (AWS) or `-o tsv` (Azure) when putting a value into a Bash variable. For more complex processing, pipe JSON to **jq** (`sudo apt install -y jq`), or use Python (topic 3.4).

AWS also has **server-side filters** (`--filters`), which are faster for large accounts: `aws ec2 describe-security-groups --filters Name=ip-permission.from-port,Values=22`.

## 5. Side by side: a tagged resource group or stack, a storage bucket, then clean-up

Create the same thing on both clouds: a private storage location, tagged, then delete it. Compare as you go.

```bash
#!/usr/bin/env bash
# lab-6-3.sh: create a private, tagged storage location on AWS and Azure, list it, delete it.
set -euo pipefail

owner="ada"                                   # change to your name
suffix=$(date +%s)                            # names must be globally unique
bucket="itl-lab-${owner}-${suffix}"           # S3 bucket name
sa="itllab${owner}${suffix: -6}"              # Azure storage account: 3-24 lowercase letters/digits
rg="rg-lab-6-3"
region="af-south-1"
location="southafricanorth"

echo "AWS as: $(aws sts get-caller-identity --query Arn --output text)"
echo "Azure as: $(az account show --query user.name -o tsv) in $(az account show --query name -o tsv)"
read -r -p "Continue? (yes/no) " ok; [[ "$ok" == "yes" ]] || exit 1

# --- AWS ---
aws s3api create-bucket --bucket "$bucket" --region "$region" \
  --create-bucket-configuration LocationConstraint="$region"
aws s3api put-public-access-block --bucket "$bucket" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-tagging --bucket "$bucket" \
  --tagging "TagSet=[{Key=owner,Value=$owner},{Key=purpose,Value=topic-6.3}]"

# --- Azure ---
az group create -n "$rg" -l "$location" --tags owner="$owner" purpose=topic-6.3 -o none
az storage account create -n "$sa" -g "$rg" -l "$location" --sku Standard_LRS \
  --allow-blob-public-access false --min-tls-version TLS1_2 --tags owner="$owner" purpose=topic-6.3 -o none

# --- List what we made, by tag ---
aws resourcegroupstaggingapi get-resources --region "$region" --tag-filters Key=purpose,Values=topic-6.3 \
  --query "ResourceTagMappingList[].ResourceARN" --output text
az resource list --tag purpose=topic-6.3 --query "[].{name:name, type:type}" -o table

read -r -p "Delete everything now? (yes/no) " ok
if [[ "$ok" == "yes" ]]; then
  aws s3api delete-bucket --bucket "$bucket" --region "$region"
  az group delete -n "$rg" --yes --no-wait
  echo "Deleted (the Azure resource group is being removed in the background)."
fi
```

Things to notice:

- **Names:** S3 bucket names and storage account names are **globally unique** across all customers, so add something unique. Each cloud has different naming rules (Azure storage accounts allow only 3–24 lowercase letters and digits).
- **Private by default:** both are private when created this way; the script states it explicitly anyway (Block Public Access; `--allow-blob-public-access false`), which is what reviewers want to see.
- **Clean-up:** on Azure, deleting the **resource group** removes everything in it. On AWS there's no equivalent folder: you delete each resource (Phase 2's Terraform and CloudFormation stacks fix this).
- **Checks before changes:** the script shows who and where you are, and asks before creating and before deleting.

## 6. Making CLI scripts safe and idempotent

Everything from topic 3.2 applies, plus:

- **Check before create** to make scripts re-runnable:

  ```bash
  aws s3api head-bucket --bucket "$bucket" 2>/dev/null || aws s3api create-bucket ...
  az group exists -n "$rg" | grep -q true || az group create -n "$rg" -l "$location"
  ```

  (Some `az ... create` commands are already idempotent and update the resource if it exists; read each command's documentation.)
- **Fail if the context is wrong:** compare `aws sts get-caller-identity --query Account` or `az account show --query id` with the expected value, and stop if they differ.
- **Tag everything** with owner and purpose, and use the tags to find and delete things.
- **Wait for resources** that take time: `aws ec2 wait instance-running --instance-ids ...`; `az vm wait --created -g ... -n ...`.
- **Don't print secrets**: connection strings and keys appear in some command outputs; send them straight to a secret store, not the terminal.

## 7. Where the CLI stops being the right tool

Scripts that create infrastructure step by step get complicated: what if step 7 of 12 fails? How do you change one setting on resources that already exist? How do you see what will change before it changes? **Infrastructure as code** tools (Terraform, CloudFormation, Bicep) describe the **end state** and work out the steps themselves, with a "plan" you can review in a pull request. That's Phase 2. The CLI stays essential for investigation, one-off tasks, glue in pipelines and quick fixes, and the skills in this topic carry straight over.

## The Google Cloud CLI: gcloud

**Install and sign in:** **Cloud Shell** (the `>_` icon in the Google Cloud console) has `gcloud`, Terraform and common tools ready. Locally, install the Google Cloud CLI from Google's official instructions (an apt repository for Ubuntu and WSL), then:

```bash
gcloud init                                   # sign in and choose a default project and region
gcloud auth login                             # your user, for gcloud commands
gcloud auth application-default login         # credentials for Terraform and the SDKs (topic 7.1)
gcloud config set project cpe-lab-ada
gcloud config set compute/region africa-south1
gcloud config list                            # who and where am I?
gcloud config configurations create work      # named profiles, like AWS profiles: switch with `configurations activate`
```

**One Google Cloud gotcha:** each service's API must be **enabled** in a project before first use: `gcloud services enable compute.googleapis.com storage.googleapis.com`. The first command against a new service often fails until you do.

**The command shape** is `gcloud <group> [<subgroup>] <verb>`, for example `gcloud compute instances list`. Help: `gcloud help`, `gcloud compute instances create --help`. **Output and filters:**

```bash
gcloud compute instances list --format="table(name, zone.basename(), status)"
gcloud compute instances list --filter="labels.purpose=topic-6-5" --format="value(name)"   # one value per line, for scripts
gcloud projects describe cpe-lab-ada --format=json | jq .projectNumber
```

`--format=value(...)` is the equivalent of `--output text` and `-o tsv`.

**The lab on Google Cloud:** the same private, labelled storage, then clean-up:

```bash
project=$(gcloud config get-value project)
bucket="itl-lab-${owner}-${suffix}"
echo "Google Cloud as: $(gcloud config get-value account) in $project"
gcloud storage buckets create "gs://$bucket" --location=africa-south1 \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update "gs://$bucket" --update-labels=owner="$owner",purpose=topic-6-3
gcloud storage buckets list --filter="labels.purpose=topic-6-3" --format="value(name)"
gcloud storage buckets delete "gs://$bucket"
```

Add these lines to `lab-6-3.sh` (after the Azure part, using the same `owner` and `suffix`). Notice: bucket names are globally unique like S3's; label values allow only lowercase letters, numbers, `-` and `_`, so `topic-6.3` becomes `topic-6-3`; and the project is the clean-up unit.

## Practice

1. Open AWS CloudShell and Azure Cloud Shell, and run `aws sts get-caller-identity` and `az account show` in each. Then install both CLIs locally (or in Codespaces) and sign in as your everyday user.
2. List the regions/locations available to you on both clouds, as tables. Is `af-south-1` enabled in your AWS account?
3. Run `lab-6-3.sh` from section 5 (copy it into your `ops-scripts` repository, make it pass `shellcheck`). Confirm in both consoles that the storage is private and tagged, then let the script delete it.
4. Write one `--query` per cloud that lists every security group / NSG rule that allows inbound port 22 from anywhere (`0.0.0.0/0` or `*`/`Internet`). Run it (you may have none, which is good).
5. Make `lab-6-3.sh` refuse to run unless the AWS account ID and Azure subscription ID match values in a config file.
6. **Google Cloud:** do the same in Cloud Shell and with a local `gcloud`; add the Google Cloud part to `lab-6-3.sh`; and write a `gcloud ... --filter` that lists firewall rules allowing port 22 from `0.0.0.0/0`.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [AWS CLI Tutorial | Learn to run AWS CLI commands in 10 minutes](https://www.youtube.com/watch?v=21-t7Rkokmo) · AWS Made Easy · 11 min. Running your first AWS CLI commands.
- [Azure CLI Tutorial](https://www.youtube.com/watch?v=GqpwiyYsNIw) · Adam Marczak - Azure for Everyone · 25 min. The Azure CLI, step by step.
- [What is the Google Cloud CLI?](https://www.youtube.com/watch?v=FBU_tF7UzQY) · Google Cloud Tech · 3 min. What the Google Cloud CLI is, from Google.
- [Gcloud command-line tips and tricks](https://www.youtube.com/watch?v=ezzZ--xt43c) · Google Cloud Tech · 10 min. gcloud tips: configurations, formats and filters, from Google.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Guided project: Manage Azure resources with Cloud Shell and the Azure CLI](https://learn.microsoft.com/training/modules/guided-project-manage-resources-cloud-shell-cli/)
- [Introduction to Azure Cloud Shell](https://learn.microsoft.com/training/modules/intro-to-azure-cloud-shell/)

**AWS (AWS Skill Builder):**

- [AWS Command Line Interface (AWS CLI) Getting Started](https://skillbuilder.aws/learn/HNQT94X934/aws-command-line-interface-aws-cli-getting-started/QHT6C7ZHDA)
- [Build with AWS Command Line Interface (AWS CLI)](https://skillbuilder.aws/learn/AVW7M7MTWY/build-with-aws-command-line-interface-aws-cli/BBYQYTJG3M)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Essential Google Cloud Infrastructure: Foundation](https://www.skills.google/course_templates/50)
- [Google Cloud Computing Foundations: Infrastructure in Google Cloud](https://www.skills.google/course_templates/154)

