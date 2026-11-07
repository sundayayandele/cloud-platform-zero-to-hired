## What you will be able to do

- Explain policy as code, and where policies run: in pull requests, in pipelines, at Kubernetes admission, and in the cloud's organisation.
- Write Kubernetes admission policies with Kyverno's CEL-based `ValidatingPolicy`, and know the built-in `ValidatingAdmissionPolicy` and OPA Gatekeeper.
- Unit-test policies with the Kyverno CLI, and check Terraform with OPA's Rego and Conftest.
- Set organisation guardrails with AWS service control policies, Azure Policy and Google Cloud organisation policies.
- Roll policies out safely (audit, then enforce), and handle exceptions without weakening them.

## Why this matters at work

A platform gives teams speed; **policy as code** keeps that speed safe. Instead of a security review that finds problems weeks later, rules are code: versioned, reviewed, tested, and checked automatically on every change. "No database open to the internet", "only images from our registries", "every resource tagged with its owner", "data stays in South Africa": each becomes a test that fails fast with a clear message. Banks and regulated companies rely on it for evidence ("show us every control and when it changed"), and Kyverno, OPA and the clouds' policy services are standard platform and security engineering skills.

## 1. Where policies run

```text
author ──► pull request ──► pipeline ──► Kubernetes admission ──► running cluster ──► cloud organisation
           Conftest/checkov   kyverno test   Kyverno, VAP,         background scans    SCPs, Azure Policy,
           on Terraform/YAML  terraform plan Gatekeeper            and reports         GCP org policies
```

The earlier a policy runs, the cheaper the fix: a failing check on a pull request costs a minute; a refused deployment costs an hour; an audit finding costs a week. But only the later layers are **guarantees**: someone can skip CI, nobody can skip admission or an organisation policy. Use both.

## 2. Kubernetes admission with Kyverno

**Kyverno** is a CNCF policy engine for Kubernetes. Since version 1.15 its main policy types use **CEL** (the Common Expression Language that Kubernetes itself uses), and **version 1.19 deprecated the older `ClusterPolicy` and `Policy` types**: many tutorials still show them, but new policies should use `ValidatingPolicy` (and `MutatingPolicy`, `GeneratingPolicy`, `ImageValidatingPolicy`). Use at least **1.19.2**, which fixed 24 security advisories, nine of them critical.

The lab's policy against unversioned images (`labs/platform/policies/kyverno/disallow-latest-tag.yaml`):

```yaml
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationActions: [Deny]
  autogen:
    podControllers:
      controllers: [deployments, statefulsets, jobs]   # also check Deployments etc., so the error comes at apply time
  matchConstraints:
    resourceRules:
      - { apiGroups: [""], apiVersions: [v1], operations: [CREATE, UPDATE], resources: [pods] }
  validations:
    - message: "Images must have a version tag or a digest, never :latest or no tag"
      expression: >-
        object.spec.containers.all(c,
          c.image.contains('@sha256:') ||
          (c.image.split('/')[size(c.image.split('/')) - 1].contains(':') && !c.image.endsWith(':latest')))
```

The lab has four policies: versioned images, resources (a memory limit and a CPU request), a `platform.itlearning.tech/team` label on Deployments, and approved registries (GHCR, ECR, ACR, Artifact Registry) in **Audit** mode.

**`autogen.podControllers`** matters: without it, a Deployment with a `:latest` image is accepted, and the error only appears when its ReplicaSet tries to create pods, in an event nobody reads.

**Alternatives you'll meet:**

| | Kyverno | Kubernetes ValidatingAdmissionPolicy | OPA Gatekeeper |
| --- | --- | --- | --- |
| Language | CEL (and older YAML patterns) | CEL | Rego |
| Built in | No (an add-on) | Yes, stable since Kubernetes 1.30 | No (an add-on) |
| Extras | Mutation, generation, image signature checks, reports, a CLI for tests | Validation only | Mutation; constraint templates; audit |

Kyverno can also turn a `ValidatingPolicy` into a native `ValidatingAdmissionPolicy` (`autogen.validatingAdmissionPolicy`), so the API server evaluates it directly.

## 3. Testing policies

Policies are code, so they get tests. `tests/kyverno-test.yaml` runs every policy against good and bad examples, offline:

```bash
kyverno test labs/platform/policies/kyverno/tests
```

```yaml
results:
  - { isValidatingPolicy: true, kind: Pod, policy: disallow-latest-tag, resources: [latest-pod, untagged-pod], result: fail }
  - { isValidatingPolicy: true, kind: Pod, policy: disallow-latest-tag, resources: [good-pod, digest-pod, no-limits-pod], result: pass }
```

Then `kind-kyverno-test.sh` installs Kyverno on kind and asks the real API server, with server-side dry runs (admission runs; nothing is created): an image tagged `:latest`, an untagged image, a pod with no limits and an unlabelled Deployment are all **refused**, with the policy's message; versioned, labelled, resourced objects are **allowed**; and a Docker Hub image is allowed because the registry policy only audits. The course's CI runs both on every push.

## 4. Terraform with OPA and Conftest

**OPA** (Open Policy Agent) is a general policy engine with a language called **Rego**; **Conftest** runs Rego against configuration files: Terraform, Kubernetes YAML, Dockerfiles. The lab's `policies/conftest/terraform.rego` denies SSH or RDP open to the internet on all three clouds, and requires tags on the resources that cost money or matter for security:

