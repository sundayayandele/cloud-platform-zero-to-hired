## What you will be able to do

- Explain self-service infrastructure, and the difference between giving teams cloud access and giving them a platform API.
- Choose between shared Terraform modules, Kubernetes-native controllers (Crossplane, ACK, Azure Service Operator, Config Connector) and the clouds' service catalogs.
- Define a platform API with a Crossplane CompositeResourceDefinition, and build it with a Composition and a composition function.
- Offer the same API with different implementations: in the cluster for dev, a managed database on each cloud in production.
- Avoid the common Composition mistakes: unstable generated values, missing permissions, and leaking cloud details into the API.

## Why this matters at work

"I need a database" is one of the most common requests a platform team gets. If every request is a ticket, teams wait days and the infrastructure team becomes a bottleneck. If every team gets full cloud access, you get forty slightly different, unsafe databases and a bill nobody understands. **Self-service infrastructure** gives teams what they ask for, in minutes, built the approved way: encrypted, backed up, tagged, in the right network. Crossplane and Terraform modules are the two most common ways to build it, and both appear in platform engineering job adverts.

## 1. Three ways to offer infrastructure

| | Shared Terraform modules | Kubernetes-native APIs | Cloud service catalogs |
| --- | --- | --- | --- |
| What teams do | Call a module (`source = ".../modules/database"`) in their own Terraform, through the pipeline from topic 8.4 | Apply a short YAML object (`kind: Database`) to the cluster, through GitOps (Module 12) | Pick an approved product in the cloud console |
| Examples | Module 7's network modules; a private module registry (HCP Terraform, GitLab, a Git tag) | **Crossplane**; the clouds' own controllers: **AWS Controllers for Kubernetes (ACK)**, **Azure Service Operator**, **Google Config Connector** | AWS Service Catalog, Azure Deployment Environments, Google Infrastructure Manager blueprints |
| Strengths | Familiar, huge ecosystem, plan before apply | Continuously reconciled (drift fixed automatically), same workflow as apps, one API across clouds | No new tools for teams |
| Weaknesses | Teams still need Terraform skills and state; drift only caught by checks | A control plane to run and secure; debugging through Kubernetes | Tied to one cloud; little automation |

Many platforms use both: Terraform for the foundations (networks, clusters, accounts), and a Kubernetes-native API for what application teams request every week (databases, buckets, queues).

## 2. Crossplane in one picture

```text
team writes:   kind: Database  (size: small)                 ← the platform's API, defined by an XRD
                       │
Crossplane:    Composition "database-in-cluster" or "database-aws-rds"   ← how the platform builds it
                       │  a pipeline of functions renders the resources
               Secret, Service, StatefulSet ...  or  an RDS Instance (via a provider)
                       │
               continuously reconciled: delete something by hand and Crossplane puts it back
```

| Part | What it is |
| --- | --- |
| **CompositeResourceDefinition (XRD)** | Defines the platform's API: a new kind (`Database`), its fields and validation |
| **Composite resource (XR)** | One request: `Database orders` in namespace `team-payments` |
| **Composition** | How to build an XR: a pipeline of **functions** that output the composed resources |
| **Function** | A package that renders resources: go-templating, patch-and-transform, KCL, Python... |
| **Provider** | Talks to a cloud's API: managed resources such as `rds.aws.m.upbound.io/Instance` |

Crossplane 2 (2025) simplified this: composite resources are **namespaced** (teams create them in their own namespace, no separate "claim" objects), and a Composition can create **any Kubernetes resource**, not only cloud resources. Older tutorials with claims and cluster-scoped XRs describe Crossplane 1.

## 3. The lab's Database API

```yaml
# labs/platform/crossplane/xrd.yaml (extract)
apiVersion: apiextensions.crossplane.io/v2
kind: CompositeResourceDefinition
metadata:
  name: databases.platform.itlearning.tech
spec:
  scope: Namespaced
  group: platform.itlearning.tech
  names: { kind: Database, plural: databases }
  versions:
    - name: v1alpha1
      schema:
        openAPIV3Schema:
          properties:
            spec:
              properties:
                size: { type: string, enum: [small, medium], default: small }
                version: { type: string, enum: ["17"], default: "17" }
            status:
              properties:
                endpoint: { type: string }
                secretName: { type: string }
```

A good platform API speaks the team's language (`size: small`), not the cloud's (`instanceClass: db.t4g.micro`, `allocatedStorage: 20`). That keeps teams independent of the cloud, and lets the platform team change how databases are built without changing every request.

What a team writes:

```yaml
apiVersion: platform.itlearning.tech/v1alpha1
kind: Database
metadata:
  name: orders
  namespace: team-payments
spec:
  size: small
```

