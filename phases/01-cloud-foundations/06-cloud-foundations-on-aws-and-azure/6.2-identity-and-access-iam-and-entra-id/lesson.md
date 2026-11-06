## What you will be able to do

- Explain authentication and authorisation, and the parts of cloud access: identities, permissions, scopes and conditions.
- Read and write a basic **AWS IAM policy** in JSON, and explain users, groups, roles and the policy evaluation rules.
- Assign **Azure RBAC** roles at the right scope, and explain Entra ID users, groups, service principals and managed identities.
- Give a workload (a VM, a container, a pipeline) access **without any stored keys**: IAM roles and managed identities.
- Apply least privilege, MFA and access reviews on both clouds.
- Investigate "access denied" errors from the logs, and know where to look for who did what (CloudTrail, the Azure Activity Log).

## Why this matters at work

Identity is the real perimeter in the cloud. Firewalls matter, but most serious cloud incidents begin with credentials: a leaked access key, an over-powerful role, a forgotten user who left the company. Every cloud job interview asks about least privilege and roles. Every day at work you'll grant someone access, fix an "AccessDenied", or remove access that's no longer needed. This topic is the cloud version of topic 1.3's Linux users and permissions, with much bigger consequences.

## 1. The parts of access

Every cloud request answers two questions:

- **Authentication (who are you?):** a person signing in with a password and MFA, or a program presenting credentials.
- **Authorisation (are you allowed to do this, here?):** the permissions attached to that identity, for that action, on that resource.

| Part | AWS | Azure |
| --- | --- | --- |
| A person | IAM Identity Center user (or an IAM user) | Entra ID user |
| A team | Group | Group |
| A workload's identity | **IAM role** (assumed by EC2, Lambda, ECS tasks, pipelines) | **Managed identity** (system- or user-assigned); service principal for external apps |
| A set of permissions | **Policy** (JSON document) | **Role definition** (built-in like *Reader*, *Contributor*, or custom) |
| Where permissions apply | The policy's `Resource` element, and which account | **Scope**: management group, subscription, resource group, or a single resource |
| Granting | Attach a policy to a user, group or role | **Role assignment**: role + identity + scope |
| Organisation-wide limits | SCPs, permission boundaries | Azure Policy, deny assignments |
| Audit log | **CloudTrail** | **Activity Log** (control plane) and Entra sign-in logs |

## 2. AWS IAM policies

An IAM policy is JSON. This one lets the holder read objects from one S3 bucket and nothing else:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadStatementsBucket",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::itlpay-statements",
        "arn:aws:s3:::itlpay-statements/*"
      ]
    }
  ]
}
```

- **Effect** is `Allow` or `Deny`.
- **Action** names API operations (`service:Operation`); wildcards like `s3:Get*` are possible but widen access.
- **Resource** names exactly what it applies to, by **ARN** (Amazon Resource Name).
- An optional **Condition** narrows it further, for example only from your company's IP range, only with MFA, or only in `af-south-1`.

How AWS decides:

1. Everything is **denied by default**.
2. An explicit **Allow** in an applicable policy permits it...
3. ...unless an explicit **Deny** anywhere applies (an SCP, a permission boundary, a resource policy, or the identity's own policies). **Deny always wins.**

AWS provides **managed policies** (for example `ReadOnlyAccess`, `AdministratorAccess`); they're convenient but usually broader than needed. For workloads, write your own narrow policies. **IAM Access Analyzer** can suggest a narrow policy from what a role actually used.

Some resources also have **resource-based policies** (an S3 bucket policy, a KMS key policy) that say who may use them, including other accounts.

## 3. Azure RBAC role assignments

In Azure you **assign a role to an identity at a scope**:

```bash
# Give the group "itlpay-devs" read-only access to one resource group
az role assignment create \
  --assignee-object-id "$(az ad group show -g itlpay-devs --query id -o tsv)" \
  --assignee-principal-type Group \
  --role "Reader" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-itlpay-staging"
