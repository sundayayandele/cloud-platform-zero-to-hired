## What you will be able to do

- Use **variables** (with types, defaults, descriptions and validation), **locals** and **outputs**.
- Read existing infrastructure with **data sources**.
- Create many similar resources with `count` and `for_each`, and know which to choose.
- Use Terraform's functions and expressions: `cidrsubnet`, `merge`, `for` expressions, conditionals.
- Write a **module** with a clear interface, and use it from an environment folder.
- Read and use the course's network modules for AWS and Azure, which share one interface.
- Do the same on **Google Cloud** with the `google` provider, and compare the three clouds.

## Why this matters at work

Real infrastructure isn't one file. The same network is needed in dev, staging and production; every team needs a storage bucket with the same security settings; every service needs the same tags. Modules and variables let you write that once, review it once, and reuse it everywhere, so a security fix is made in one place instead of forty. Platform teams publish internal modules ("golden paths", Phase 3) that other teams must use. Being able to design a clean module interface is what moves you from writing Terraform to owning it.

## 1. Variables

Variables are a configuration's inputs:

```hcl
variable "name" {
  description = "Prefix for every resource name, for example itlpay-dev"
  type        = string
}

variable "cidr" {
  description = "Address range of the network, for example 10.20.0.0/16"
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr, 0))
    error_message = "cidr must be a valid IPv4 CIDR block, such as 10.20.0.0/16."
  }
}

variable "nat_gateway" {
  description = "Create a NAT gateway (costs money every hour)"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

- **Types**: `string`, `number`, `bool`, `list(string)`, `map(string)`, `object({...})`, and more. A wrong type fails at plan time, not halfway through an apply.
- **`default`** makes a variable optional. No default means the caller must set it.
- **`validation`** rejects bad values early with your own message.
- **`sensitive = true`** hides a value in plan output (it's still stored in state).

Ways to set them, from lowest to highest priority: the default; a `terraform.tfvars` or `*.auto.tfvars` file; `-var-file=prod.tfvars`; `-var name=value`; an environment variable `TF_VAR_name`. Use `.tfvars` files for environment settings, and **never put secrets in a `.tfvars` file in Git**: pass them from the environment or, better, keep them in a secret store (topic 10.2).

Use a variable as `var.name`.

## 2. Locals and outputs

**Locals** are named values computed inside the configuration, to avoid repeating yourself:

```hcl
locals {
  tags   = merge(var.tags, { module = "aws-network" })
  public = [for i, z in local.zones : cidrsubnet(var.cidr, 8, i)]
}
```

Use them as `local.tags`.

**Outputs** are a configuration's results, shown after apply and readable by other configurations:

```hcl
output "app_subnet_ids" {
  description = "App subnets, one per zone"
  value       = aws_subnet.app[*].id
}
```

`terraform output` shows them; `terraform output -json` gives them to scripts. Mark secrets `sensitive = true`.

## 3. Data sources: reading what already exists

A **data source** reads something Terraform doesn't manage, so you can use it:

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "azurerm_client_config" "current" {}   # who am I: tenant, subscription, object ID
```

