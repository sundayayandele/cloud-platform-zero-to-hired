## What you will be able to do

- Explain the shared responsibility model, and which compliance work is yours on AWS, Azure and Google Cloud.
- Configure and query audit logs: AWS CloudTrail, the Azure Activity Log, Google Cloud Audit Logs, and Kubernetes audit logs.
- Map the main data protection laws that apply to African fintechs (Nigeria's NDPA, South Africa's POPIA, Kenya's Data Protection Act, the EU's GDPR) and PCI DSS to concrete technical controls.
- Choose regions for data residency with the clouds' African footprint, and enforce the choice as code.
- Collect compliance evidence continuously instead of in a panic before an audit.

## Why this matters at work

A payments company can't operate without passing audits: PCI DSS for card data, central bank requirements, data protection regulators, and the due-diligence questionnaires every bank customer sends. Engineers are asked "who accessed this customer's data last month?", "where is this data stored?", "show us the evidence that only approved people can change production". Teams that built audit logging, residency rules and evidence into the platform answer in minutes; teams that didn't spend weeks. Engineers who understand both the laws and the controls are rare and in demand, especially in African fintech and in international companies serving African markets.

## 1. Shared responsibility

The cloud provider secures the cloud; you secure what you put in it.

| | Provider | You |
| --- | --- | --- |
| Data centres, hardware, the hypervisor | ✔ | |
| Managed service internals (RDS, AKS control plane, Cloud SQL) | ✔ | |
| Identity and access: who can do what | | ✔ |
| Network rules, encryption settings, logging turned on | | ✔ |
| Your application, images and data | | ✔ |
| Compliance of **your** system | Provides reports for their part (AWS Artifact, Microsoft Service Trust Portal, Google Compliance Reports Manager) | ✔ |

A provider's PCI DSS or ISO 27001 certificate covers their infrastructure, not your configuration on top of it. Auditors ask for both.

## 2. Audit logs: who did what, when

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Control-plane actions (create, change, delete) | **CloudTrail** management events: 90 days of event history by default; a **trail** to S3 to keep longer | **Activity Log**: 90 days; export with a diagnostic setting to Log Analytics or Storage | **Cloud Audit Logs** Admin Activity: always on, kept 400 days |
| Data access (reading objects, secrets) | CloudTrail **data events** (S3, Lambda, DynamoDB...), opt-in and charged | Resource logs per service (Key Vault, Storage), opt-in | **Data Access** logs, mostly off by default |
| Across the organisation | An **organization trail** into a separate log-archive account | Diagnostic settings at management-group or subscription scope, by Azure Policy | **Aggregated sinks** at organisation or folder level |
| Tamper resistance | S3 Object Lock, log file validation | Immutable storage | Locked log buckets |

Two rules: send audit logs to a **separate account, subscription or project** that production administrators can't change (an attacker's first step is often deleting the evidence; the AWS SCP from topic 14.3 forbids stopping CloudTrail), and **turn on data access logging** for your most sensitive data, such as the secret store (topic 10.2).

## 3. Kubernetes audit logs

The API server can record every request: who, what, which object, when, and the result. An **audit policy** decides how much. The lab's (`labs/security/audit/audit-policy.yaml`):

```yaml
rules:
  - level: Metadata            # Secrets: who, which one, when, the result, NEVER the contents
    resources: [{ group: "", resources: [secrets, serviceaccounts/token] }]
  - level: RequestResponse     # changes to RBAC: full detail for investigations
    verbs: [create, update, patch, delete]
    resources: [{ group: rbac.authorization.k8s.io, resources: [roles, rolebindings, clusterroles, clusterrolebindings] }]
  - level: None                # noise: events, endpoints, leases, health checks
    ...
  - level: Metadata            # everything else, without bodies
```

Logging a Secret at `Request` or `RequestResponse` level writes the secret into your logs, where far more people can read it. That's the most common audit-policy mistake.

`kind-audit-test.sh`, run by the course's CI, creates a kind cluster with this policy, has the ITL Pay service account read the database Secret and another service account try. It then reads the audit log and checks three things: both requests are recorded (200 and 403, with the impersonated identity), Secret reads are logged at `Metadata` level, and **the Secret's value appears nowhere in the log**.

On the managed services, turn on the control plane's audit logs: EKS control plane logging (`audit` to CloudWatch Logs), AKS diagnostic settings (`kube-audit-admin`), and GKE Cloud Audit Logs (on by default for Admin Activity).

## 4. The laws, and what they mean for engineers

This is an engineer's summary, not legal advice: your company's lawyers and data protection officer decide what applies.

| | Nigeria: **Data Protection Act 2023** (NDPA) | South Africa: **POPIA** | Kenya: **Data Protection Act 2019** | EU: **GDPR** |
| --- | --- | --- | --- | --- |
| Regulator | Nigeria Data Protection Commission (NDPC); its General Application and Implementation Directive (GAID, 2025) adds detail | Information Regulator | Office of the Data Protection Commissioner (ODPC) | National data protection authorities |
| Breach notification | To the NDPC within 72 hours | To the Regulator and the people affected, as soon as reasonably possible | To the ODPC within 72 hours | Within 72 hours |
| Sending data abroad | Allowed with an adequate level of protection or safeguards | Allowed with adequate protection, consent or contracts | Allowed with safeguards; some data must stay in Kenya by regulation | Allowed to "adequate" countries or with safeguards |

What they mean in your systems:

