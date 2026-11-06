## What you will be able to do

- Explain what "the cloud" is, the service models (IaaS, PaaS, SaaS, serverless) and the shared responsibility model.
- Explain regions, availability zones and edge locations, and choose a region for a Nigerian workload, including the regions in Africa.
- Explain how each cloud organises things: AWS accounts and Organizations; Azure tenants, management groups, subscriptions and resource groups.
- Open an AWS account and an Azure account safely: protect the root/owner sign-in, turn on MFA, and stop using it day to day.
- Set billing guardrails on both clouds **before** building anything: budgets with alerts, free-tier limits, and a teardown habit.
- Read how each cloud charges, and recognise the common causes of surprise bills.
- Do the same on **Google Cloud**, and compare the three clouds.

## Why this matters at work

Every cloud job starts here: the account structure decides who can do what and who pays; the region decides latency, cost and which data-protection rules apply; the guardrails decide whether a mistake costs ₦5,000 or ₦5,000,000. Surprise bills are the most common way learners (and companies) get hurt in the cloud, and leaked credentials on an account with no budget alerts can run up thousands of dollars of crypto-mining in a weekend. Employers expect you to set these protections up without being asked.

## 1. What the cloud is

The cloud is computing you **rent by the second or the hour** from a provider's data centres, created and removed through an API (a web console, a CLI or code), instead of buying servers. You get:

- **speed:** a server in a minute, not a purchase order in a month;
- **elasticity:** add capacity for a busy end of month, remove it after;
- **managed services:** databases, queues and load balancers that the provider patches and runs;
- **global reach:** data centres on every continent.

You pay for what you use, which is great when you switch things off, and expensive when you forget.

## 2. Service models and shared responsibility

| Model | You manage | The provider manages | AWS examples | Azure examples |
| --- | --- | --- | --- | --- |
| **IaaS** (infrastructure) | The OS, patches, runtime, app, data | Hardware, network, virtualisation | EC2, VPC, EBS | Virtual Machines, VNet, Managed Disks |
| **PaaS** (platform) | The app and data, settings | Also the OS and runtime | RDS, Elastic Beanstalk, App Runner | Azure Database for PostgreSQL, App Service, Container Apps |
| **Serverless** | Your code and its settings | Everything else; billed per request | Lambda, Fargate, DynamoDB | Functions, Container Apps (consumption), Cosmos DB serverless |
| **SaaS** (software) | Your data and users | The whole application | Amazon WorkMail | Microsoft 365 |

Both clouds publish a **shared responsibility model**: the provider secures the **cloud itself** (buildings, hardware, the hypervisor); you secure what you put **in** it (who has access, network rules, encryption settings, patching your VMs, your data). Nearly every cloud breach in the news is on the customer's side: a public storage bucket, a leaked key, an open database port. That side is your job.

## 3. Regions, availability zones and the edge

- A **region** is a geographic area with several data centres, such as AWS `af-south-1` (Cape Town) or Azure **South Africa North** (Johannesburg). Data stays in the region you choose unless you copy it elsewhere.
- An **availability zone (AZ)** is one or more separate data centres inside a region, with independent power and networking. Spreading servers across two or three AZs means one building failing doesn't take you down. AWS regions have at least three AZs; many Azure regions have three **availability zones** too (check the region before relying on them).
- **Edge locations** (AWS CloudFront, Azure Front Door) cache content close to users, including in Lagos, Nairobi and other African cities.

Choosing a region for ITL Pay:

