## What you will be able to do

- Read an **AWS CloudFormation** template (YAML) and an **Azure Bicep** file, and say what they create.
- Map their building blocks to Terraform's: parameters, resources, references, outputs, modules.
- Explain how each tool manages state and changes: stacks and change sets; deployments and what-if.
- Deploy, preview and delete a small template with each cloud's CLI.
- Decide when a team would choose the native tool over Terraform, and work in a company that uses them.
- Translate a small CloudFormation or Bicep file into Terraform, and back.

## Why this matters at work

Terraform is the most common choice across clouds, but many companies use the clouds' own tools: AWS-only shops often use CloudFormation or the CDK, Microsoft-centred banks and governments often use Bicep, and many AWS and Azure products ship their examples, quick starts and marketplace offers as CloudFormation templates or Bicep/ARM files. In a new job you'll be asked to read, fix and deploy them, and the certifications (AWS Solutions Architect, AZ-104) ask about them. You don't need to master both; you do need to read them comfortably.

## 1. The same bucket, three ways

**Terraform** (topic 7.1):

```hcl
resource "aws_s3_bucket" "statements" {
  bucket = "itlpay-statements-ada"
}
```

**CloudFormation** (`statements.yaml`):

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: Private, versioned statements bucket for ITL Pay
Parameters:
  Owner:
    Type: String
    Description: Who owns these resources
Resources:
  StatementsBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "itlpay-statements-${Owner}"
      VersioningConfiguration:
        Status: Enabled
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      Tags:
        - Key: owner
          Value: !Ref Owner
    DeletionPolicy: Retain
    UpdateReplacePolicy: Retain
Outputs:
  BucketArn:
    Value: !GetAtt StatementsBucket.Arn
```

**Bicep** (`statements.bicep`):

```bicep
@description('Who owns these resources')
param owner string
param location string = resourceGroup().location

resource statements 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'itlstmt${owner}'
  location: location
  sku: { name: 'Standard_ZRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
  tags: { owner: owner }
}

output storageId string = statements.id
```

## 2. Reading CloudFormation

| CloudFormation | Means | Terraform equivalent |
| --- | --- | --- |
| `Parameters:` | Inputs | `variable` |
| `Resources:` → `LogicalName:` → `Type: AWS::S3::Bucket` | A resource and its type | `resource "aws_s3_bucket" "name"` |
| `!Ref Owner` | A parameter's value, or a resource's main ID | `var.owner`, `aws_s3_bucket.x.id` |
| `!GetAtt Bucket.Arn` | Another attribute of a resource | `aws_s3_bucket.x.arn` |
| `!Sub "name-${Owner}"` | Text with values inserted | `"name-${var.owner}"` |
| `Conditions:`, `!If` | Optional resources and values | `count = var.x ? 1 : 0`, conditional expressions |
| `Mappings:`, `!FindInMap` | Lookup tables | `locals` maps, `lookup()` |
| `DeletionPolicy: Retain` and `UpdateReplacePolicy: Retain` | Keep the real resource if the stack is deleted, or if an update replaces it (you need both; `cfn-lint` warns if one is missing) | `prevent_destroy`, `removed { destroy = false }` |
| `Outputs:` (with `Export`) | Results, optionally shared with other stacks (`!ImportValue`) | `output`, remote state or data sources |
| Nested stacks, or the **CDK** | Reuse | Modules |

Two big differences from Terraform:

- **No state file to manage.** CloudFormation keeps the state itself, in the **stack**. That's simpler (nothing to lock or protect) but you can only see and change the resources through the stack.
- **Change sets** are CloudFormation's plan: create one, read it, then execute it.

```bash
aws cloudformation validate-template --template-body file://statements.yaml
aws cloudformation deploy --stack-name itlpay-statements --template-file statements.yaml \
  --parameter-overrides Owner=ada --no-execute-changeset          # creates a change set to review