Use them as `data.aws_availability_zones.available.names`. Data sources replace hard-coded IDs (an AMI ID that differs per region, a zone name that doesn't exist in another region), which is one of the most common reasons configurations break when copied.

## 4. Many resources: count and for_each

```hcl
# count: N copies, addressed by number
resource "aws_subnet" "app" {
  count             = var.zone_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.app[count.index]
  availability_zone = local.zones[count.index]
}
# addresses: aws_subnet.app[0], aws_subnet.app[1]

# for_each: one per key, addressed by key
resource "azurerm_storage_container" "this" {
  for_each           = toset(["statements", "exports", "audit"])
  name               = each.key
  storage_account_id = azurerm_storage_account.this.id
}
# addresses: azurerm_storage_container.this["statements"], ...
```

Prefer **`for_each`** when items have names. With `count`, removing the first item of a list shifts every index, so Terraform plans to destroy and recreate everything after it. With `for_each`, removing `"exports"` only removes `"exports"`.

`count = var.nat_gateway ? 1 : 0` is the usual way to make a resource optional.

## 5. Expressions and functions you'll use weekly

```hcl
cidrsubnet("10.20.0.0/16", 8, 1)                  # "10.20.1.0/24": slice a range (topic 2.2)
merge(var.tags, { tier = "app" })                 # combine maps
[for s in aws_subnet.app : s.id]                  # transform a list
{ for k, v in var.services : k => v.port }        # build a map
var.env == "prod" ? 3 : 1                         # conditional
lookup(var.sizes, var.env, "small")               # map lookup with a default
try(var.settings.backup, true)                    # a fallback if an attribute is missing
```

Try any expression in `terraform console`, an interactive shell that knows your variables and state.

## 6. Modules

A **module** is just a folder of `.tf` files with variables (inputs) and outputs. Every configuration is a module; the one you run `terraform` in is the **root module**, and it can call **child modules**:

```hcl
module "network" {
  source      = "../../modules/aws-network"    # a local folder; or a Git URL with a tag, or a registry address
  name        = "itlpay-dev"
  cidr        = "10.20.0.0/16"
  nat_gateway = false
}

output "app_subnets" {
  value = module.network.app_subnet_ids
}
```

Good module design:

- **A small, clear interface**: few required inputs, sensible defaults, descriptions on everything, validation where mistakes are likely.
- **Secure by default**: the module creates private subnets with no internet route for data, restrictive rules, encryption on. Callers shouldn't have to remember.
- **No provider blocks inside reusable modules**: the caller configures providers (region, credentials). The module only declares `required_providers` with a version range.
- **Versioned**: shared modules are referenced by a Git tag (`source = "git::https://github.com/org/modules.git//aws-network?ref=v1.4.0"`) or a registry version, so a change doesn't surprise everyone at once.
- **Composable**: a network module doesn't also create the database. Small modules combine; giant ones get forked and diverge.

The **Terraform Registry** (registry.terraform.io) has well-known public modules, such as `terraform-aws-modules/vpc/aws` and Azure Verified Modules. They're great to read and often fine to use; many companies still write their own thin modules to enforce their rules.

## 7. The course's network modules

`labs/terraform-network/` (in the course labs download and the public repository) contains ITL Pay's network from topic 6.4 as three modules with **the same interface**:

| | `modules/aws-network` | `modules/azure-network` | `modules/gcp-network` |
| --- | --- | --- | --- |
| Inputs | `name`, `cidr`, `nat_gateway`, `tags`, plus `zone_count` | `name`, `cidr`, `nat_gateway`, `tags`, plus `location`, `resource_group_name` | `name`, `cidr`, `nat_gateway`, `tags`, plus `project_id`, `region` |
| Outputs | `network_id`, `public_subnet_ids`, `app_subnet_ids`, `data_subnet_ids`, `security_group_ids` | The same five, plus `appgw_subnet_id`, `bastion_subnet_id` | The same five, plus `private_services_range` |
| Builds | VPC, subnets per AZ, internet gateway, optional NAT, route tables, three security groups that reference each other | VNet, one subnet per tier (plus Bastion and Application Gateway subnets), optional NAT, NSGs with an explicit deny inside the VNet, an application security group | Global VPC, one regional subnet per tier with flow logs, optional Cloud NAT, firewall rules that target the network tag `app`, private services access for Cloud SQL |

Read the three `main.tf` files side by side. The decisions are the same as in topic 6.4; only the building blocks differ. Notice:

- `cidrsubnet` derives every subnet from the one network range, so changing `cidr` moves the whole plan consistently;
- `zone_count` has a validation, because a third app subnet would overlap the data subnets in this layout: modules should refuse inputs that would produce a broken network;
- the Azure data subnet is **delegated** to PostgreSQL Flexible Server (topic 6.7) and has `default_outbound_access_enabled = false`, so it's private on purpose, not by luck.

The environment folders `envs/dev-aws`, `envs/dev-azure` and `envs/dev-gcp` call the modules. In Capstone 2 you'll extend this to dev, staging and production.

## Practice

1. Apply `envs/dev-aws`, `envs/dev-azure` and `envs/dev-gcp` (with `nat_gateway = false`). Use `terraform output -json` and `jq` to print the app subnet IDs from each. Destroy both.
2. Add a `zone_count = 3` to the AWS environment and run `plan`. Read the validation message. Then change the layout in a copy of the module so three zones fit (hint: move the data subnets), and prove with `terraform console` and `cidrsubnet` that nothing overlaps.
3. Write a small module `modules/aws-bucket` that creates a private, versioned, encrypted S3 bucket with lifecycle rules, with inputs `name`, `expire_days` and `tags`. Write `modules/azure-storage` and `modules/gcp-bucket` with the same interface. Use both from one environment.
4. Convert a `count` resource to `for_each` in a copy of a module and run `plan`. What does Terraform want to do to the existing resources? (Topic 7.5 shows how to avoid that with `moved` blocks.)
5. In your learning log, list three things that make a module "secure by default".

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Terraform Basics: Modules](https://www.youtube.com/watch?v=GSXx8AZjKK4) · Ned in the Cloud · 15 min. Writing and using Terraform modules.
- [How to Use Terraform Variables & .tfvars Files | Practical Examples](https://www.youtube.com/watch?v=B6l2UbCsH94) · Spacelift · 21 min. Variables and .tfvars files, with practical examples.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Fundamentals of Terraform on Azure (learning path)](https://learn.microsoft.com/training/paths/terraform-fundamentals/)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Getting Started with Terraform for Google Cloud](https://www.skills.google/course_templates/443)

**Terraform (HashiCorp's free tutorials):**

- [Customize Terraform configuration with variables](https://developer.hashicorp.com/terraform/tutorials/configuration-language/variables)
- [Modules](https://developer.hashicorp.com/terraform/tutorials/modules)