```rego
package main

import rego.v1

deny contains msg if {
	some name, firewalls in input.resource.google_compute_firewall
	some f in firewalls
	some cidr in f.source_ranges
	open_to_internet(cidr)
	some allow in f.allow
	some p in allow.ports
	to_number(p) in admin_ports
	msg := sprintf("google_compute_firewall.%s opens port %s to the internet: use IAP (topic 6.5)", [name, p])
}
```

```bash
conftest verify -p labs/platform/policies/conftest                     # the policies' own unit tests
conftest test --parser hcl2 -p labs/platform/policies/conftest labs/terraform-network/modules/*/main.tf
```

Module 7's network modules pass: their only SSH rule allows Google's IAP range (35.235.240.0/20), not the internet. Checking the **plan** (`terraform show -json tfplan | conftest test -`) catches values that only exist after variables are resolved; checking the source catches mistakes earlier. checkov (topic 7.4) covers many common rules out of the box; Rego is for your own.

## 5. Organisation guardrails in the clouds

The last layer works even for someone with full access to an account, because it's set above it:

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Service | **Service control policies** (and resource control policies) in AWS Organizations | **Azure Policy**, assigned to management groups or subscriptions | **Organization Policy Service**, on the organisation, folders or projects |
| Lab example | `aws-scp-allowed-regions.json`: only af-south-1 and eu-west-1; no leaving the organisation or stopping CloudTrail | `azure-policy-allowed-locations.json`: only South Africa North and West Europe | `gcp-org-policy-resource-locations.yaml`: only africa-south1 and europe-west1 |
| Typical rules | Regions, no disabling audit logs, no public S3 buckets, required tags | Allowed locations and SKUs, required tags, deny public IPs, built-in compliance initiatives | Resource locations, no external IPs on VMs, no service account keys, uniform bucket access |

Region rules are how data residency is enforced in practice (topic 15.2). Always leave a **break-glass** path, as the SCP does with a dedicated role, used only in emergencies and alerted on.

## 6. Rolling policies out without breaking everyone

1. **Write the policy and its tests**, review it like code.
2. **Audit first** (`validationActions: [Audit]`, Azure Policy's `audit` effect): see what would be refused today, in policy reports.
3. **Fix or exempt** what's found: help teams fix it, or record an exception.
4. **Enforce**, and announce it. Keep the message clear and actionable: say what to do, not only what's wrong.
5. **Exceptions** are explicit objects (Kyverno's `PolicyException`, Azure Policy exemptions), with an owner, a reason and an expiry date, reviewed regularly. Never weaken the policy itself for one team.

## Practice

1. Run `kyverno test` on the lab's policies, then add a fifth policy: containers must set `readOnlyRootFilesystem: true`. Write the tests first, watch them fail, then write the policy.
2. Run `kind-kyverno-test.sh`. Switch `restrict-registries` to `Deny` and find everything that would break in the course's labs (hint: the database image). Decide what to do about each.
3. Add a Conftest rule that every Azure storage account and S3 bucket blocks public access, with unit tests, and run it against your Capstone 2 Terraform.
4. Create a `PolicyException` that lets one namespace use an untagged image for one week, and show it works only there.
5. In one cloud, apply the lab's region guardrail to a test account, subscription or project, and show a resource in another region is refused. Then show the break-glass path and the alert it raises.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Kubernetes Security Made Easy: Enforce Policies with Kyverno | Complete Tutorial](https://www.youtube.com/watch?v=XQHhUg7GZ0g) · Lens - Kubernetes and LLM observability · 8 min. Enforcing Kubernetes policies with Kyverno.
- [What is Open Policy Agent (OPA)?](https://www.youtube.com/watch?v=ijQdHy4XQCU) · CNCF [Cloud Native Computing Foundation] · 11 min. What Open Policy Agent is, from the CNCF.
- [Enforce Preventive Guardrails Using Service Control Policies | Amazon Web Services](https://www.youtube.com/watch?v=mEO05mmbSms) · Amazon Web Services · 4 min. AWS on preventive guardrails with service control policies.
- [AZ-900 Episode 31 | Azure Policy](https://www.youtube.com/watch?v=9WO4EBgUJXk) · Adam Marczak - Azure for Everyone · 15 min. Azure Policy explained.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Intro to Azure Policy](https://learn.microsoft.com/training/modules/intro-to-azure-policy/)
- [Azure Kubernetes Service governance with Azure Policy](https://learn.microsoft.com/training/modules/aks-governance-azure-policy/)
- [Enforce governance with Azure Policy and resource locks](https://learn.microsoft.com/training/modules/enforce-governance-azure-policy-resource-locks/)

**AWS (AWS Skill Builder):**

- [Deep Dive on AWS Organizations Policies](https://skillbuilder.aws/learn/SG8M56GKXM/deep-dive-on-aws-organizations-policies/GGZRYCVY3A)
- [Deep Dive on Declarative Policies in AWS Organizations](https://skillbuilder.aws/learn/1JC4FTCW9T/deep-dive-on-declarative-policies-in-aws-organizations/DEMM94F869)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Manage Security in Google Cloud (including organisation policies)](https://www.skills.google/course_templates/21)