The in-cluster Composition (`composition-in-cluster.yaml`) uses **function-go-templating** to render a Secret with a generated password and `DATABASE_URL`, a headless Service, and a PostgreSQL StatefulSet with the platform's defaults (non-root, a readiness probe, requests and limits sized by `size`), then reports `status.endpoint` and `status.secretName`.

The course's CI installs Crossplane 2.4 on kind and runs `kind-crossplane-test.sh`: it applies the request, waits for `Ready`, connects with the generated `DATABASE_URL`, then forces a reconciliation and checks the **password didn't change**.

## 4. Four mistakes the lab avoids

1. **Generated values that change on every reconciliation.** A Composition runs again every minute or so. A template that calls `randAlphaNum 24` each time would rotate the database password constantly and break every client. The lab's template reads the password back from the Secret it created earlier (`getComposedResource . "secret"`) and only generates a new one the first time. The CI test checks it.
2. **Missing permissions.** Crossplane may only manage what it's allowed to. To compose StatefulSets, Services and Secrets, `rbac.yaml` adds exactly those permissions to Crossplane's role with the `rbac.crossplane.io/aggregate-to-crossplane` label: no more.
3. **Readiness that lies.** A Database should only be `Ready` when PostgreSQL answers. The template marks the StatefulSet ready only when it reports a ready replica, so `kubectl wait database/orders --for=condition=Ready` really means "you can connect".
4. **A health check that asks the wrong question.** The course's CI caught this one. The `Database` became `Ready`, yet connecting over TCP was refused. On first start, the PostgreSQL image runs a temporary server that listens **only on a Unix socket** while it initialises, then restarts; `pg_isready` checks the socket by default, so it reported "ready" during initialisation. Every real client connects over TCP. The fix is one flag: `pg_isready -h 127.0.0.1`. Check readiness the way your clients connect (the same lesson as topic 13.3's probe timeout). The course fixed Module 9's PostgreSQL manifest the same way.

## 5. One API, three clouds

In production, the same `Database` request is built differently. `composition-aws-rds.yaml` (a reference, not run in CI) renders an **Amazon RDS for PostgreSQL** instance through the Upbound AWS provider: encrypted, private, 7-day backups, the password managed in Secrets Manager (topic 10.2), tagged with the team's namespace. Azure and Google Cloud versions use the Azure provider's `FlexibleServer` and the GCP provider's `DatabaseInstance` the same way.

The platform chooses the Composition per environment (with `compositionSelector` labels, or a default per namespace), so a team's YAML is identical in dev and production, and on any cloud.

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Crossplane provider | Upbound `provider-aws-*` (RDS, S3, ...) | Upbound `provider-azure-*` | Upbound `provider-gcp-*` |
| The cloud's own Kubernetes controller | AWS Controllers for Kubernetes (ACK) | Azure Service Operator v2 | Config Connector (built into GKE as an add-on) |
| Identity for the controller | EKS Pod Identity (topic 9.5) | Workload ID | Workload Identity Federation for GKE |

## Practice

1. Run `kind-crossplane-test.sh`. Then delete the StatefulSet by hand and watch Crossplane recreate it. How long does it take, and why?
2. Remove the "read the password back" lines from the Composition, apply it, and force reconciliations. Watch the password change and the connection break. Restore it.
3. Add `size: large` to the API (10 GiB, 1 CPU) with a sensible default, and show an invalid size (`huge`) is refused by the API server, before Crossplane sees it.
4. Write a second XRD for a `Bucket` with a `retention` field, and an in-cluster Composition that creates a ConfigMap describing it (a stand-in for a real bucket). Then sketch the S3 version with the AWS provider.
5. On one cloud, install the provider for its managed PostgreSQL with workload identity, and build `database-orders.yaml` as a real managed database. Record everything the team didn't have to know.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Crossplane on Kubernetes Explained](https://www.youtube.com/watch?v=2l8j_yxJbow) · Containers from the Couch · 8 min. Crossplane on Kubernetes, explained.
- [Crossplane v2: Simplified Compositions, Namespace-Scoped Resources, and More!](https://www.youtube.com/watch?v=jw8mMslpqOI) · DevOps & AI Toolkit · 15 min. What changed in Crossplane 2: namespaced resources and simpler compositions.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Governance, guardrails, and operations](https://learn.microsoft.com/training/modules/governance-guardrails-operations/)

**AWS (AWS Skill Builder):**

- [AWS Service Catalog](https://skillbuilder.aws/learn/KASUBK4E7W/aws-service-catalog/PNPUSBYTQ4)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Manage Kubernetes in Google Cloud (skill badge)](https://www.skills.google/course_templates/783)