aws cloudformation describe-change-set --stack-name itlpay-statements --change-set-name <name from the output>
aws cloudformation execute-change-set --stack-name itlpay-statements --change-set-name <name>
aws cloudformation delete-stack --stack-name itlpay-statements    # the bucket stays (DeletionPolicy: Retain); empty and delete it by hand
```

**Drift detection** is built in: `aws cloudformation detect-stack-drift`. Linters: `cfn-lint`, and checkov reads CloudFormation too.

The **AWS CDK** lets you write CloudFormation in TypeScript, Python, Java or C#; `cdk synth` turns your code into a CloudFormation template, and `cdk diff` shows the change. If a team uses the CDK, what's deployed is still CloudFormation, so everything above applies.

## 3. Reading Bicep

| Bicep | Means | Terraform equivalent |
| --- | --- | --- |
| `param owner string` | Input (decorators like `@description`, `@allowed`, `@minLength` add rules) | `variable` with validation |
| `var` | A computed value | `locals` |
| `resource name 'Type@apiVersion' = { ... }` | A resource, with the exact Azure API version | `resource "azurerm_..." "name"` |
| `statements.id`, `statements.properties.primaryEndpoints` | References | `azurerm_storage_account.x.id` |
| `existing` resources | Read something that already exists | Data sources |
| `module net './network.bicep' = { params: {...} }` | Reuse | `module` |
| `output` | Results | `output` |
| `for` loops and `if` conditions | Many or optional resources | `for_each`, `count` |

Bicep compiles to **ARM templates** (JSON), the format Azure Resource Manager understands; you'll see ARM JSON in older repositories and in the portal's "Export template". Like CloudFormation, there's **no state file**: Azure Resource Manager knows what's deployed.

```bash
az bicep build --file statements.bicep                         # compile and check
az group create -n rg-topic-7-6 -l southafricanorth
az deployment group what-if -g rg-topic-7-6 --template-file statements.bicep --parameters owner=ada   # the plan
az deployment group create -g rg-topic-7-6 --template-file statements.bicep --parameters owner=ada
az group delete -n rg-topic-7-6 --yes
```

`what-if` is Bicep's plan: it shows creates, modifies and deletes before you deploy. A deployment's **mode** matters: the default **incremental** mode adds and updates but leaves other resources in the group alone; **complete** mode deletes anything in the resource group that isn't in the template, which is powerful and dangerous. **Deployment stacks** (newer) add Terraform-like management of what a deployment owns, including deny settings that block changes outside the stack.

Linters: Bicep's built-in linter (`az bicep lint`), and checkov reads Bicep and ARM.

## 4. When teams choose the native tools

| Choose the native tool when | Choose Terraform when |
| --- | --- |
| The company uses one cloud and wants no extra tool or state to manage | You use more than one cloud, or many SaaS providers (GitHub, Cloudflare, Datadog) |
| You want new cloud features on day one (native tools usually support them first) | You want one language and one workflow for everything |
| The vendor's examples or marketplace products come as templates | The team already knows Terraform (it's the most common skill in job adverts) |
| Policies require it (some government and regulated environments) | You need a mature module ecosystem and testing tools |

Many companies use both: Terraform for the platform, and native templates for specific vendor products. That's why this course teaches Terraform deeply and the native tools for reading.

## Practice

1. Deploy `statements.yaml` with a change set (review it before executing), check the bucket in the console, delete the stack, then empty and delete the retained bucket by hand.
2. Deploy `statements.bicep` with `what-if` first, then for real. Delete the resource group.
3. Translate the CloudFormation template into Terraform, and the Bicep file into Terraform with the azurerm provider. Run `terraform plan` on both and compare what each would create.
4. In the Azure portal, open any resource group with a resource in it and choose **Export template**. Read the ARM JSON and find the resources, parameters and API versions. What would you remove before reusing it?
5. Write an ADR (topic 4.3) for a fictional all-Azure bank choosing between Bicep and Terraform, with at least two options considered.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [AWS CloudFormation for Beginners](https://www.youtube.com/watch?v=2gT1dvbppg8) · Digital Cloud Training · 10 min. AWS CloudFormation for beginners: stacks, templates and change sets.
- [Azure Bicep explained in 5 mins | Azure Bicep Tutorial for Beginners | 2022](https://www.youtube.com/watch?v=AkZqEIzgcZo) · Talking tech with Techielass · 6 min. Azure Bicep explained in five minutes.
- [Get started with Bicep | A Step-by-step guide from scratch](https://www.youtube.com/watch?v=17FI_KXQfMg) · PetterTech · 25 min. Getting started with Bicep, step by step.

## Further learning (free)

Free, self-paced courses from the two clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn and a free AWS Builder ID for AWS Skill Builder to track your progress.

**Azure (Microsoft Learn):**

- [Fundamentals of Bicep (learning path)](https://learn.microsoft.com/training/paths/fundamentals-bicep/)
- [Deploy Azure infrastructure by using JSON ARM templates](https://learn.microsoft.com/training/modules/create-azure-resource-manager-template-vs-code/)

**AWS (AWS Skill Builder):**

- [AWS CloudFormation Getting Started](https://skillbuilder.aws/learn/RH22P2RXU4/aws-cloudformation-getting-started/KEK5BT6HSE)
- [AWS Cloud Development Kit (CDK) Getting Started](https://skillbuilder.aws/learn/XP346HYHM9/aws-cloud-development-kit-cdk-getting-started/D6C46ND6ZQ)