```

Roles you'll meet constantly:

| Role | Can do |
| --- | --- |
| **Owner** | Everything, including granting access to others. Give it to very few |
| **Contributor** | Create and manage everything, but not grant access |
| **Reader** | View everything, change nothing |
| Service roles, e.g. **Storage Blob Data Reader**, **AcrPull**, **Key Vault Secrets User** | Exactly one job on one kind of resource |

Assignments are **inherited downwards**: Reader on a subscription means Reader on every resource group and resource in it. So assign at the **narrowest scope** that works. Like AWS, Azure supports **deny assignments** and **Azure Policy** to set limits nobody below can override.

Note the difference between **control plane** and **data plane** roles: *Contributor* on a storage account lets you change its settings, but reading the files inside needs a data role such as *Storage Blob Data Reader*. The same split exists for Key Vault secrets. Expect it to surprise you once.

## 4. Workloads without stored keys

The most important rule in this topic: **programs running in the cloud should never hold long-lived keys.** Give the workload an identity instead, and the cloud hands it short-lived credentials automatically.

**AWS: an IAM role for an EC2 instance**

1. Create a role whose **trust policy** says "the EC2 service may assume this role".
2. Attach a narrow permissions policy (like the S3 one above).
3. Attach the role to the instance as an **instance profile**.
4. On the instance, the AWS CLI and SDKs (boto3) find temporary credentials automatically, via the instance metadata service (`169.254.169.254`, topic 2.2). They rotate on their own.

Require **IMDSv2** (token-based metadata) on every instance; it blocks a class of attacks where a bug in the app is used to steal the role's credentials.

**Azure: a managed identity for a VM**

1. Turn on the VM's **system-assigned managed identity** (or attach a user-assigned one).
2. Give that identity a role at a narrow scope, for example *Storage Blob Data Reader* on one storage account.
3. On the VM, the Azure CLI (`az login --identity`) and SDKs (`DefaultAzureCredential`, topic 3.4) get tokens automatically.

The same idea covers containers (ECS task roles, EKS Pod Identity; AKS Workload Identity), functions (Lambda execution roles; Function App managed identities) and pipelines: **GitHub Actions can sign in to both clouds with OIDC federation**, trading a short-lived GitHub token for cloud credentials, so no cloud secret is stored in GitHub at all (Phase 2).

## 5. People: MFA, groups and temporary admin

- **MFA for everyone**, enforced. On AWS through IAM Identity Center; on Azure through Conditional Access or security defaults.
- **Grant to groups, not individuals.** When Ada joins the payments team, add her to `payments-devs`; when she leaves, remove her once.
- **Separate everyday and admin access.** Engineers read by default and step up to admin only when needed: AWS IAM Identity Center permission sets with short session lengths; Azure **Privileged Identity Management (PIM)** for time-limited, approved role activation (needs Entra ID P2 licences).
- **Review access regularly**, and remove what's unused. Both clouds show last-used information (IAM's *Last accessed* tab; Entra sign-in logs).
- **No shared accounts.** Every action must trace back to one person.

## 6. "Access denied": how to investigate

1. **Read the full error.** AWS errors name the identity (the ARN), the action and often the resource: `User: arn:aws:sts::123456789012:assumed-role/itlpay-app/i-0abc is not authorized to perform: s3:PutObject on resource: arn:aws:s3:::itlpay-statements/2026/11/06.pdf`. Azure errors name the action and scope: `does not have authorization to perform action 'Microsoft.Storage/storageAccounts/listKeys/action' over scope '/subscriptions/.../resourceGroups/rg-itlpay'`.
2. **Confirm who you really are.** `aws sts get-caller-identity`; `az account show` and `az ad signed-in-user show`. Many "access denied" cases are the wrong profile, account or subscription.
3. **Find the missing permission**, and add **only that**, at the narrowest scope. Don't jump to Administrator, Owner or `*`.
4. **Check for a deny** (an SCP, an Azure Policy, a bucket policy) if the permission seems present.
5. **Check the logs**: CloudTrail event history shows `AccessDenied` events with details; the Azure Activity Log shows failed operations. The **IAM Policy Simulator** and Azure's **Check access** blade test what an identity can do.
6. **Remember propagation**: new permissions can take a few minutes (often longer for Azure role assignments) to take effect.

## Practice

Use the accounts and budgets from topic 6.1. Delete everything at the end.

1. **AWS:** create a group `learners-readonly` with the `ReadOnlyAccess` managed policy and a test user in it (with MFA). Sign in as the user and show you can list S3 buckets but can't create one. Read the error in full.
2. **Azure:** create a resource group `rg-lab-6-2`, then assign **Reader** on it to a second user in your tenant (or to yourself in a test). Show what Reader can and can't do in that group.
3. **AWS:** write the narrow S3 read policy from section 2 for a test bucket, attach it to a role trusted by EC2, and (in topic 6.5) use it from a VM with no keys.
4. **Azure:** create a storage account, and give a managed identity *Storage Blob Data Reader* on it only (you'll use it from a VM in topic 6.5).
5. Find your own actions from today in **CloudTrail event history** and the **Azure Activity Log**. Write down one event from each: who, what, when, from which IP address.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [AWS IAM Core Concepts You NEED to Know](https://www.youtube.com/watch?v=_ZCTvmaPgao) · Be A Better Dev · 22 min. AWS IAM users, groups, roles and policies.
- [AZ-900 Episode 28 | Azure Role-based Access Control (RBAC)](https://www.youtube.com/watch?v=4v7ffXxOnwU) · Adam Marczak - Azure for Everyone · 14 min. Azure role-based access control (AZ-900).
- [Microsoft Entra ID Beginner's Tutorial (Azure Active Directory)](https://www.youtube.com/watch?v=0qZzcK1mHwA) · Microsoft Mechanics · 13 min. Microsoft Entra ID for beginners, from Microsoft.

## Further learning (free)

Free, self-paced courses from the two clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn and a free AWS Builder ID for AWS Skill Builder to track your progress.

**Azure (Microsoft Learn):**

- [Describe Azure identity, access, and security](https://learn.microsoft.com/training/modules/describe-azure-identity-access-security/)
- [Secure your Azure resources with Azure role-based access control (Azure RBAC)](https://learn.microsoft.com/training/modules/secure-azure-resources-with-rbac/)
- [Guided Project: Set up new employee access (Entra ID and RBAC)](https://learn.microsoft.com/training/modules/guided-project-new-employee-access/)

**AWS (AWS Skill Builder):**

- [Introduction to AWS Identity and Access Management (IAM)](https://skillbuilder.aws/learn/XFPX3M7HAQ/introduction-to-aws-identity-and-access-management-iam/DQJ3N5QRRU)
- [AWS Identity and Access Management (IAM) - Troubleshooting](https://skillbuilder.aws/learn/ESGHTNXQFZ/aws-identity-and-access-management-iam--troubleshooting/3MQXNQUUQ4)