| Requirement | Control you build |
| --- | --- |
| Know what personal data you hold and where | A data inventory; tags on stores (`data-classification=personal`); the catalog (topic 14.1) |
| Only the people who need it can see it | Least-privilege IAM and RBAC; per-secret access (topic 10.2); access reviews |
| Show who accessed it | Data access audit logs (sections 2–3), kept for the required period |
| Protect it | Encryption at rest and in transit; no personal data in logs (topic 11.2) |
| Detect and report breaches quickly | Alerts (Module 11), runtime detection (topic 15.1), an incident process with the regulator step (topic 13.2) |
| Delete it when it's no longer needed | Retention rules on logs, backups and databases (topic 13.4) |
| Keep it in agreed places | Residency rules enforced as code (section 5) |

**PCI DSS 4.0** (fully in force since March 2025) applies wherever card numbers are stored, processed or transmitted. Its single most useful engineering principle: **shrink the scope**. Use a payment provider's tokens instead of card numbers, so most of your platform never touches card data and stays out of the audit.

**Sector rules** add to this: central banks often require approval for outsourcing to the cloud, and may require certain data or processing in-country (the Central Bank of Nigeria and the South African Reserve Bank both publish cloud and outsourcing guidance). Check them with your compliance team for every new market.

## 5. Data residency in practice

The three clouds' footprint in Africa, today:

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Full regions in Africa | **af-south-1** (Cape Town) | **South Africa North** (Johannesburg) and **South Africa West** (Cape Town) | **africa-south1** (Johannesburg) |
| Closer to West and East Africa | A **Local Zone in Lagos** (for low latency; check which services and data it holds) | | |

None of the three has a full region in Nigeria or Kenya, so where local hosting is mandatory, companies combine local data centres (colocation or a local cloud provider) with a hyperscaler for everything else. Check each provider's current region list: new regions are announced regularly.

The course enforces residency **as code**, at two levels:

- **Organisation guardrails** (topic 14.3): the AWS SCP, Azure Policy and Google organisation policy in `labs/platform/policies/cloud/` refuse resources outside the agreed regions.
- **A policy on the Terraform itself** (`labs/security/residency/residency.rego`), so a wrong region fails on the pull request, before any plan: every `region` or `location` variable default, and every literal region in a provider or resource, must be one of South Africa's regions or the agreed EU disaster recovery region.

```bash
conftest verify -p labs/security/residency                                   # the policy's own tests
conftest test --parser hcl2 -p labs/security/residency labs/terraform-network/envs/*/main.tf
```

The course's CI runs both: Module 7's environments (af-south-1, southafricanorth, africa-south1) pass; the tests prove `us-east-1` and a literal `eastus` would fail.

## 6. Continuous evidence

Auditors want evidence that controls work all the time, not on audit day. Build it from what you already have:

| Evidence | Where it comes from |
| --- | --- |
| Every infrastructure change was reviewed and approved | Pull requests, plan comments and environment approvals (Modules 8 and 12) |
| Policies are enforced | Policy tests in CI; admission reports; organisation policy compliance (topic 14.3) |
| Access is controlled and reviewed | IAM and RBAC as code; audit logs; periodic access reviews |
| Backups work | Timed restore tests (topic 13.4) |
| Incidents are handled | Post-mortems and their actions (topic 13.2) |
| The cloud configuration meets a benchmark | AWS Audit Manager and Security Hub; Microsoft Defender for Cloud regulatory compliance and Purview Compliance Manager; Google Security Command Center compliance and Assured Workloads |

## Practice

1. Run `kind-audit-test.sh`, then change the Secret rule to `level: RequestResponse` and run it again. What does the test catch, and why does it matter?
2. In one cloud, send audit logs to a separate account, subscription or project with a retention lock. Make a change in production and find it in the archive.
3. Turn on data access logging for your secret store (CloudTrail data events, Key Vault diagnostic logs, or Secret Manager Data Access logs). Read a secret and find the entry.
4. Write a one-page data map for ITL Pay: what personal data it holds, where (which cloud, region, service), who can access it, how long it's kept, and which law applies to each customer group.
5. Add a rule to `residency.rego` that also checks Google Cloud storage bucket `location` values, with tests, and run it against your Capstone 2 Terraform.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [AWS Compliance - The Shared Responsibility Model](https://www.youtube.com/watch?v=U632-ND7dKQ) · Amazon Web Services · 3 min. AWS on the shared responsibility model.
- [AWS CloudTrail Basics | Step-by-Step Tutorial for Beginners](https://www.youtube.com/watch?v=CXbdsp9ThvM) · Tiny Technical Tutorials · 10 min. AWS CloudTrail basics, step by step.
- [Data Sovereignty vs Data Residency Explained: The Compliance Mistake That Costs Millions](https://www.youtube.com/watch?v=gkra2jltpkA) · StoneFly, Inc. · 6 min. Data sovereignty and data residency, and how they differ.
- [What is PCI DSS? | A Brief Summary of the Standard](https://www.youtube.com/watch?v=szVmMxWORBc) · GRC Solutions · 5 min. A short summary of PCI DSS.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Evaluate regulatory compliance in Defender for Cloud](https://learn.microsoft.com/training/modules/evaluate-regulatory-compliance/)
- [Guided project: monitor Azure with Service Health and Activity Log alerts](https://learn.microsoft.com/training/modules/guided-project-monitor-service-health-activity-alerts/)

**AWS (AWS Skill Builder):**

- [AWS CloudTrail Getting Started](https://skillbuilder.aws/learn/6E2F4RVDA2/aws-cloudtrail-getting-started/N24M82M8YF)
- [Deep Dive on AWS Organizations Policies](https://skillbuilder.aws/learn/SG8M56GKXM/deep-dive-on-aws-organizations-policies/GGZRYCVY3A)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Logging and Monitoring in Google Cloud (including Cloud Audit Logs)](https://www.skills.google/course_templates/99)

