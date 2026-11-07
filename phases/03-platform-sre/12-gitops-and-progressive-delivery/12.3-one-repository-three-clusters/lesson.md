## What you will be able to do

- Choose between one Argo CD per cluster and one central Argo CD managing many clusters.
- Register EKS, AKS and GKE clusters with Argo CD, using each cloud's identity instead of long-lived tokens.
- Generate one Application per cluster with an **ApplicationSet**, from cluster labels or a list.
- Lay out a GitOps repository for several apps, environments and clouds, with the app-of-apps pattern.
- Roll a change across clouds in waves, and keep one cloud serving when another has a problem.
- Explain the security boundary a central Argo CD creates, and how to limit it.

## Why this matters at work

Platform teams rarely run one cluster. A bank might have dev, staging and production clusters in two regions, and a multi-cloud company has them on several providers, each with the same platform add-ons (monitoring, External Secrets, policies) and many applications. Doing that cluster by cluster doesn't scale: add-on versions drift, a security fix reaches some clusters and not others. Running **many clusters from one repository** is a core platform engineering skill, and ApplicationSets are the standard Argo CD way to do it.

## 1. One Argo CD or many?

| | One per cluster | One central Argo CD (hub and spoke) |
| --- | --- | --- |
| How | Argo CD installed in each cluster, syncing only itself | Argo CD in a management cluster, deploying to registered clusters |
| Blast radius | A problem stays in one cluster | The hub holds credentials to every cluster: protect it like production |
| Operations | Many Argo CDs to upgrade and watch | One UI, one place for policies and audit |
| If the hub is down | n/a | Clusters keep running; changes wait until it's back |

Many teams start with one per cluster and move to a hub as cluster counts grow. Some use one hub per environment (a dev hub and a production hub) as a middle ground. The rest of this topic uses a hub, because ApplicationSets shine there; the same repository layout works either way.

## 2. Registering the three clouds

Argo CD stores each cluster as a Secret in its namespace, labelled `argocd.argoproj.io/secret-type: cluster`, with the API server address and how to authenticate. Prefer the cloud's workload identity (topic 9.5) over long-lived tokens:

| | EKS | AKS | GKE |
| --- | --- | --- | --- |
| How Argo CD signs in | IAM role for Argo CD's service accounts (Pod Identity or IRSA) with an EKS access entry on the target cluster; `awsAuthConfig` in the cluster Secret | Workload identity with `kubelogin` (`execProviderConfig`), and an Azure RBAC role on the target cluster | Workload Identity Federation for GKE with the `gke-gcloud-auth-plugin` (`execProviderConfig`), and an IAM role on the target cluster |
| Quick start (learning only) | `argocd cluster add <context>`: creates a service account with cluster-admin in the target cluster and stores its token | | |

`argocd cluster add` is fine for a lab; in production it leaves a long-lived, all-powerful token in the hub, the kind of key topic 8.3 taught you to remove.

Label each cluster Secret so generators can select them:

```yaml
metadata:
  labels:
    argocd.argoproj.io/secret-type: cluster
    env: dev
    cloud: aws          # azure, gcp
```

## 3. ApplicationSets

An **ApplicationSet** is a template plus a **generator** that produces parameters; Argo CD creates one Application per set of parameters, and deletes it when the parameters disappear. The lab's (`labs/gitops/argocd/itlpay-clusters.yaml`):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: itlpay-dev
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - clusters:
        selector:
          matchLabels: { env: dev }       # every registered cluster labelled env=dev
  template:
    metadata:
      name: 'itlpay-dev-{{ index .metadata.labels "cloud" }}'   # itlpay-dev-aws, itlpay-dev-azure, itlpay-dev-gcp
    spec:
      source:
        repoURL: https://github.com/OWNER/REPO.git
        path: labs/gitops/kustomize/overlays/dev
      destination:
        server: '{{ .server }}'
        namespace: itlpay
      syncPolicy:
        automated: { prune: true, selfHeal: true }