| Factor | Questions to ask |
| --- | --- |
| **Latency** | How far are users? Lagos to South Africa is typically 60–80 ms; to Europe about 80–120 ms. Measure it (topic 2.4's `curl` timing). |
| **Law and compliance** | Does the Nigeria Data Protection Act, the Central Bank, or a customer contract limit where personal or financial data may go? Record the decision in an ADR (topic 4.3). |
| **Services and features** | Newer services and larger machine types often reach big regions (Ireland, Frankfurt, US East) first. Check before you design. |
| **Price** | The same service can cost 10–30% more in some regions. |
| **Disaster recovery** | Which second region holds backups? |

In Africa today: AWS has **Cape Town (`af-south-1`)**, which is an **opt-in region** you must enable in the account before use. Azure has **South Africa North** (Johannesburg) and South Africa West (Cape Town, mostly for backup and recovery). Both providers have announced or are building more African capacity; check the current region lists at the start of each cohort.

For learning, use whichever region your free credits and services work best in; for ITL Pay's capstone, you'll justify a choice.

## 4. How each cloud is organised

**AWS:**

- An **account** is the container for resources and the unit of billing and security isolation. It has a **root user**: the email address that created it, with unlimited power.
- **AWS Organizations** groups many accounts (for example `prod`, `staging`, `security`, `sandbox-ada`) under one management account, with central billing and **Service Control Policies (SCPs)** that limit what any account may do (for example "nothing outside af-south-1 and eu-west-1"). Companies give every team and environment its own account.
- People sign in through **IAM Identity Center** (single sign-on) rather than the root user (topic 6.2).

**Azure:**

- A **tenant** is your organisation's **Microsoft Entra ID** directory: the users, groups and app identities.
- **Management groups** organise subscriptions, with **Azure Policy** applied across them (like SCPs).
- A **subscription** is the unit of billing and a boundary for access, like an AWS account.
- **Resource groups** hold related resources inside a subscription (for example `rg-itlpay-prod`). Deleting a resource group deletes everything in it, which makes clean-up easy and mistakes expensive.

| Idea | AWS | Azure |
| --- | --- | --- |
| Identity directory | IAM (per account), IAM Identity Center (organisation) | Microsoft Entra ID (tenant) |
| Billing and isolation boundary | Account | Subscription |
| Grouping for lifecycle and clean-up | Tags; CloudFormation stacks | Resource groups (and tags) |
| Organisation-wide guardrails | Organizations + SCPs | Management groups + Azure Policy |
| The all-powerful sign-in | Root user | Global Administrator / subscription Owner |

## 5. Opening accounts safely

Use a **personal email you'll keep**, and a password manager. Free-tier and credit offers change; read the current terms on the sign-up page.

**Azure:**

- If you're a student with a school email, use **Azure for Students**: free credit, **no card needed**, renewable while you're a student.
- Otherwise, the **Azure free account** gives a credit for the first 30 days and a set of services free for 12 months, plus "always free" services. A card is used for identity checks.

**AWS:**

- New accounts choose a **free plan** (free credits for a limited period; resources are stopped if credits run out) or a paid plan. A card is needed to sign up. Choose the free plan while learning.

Straight after sign-up, on **both** clouds:

1. **Turn on MFA** for the root user (AWS) and your account (Azure), with an authenticator app. Store recovery codes safely.
2. **Stop using the root/owner sign-in day to day.** On AWS, create an IAM Identity Center user (or an IAM admin user while learning) with MFA and use that; lock the root password away. On Azure, your account is the tenant's Global Administrator; create a separate everyday user with only the roles you need (topic 6.2).
3. **Never create access keys for the AWS root user.**
4. **Set the budget alerts in section 6 now**, before creating anything else.

If you can't get a card or a student email, you can still do most of Module 6 with the **AWS and Azure command-line tools against local emulators** (LocalStack, Azurite) and in the free **sandbox environments** some Microsoft Learn and AWS Skill Builder modules provide; your instructor can also arrange shared lab access. Tell your mentor or post in *Questions and help*.

## 6. Billing guardrails, on both clouds, today

**AWS:**

```bash
# In the console: Billing and Cost Management → Budgets → Create budget
#   Template: "Zero spend budget" (alerts on the first cent) or a monthly cost budget of USD 5
#   Alert at 50%, 80% and 100% of actual, and 100% of forecast, to your email
# Also: Billing → Cost Anomaly Detection → create a monitor with email alerts
# Also: Billing preferences → turn on Free Tier usage alerts
```

**Azure:**

```bash
# In the portal: Cost Management + Billing → Budgets → Add
#   Scope: your subscription. Amount: USD 5 (or the equivalent) per month
#   Alerts at 50%, 80% and 100% actual, and 100% forecasted, to your email
# Azure for Students and free-credit subscriptions also stop resources when credit runs out,
# but don't rely on that alone.
```

A budget **alerts**; it doesn't stop spending. So also build habits:

- **Tag everything** you create with `owner` and `purpose` (for example `owner=ada`, `purpose=topic-6.5`), so you can find and delete it.
- **Tear down at the end of every session.** On Azure, put each lab in its own resource group and delete the group (`az group delete -n rg-lab-6-5`). On AWS, delete in reverse order of creation; Phase 2's Terraform makes this one command.
- **Check the bill weekly**: AWS Cost Explorer, Azure Cost analysis. Look at the cost by service.

## 7. How the clouds charge, and the usual surprises

You pay for **compute** (per second or hour while running), **storage** (per GB per month, even when nothing runs), **requests** (per million for some services) and **data transfer** (data **out** to the internet, and sometimes between zones and regions).

The usual surprise items for learners:

| Item | Why it costs | Avoid it by |
| --- | --- | --- |
| A **NAT gateway** (topic 2.5) | Charged per hour and per GB on both clouds, even idle | Delete it after the lab; use one only when you need private outbound access |
| **Load balancers** | Charged per hour while they exist | Delete after the lab |
| **Public IPv4 addresses** | AWS charges for every public IPv4 address per hour, attached or not; Azure charges for public IPs too | Release them; use Session Manager/Bastion instead of public SSH |
| **Managed databases** left running | Charged per hour | Stop or delete; use the smallest size |
| **Disks and snapshots** left after deleting a VM | Charged per GB-month | Delete the disks; on Azure, delete the resource group |
| VMs that are **stopped** but not deallocated (Azure) | A stopped-but-allocated Azure VM still bills for compute | Use **Stop (deallocate)** in the portal or `az vm deallocate` |
| A **leaked access key** | Attackers start large machines to mine cryptocurrency | MFA, no root keys, budgets, never commit keys (topic 4.1) |

The **pricing calculators** (AWS Pricing Calculator, Azure Pricing Calculator) estimate a design's monthly cost before you build it. Capstone 1 asks you for an estimate on both clouds.

## Google Cloud: projects, regions and budgets

Google Cloud organises things differently from the other two, and the difference matters for clean-up and billing.

- A **project** is the main container: every resource lives in exactly one project, and the project is linked to a **billing account** that pays for it. A project has a name, a globally unique **project ID** (for example `itlpay-dev-ada-4821`) and a number. Think of it as AWS's account and Azure's subscription and resource group in one.
- **Folders** group projects (for example `prod`, `nonprod`), and the **organization** sits on top. An organization exists only when you sign up with a company domain (Google Workspace or Cloud Identity); an individual learner has projects without an organization, which is fine for this course.
- **Organization Policy** constraints set limits for everything below (for example "only these regions", "no service account keys"), like SCPs and Azure Policy.
- **Labels** (lowercase keys and values, such as `owner=ada`, `purpose=topic-6-1`) do the job of tags.

| Idea | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Billing and isolation boundary | Account | Subscription | Project, linked to a billing account |
| Grouping for clean-up | Tags; CloudFormation stacks | Resource groups | **The project itself**: deleting it shuts down everything inside |
| Organisation-wide guardrails | Organizations + SCPs | Management groups + Azure Policy | Organization + folders + Organization Policy |
| The all-powerful sign-in | Root user | Global Administrator / Owner | The account that created the project (Owner) |

**Regions:** Google Cloud has a region in **Johannesburg, `africa-south1`**, with three zones. Like the others, check that the services you need are offered there before you design around it.

**Opening an account safely:**

1. Sign up at cloud.google.com with a Google account you'll keep. New customers get a **free trial credit** for a limited period, and the **Always Free** tier includes small amounts of some services (for example one small `e2-micro` VM in certain US regions). A card is used for identity checks; check the current terms before you start.
2. Turn on **2-Step Verification** for the Google account.
3. Create a project for the course (for example `cpe-lab-ada`), and later one project per environment.
4. Don't use the basic **Owner** and **Editor** roles for daily work once you know IAM (topic 6.2).

**Budgets on Google Cloud** (do it now, like the other two):

```text
Console: Billing → Budgets & alerts → Create budget
  Scope: your billing account or the course project. Amount: USD 5 per month.
  Alert thresholds: 50%, 90% and 100% of actual spend, and 100% of forecast; email to billing admins and users.
```

Budgets alert, they don't stop spending; advanced teams connect budget alerts to a Pub/Sub topic and a function that disables billing on a project, which you'll see in Phase 3.

**Clean-up is easiest of all:** `gcloud projects delete cpe-lab-ada` shuts down every resource in the project (it can be restored for about 30 days). Put each big lab in its own project.

Surprise costs to watch on Google Cloud: **Cloud NAT** and **load balancer forwarding rules** (hourly), **external IPv4 addresses** on VMs, **Cloud SQL** instances left running, and **disks and snapshots** left after deleting a VM.

## Practice

1. Open (or prepare) an Azure account and an AWS account. Turn on MFA on both. Record in your learning log which offer you used and its current limits (credit amount, how long it lasts).
2. Set the budgets and alerts from section 6 on both clouds, and take a screenshot of each.
3. On AWS, create an everyday admin user (IAM Identity Center, or IAM with MFA while learning), sign out of root, and sign in as that user. On Azure, look at **Microsoft Entra ID → Users** and **Subscriptions → Access control (IAM)** to see who has which role.
4. Use both pricing calculators to estimate one month of: one small Linux VM running 24/7, a 20 GB disk, a small managed PostgreSQL, and 10 GB of data out to the internet, in Cape Town / South Africa North and in an EU region. Compare.
5. Write an ADR (topic 4.3) choosing a region for ITL Pay's production, with at least two options, citing latency you measured and any data-protection points.
6. **Google Cloud:** create a project for the course, turn on 2-Step Verification, set a USD 5 budget with alerts, and add Google Cloud to your pricing comparison in exercise 4. Use `africa-south1` (Johannesburg) as the African region.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [AZ-900 Episode 7 | Geographies, Regions & Availability Zones | Microsoft Azure Fundamentals Course](https://www.youtube.com/watch?v=C-nNw1mGwzE) · Adam Marczak - Azure for Everyone · 15 min. Azure geographies, regions and availability zones (AZ-900).
- [AWS Global Infrastructure Overview - Regions, Availability Zones, Edge Locations and more](https://www.youtube.com/watch?v=0hlZvybbaGk) · Digital Cloud Training · 6 min. AWS regions, availability zones and edge locations.
- [AWS vs Azure vs GCP | Which one should you learn?](https://www.youtube.com/watch?v=ECnqartfjIM) · Tech With Lucy · 7 min. AWS, Azure and GCP compared: which to learn first.
- [How to Create Organization, Folders, and Projects in Google Cloud | GCP Resource Hierarchy](https://www.youtube.com/watch?v=x2z11Z-HsXU) · TechTrapture · 21 min. Google Cloud's organization, folders and projects, step by step.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Introduction to Cloud Infrastructure: Describe cloud concepts (learning path, AZ-900)](https://learn.microsoft.com/training/paths/microsoft-azure-fundamentals-describe-cloud-concepts/)
- [Introduction to Cloud Infrastructure: Describe Azure architecture and services (learning path, AZ-900)](https://learn.microsoft.com/training/paths/azure-fundamentals-describe-azure-architecture-services/)
- [Guided project: Set up cost guardrails in Azure](https://learn.microsoft.com/training/modules/guided-project-cost-guardrails/)
- [Introduction to analyzing costs and creating budgets with Microsoft Cost Management](https://learn.microsoft.com/training/modules/analyze-costs-create-budgets-azure-cost-management/)

**AWS (AWS Skill Builder):**

- [AWS Cloud Practitioner Essentials (Cloud Practitioner exam prep)](https://skillbuilder.aws/learn/94T2BEN85A/aws-cloud-practitioner-essentials/8D79F3AVR7)
- [AWS Cloud Quest: Cloud Practitioner (hands-on game)](https://skillbuilder.aws/learn/FU5WCYVGKY/aws-cloud-quest-cloud-practitioner/JF9TKU68GT)
- [AWS Budgets Getting Started](https://skillbuilder.aws/learn/778TKSGH8Z/aws-budgets-getting-started/XAZ7B7K32D)
- [AWS Billing and Cost Management](https://skillbuilder.aws/learn/J59SS92GUN/aws-billing-and-cost-management/25JXE6WYAY)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Google Cloud Fundamentals: Core Infrastructure](https://www.skills.google/course_templates/60)
- [Google Cloud Computing Foundations: Cloud Computing Fundamentals](https://www.skills.google/course_templates/153)
- [Cloud Digital Leader Certification (learning path)](https://www.skills.google/paths/9)
- [Optimizing Your Google Cloud Costs](https://www.skills.google/course_templates/56)