```

Register a fourth dev cluster and label it `env=dev`: its Application appears without any change to Git.

| Generator | Produces one Application per... | Use it for |
| --- | --- | --- |
| `clusters` | Registered cluster (filtered by labels) | The same app or add-on on every matching cluster |
| `list` | Item in a fixed list | A few known targets |
| `git` (directories or files) | Folder or config file in a repository | A new app = a new folder |
| `matrix` | Combination of two generators | Every app × every cluster |

The course's CI validates the lab's ApplicationSet against a real Argo CD with a server-side dry run, so a wrong field is caught before learners copy it.

## 4. Laying out the repository

```text
platform-gitops/
  bootstrap/                 the "app of apps": one Application per folder below, applied once by hand
  addons/                    the same on every cluster: ApplicationSets with the clusters generator
    external-secrets/        (topic 10.2)
    kube-prometheus-stack/   (topic 11.1)
    argo-rollouts/           (topic 12.2)
  apps/
    itlpay/
      base/
      overlays/dev-aws/ dev-azure/ dev-gcp/ prod-gcp/     cloud differences live here: registry, Gateway, identity
```

- **App of apps:** you apply one Application, `bootstrap`, by hand; it creates the others. A new cluster gets the whole platform from one Git change.
- **Per-cloud overlays** carry what differs, exactly as the Helm values files did in topic 9.5: the image registry, the Gateway parent, the pod identity annotation.
- **Separate add-ons from apps**, so the platform team and the application teams review different pull requests, and an `AppProject` per team limits what each can deploy (topic 12.1).

## 5. Rolling out across clouds safely

A change merged to `main` would otherwise reach every matching cluster at once: a bad add-on version breaks three clouds together. Ways to stage it:

- **Waves by environment:** dev overlays track `main`; staging and production overlays pin a Git tag or commit, promoted by pull request (topic 12.1).
- **Progressive syncs:** ApplicationSets can update their Applications in steps, for example clusters labelled `wave: 1` first, then `wave: 2` once the first are healthy.
- **Canaries per cluster:** each cluster's Rollout runs its own analysis (topic 12.2), so a version that fails on one cloud stops there.

For resilience across clouds, run production on two clouds behind global DNS (Route 53, Azure Traffic Manager or Cloud DNS routing policies) with health checks: if one cloud's region fails, DNS sends users to the other. Data is the hard part: a PostgreSQL primary lives on one cloud, so the second cloud either reads a replica or takes over after a failover (topic 13.4).

## 6. Securing a central Argo CD

The hub can change every cluster, so:

- Sign in with SSO and give people roles (read-only for most, sync for team leads); disable the local `admin` account after setup.
- Use `AppProjects` to limit each team to its repositories, clusters and namespaces, and forbid cluster-scoped resources for app teams.
- Use cloud identities, not stored tokens, for cluster access (section 2); give the hub only the permissions it needs on each cluster.
- Put the hub's API behind a private network or an identity-aware proxy, and keep its own Git repository (bootstrap) protected by branch rules.
- Turn on Argo CD's notifications for sync failures and degraded applications, routed like any other alert (topic 11.1).

## Practice

1. On kind, create two extra kind clusters (`kind create cluster --name dev-b`) and register them with your Argo CD (`argocd cluster add`). Label them `env=dev`, `cloud=...`, and apply the lab's ApplicationSet. How many Applications appear?
2. Remove the `env=dev` label from one cluster. What happens to its Application, and to the app running in that cluster?
3. Build the `bootstrap` app of apps from section 4 for the add-ons External Secrets and Argo Rollouts, and recreate a cluster from nothing with it. Time it.
4. On one cloud, register a real cluster using its workload identity instead of `argocd cluster add`, and write down every permission you granted.
5. Write a one-page design for running ITL Pay in production on two clouds with Argo CD: hub or not, repository layout, promotion, DNS failover, and where the database primary lives.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Argo CD Tutorial: App of Apps in 8 Minutes](https://www.youtube.com/watch?v=2pvGL0zqf9o) · Akuity · 8 min. The app-of-apps pattern, from the Argo CD maintainers' company.
- [GitOps: How Many GitOps (ArgoCD) Instances Are Recommended for Multiple Environments?](https://www.youtube.com/watch?v=Tuba7LpoUVM) · DevOps & AI Toolkit · 11 min. How many Argo CD instances to run, and why.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**AWS (AWS Skill Builder):**

- [GitOps for Amazon EKS Automation](https://skillbuilder.aws/learn/KB9MZUXHSF/gitops-for-amazon-eks-automation/52PNE2AN58)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Manage Kubernetes in Google Cloud (skill badge)](https://www.skills.google/course_templates/783)

