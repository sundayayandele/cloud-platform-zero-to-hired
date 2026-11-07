## What you will be able to do

- Explain GitOps: Git as the single source of truth, and a controller that pulls changes into the cluster and keeps it there.
- Compare push-based delivery (Module 8's `helm upgrade` from the pipeline) with pull-based GitOps, and say when each fits.
- Write Kustomize bases and overlays for dev and production.
- Install Argo CD, create an Application, and use automated sync, self-heal and prune.
- Promote a release between environments with a pull request, and roll back with `git revert`.
- Keep secrets out of a GitOps repository.

## Why this matters at work

In Capstone 2 the pipeline pushed releases into the clusters with `helm upgrade`, which means the pipeline holds credentials to every cluster, and anything changed by hand in a cluster stays changed until someone notices. Most platform teams now run **GitOps** instead: a controller inside each cluster watches Git and makes the cluster match it, all the time. Every change is a reviewed commit, rollback is `git revert`, and an auditor's question "who changed production, when, and who approved it?" is answered by the Git history. Argo CD and Flux are named in a large share of platform and SRE job adverts, and Argo CD is a graduated CNCF project used by banks, telcos and most large Kubernetes users.

## 1. GitOps in four principles

The OpenGitOps project defines it as:

1. **Declarative:** the whole desired state is described as data (YAML), not as steps.
2. **Versioned and immutable:** that description lives in Git, with history.
3. **Pulled automatically:** software agents fetch the desired state from Git; no one pushes into the cluster.
4. **Continuously reconciled:** the agents keep comparing actual with desired state and fix any difference.

It's the reconciling idea from topic 9.1, applied to whole applications and environments.

```text
push (Module 8)                                  pull (GitOps)
pipeline ──kubectl/helm──► cluster               pipeline ──commit──► Git ◄──watches── Argo CD (in the cluster) ──► cluster
needs cluster credentials in CI                  CI needs only Git access; the cluster reaches out
hand changes in the cluster stay                 hand changes are undone within minutes
```

The pipeline doesn't disappear: it still tests, builds, scans and signs the image (Module 8), then **opens or makes a commit** that changes the image digest in the environment's folder. Argo CD does the rest.

## 2. Kustomize: one base, small overlays

Helm templates (topic 9.4) are one way to vary manifests per environment; **Kustomize** is the other, and it's built into `kubectl` and Argo CD. It never uses a template language: it takes plain YAML and applies patches.

```text
labs/gitops/kustomize/
  base/                   deployment.yaml, service.yaml, kustomization.yaml (settings from a configMapGenerator)
  overlays/dev/           kustomization.yaml: namespace itlpay, 2 replicas, image itlpay-lite:ci, APP_ENV=dev, DEBUG logs
  overlays/prod/          kustomization.yaml + pdb.yaml: namespace itlpay-prod, 4 replicas, image by digest, APP_ENV=prod
```

```yaml
# overlays/dev/kustomization.yaml
namespace: itlpay
resources:
  - ../../base
images:
  - name: itlpay-lite
    newName: itlpay-lite
    newTag: ci
replicas:
  - name: itlpay
    count: 2
configMapGenerator:
  - name: itlpay
    behavior: merge
    literals: [APP_ENV=dev, LOG_LEVEL=DEBUG]
```

```bash
kubectl kustomize labs/gitops/kustomize/overlays/dev     # see exactly what would be applied
kubectl apply -k labs/gitops/kustomize/overlays/dev      # what Argo CD does for you
```

One detail worth knowing: the `configMapGenerator` adds a **hash** to the ConfigMap's name (`itlpay-7g492642m9`) and rewrites every reference to it. Change a setting and the name changes, so the Deployment's pod template changes and the pods roll: the same problem the Helm chart solved with a checksum annotation in topic 9.4.

| | Helm | Kustomize |
| --- | --- | --- |
| How it varies YAML | Templates and values | Patches and overlays on plain YAML |
| Best for | Packaging and sharing software, many options | Your own apps with a few differences per environment |
| In Argo CD | Supported (it renders the chart) | Supported (it runs Kustomize) |

Many teams use Kustomize overlays that refer to a Helm chart, or the reverse. Choose one per application and be consistent.

## 3. Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/manifests/install.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:443          # https://localhost:8080, user admin
```

(`--server-side` is needed because Argo CD's custom resource definitions are too large for client-side apply. Change the admin password at once, then use SSO: Argo CD supports GitHub, Microsoft Entra ID and Google sign-in.)

An **Application** connects a folder in Git to a namespace in a cluster:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: itlpay-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/OWNER/REPO.git
    targetRevision: main
    path: labs/gitops/kustomize/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: itlpay
  syncPolicy:
    automated:
      prune: true      # deleted from Git → deleted from the cluster
      selfHeal: true   # changed by hand in the cluster → put back
```

| Status | Meaning |
| --- | --- |
| **Synced / OutOfSync** | Does the cluster match Git? |
| **Healthy / Progressing / Degraded** | Are the resources working (pods ready, rollout finished)? |

Argo CD shows the difference between Git and the cluster resource by resource, which makes it a good debugging tool even before you turn on automated sync.

**Projects** (`AppProject`) limit what an Application may deploy and where: which repositories, which clusters and namespaces, which kinds of resource. The `default` project allows everything; real platforms give each team a project.

## 4. Promotion and rollback with Git

```text
merge to main → pipeline builds, scans and signs sha256:abc → bot commits the digest to overlays/dev → Argo CD syncs dev
reviewer approves a pull request copying sha256:abc to overlays/prod → merge → Argo CD syncs prod
```

- **Promotion** is a pull request that changes the production overlay's `images` entry. Branch protection (topic 4.2) and required reviewers replace the GitHub environment approval from topic 8.4.
- **Rollback** is `git revert` of that commit. The cluster follows within minutes, and the history shows who rolled back and why.
- **Don't** deploy by changing the cluster: with `selfHeal: true`, Argo CD will put it back. In an incident you can pause automated sync on one Application, fix forward in Git, then re-enable it.

Two common repository layouts: the application's manifests in the **same repository** as its code (simple), or a separate **environment repository** that holds what runs where (cleaner permissions and audit for regulated teams; most banks choose this).

## 5. Secrets in a GitOps repository

Everything in the repository is visible to everyone who can read it, forever. The options:

| Approach | How |
| --- | --- |
| **External Secrets** (topic 10.2) | Commit the `ExternalSecret` and `SecretStore`; the values stay in the cloud's secret store. The usual choice on the three clouds |
| **Sealed Secrets** | Commit a Secret encrypted with the cluster's public key; only the controller in that cluster can decrypt it |
| **SOPS** | Commit files encrypted with a KMS key (AWS KMS, Azure Key Vault, Cloud KMS); Argo CD decrypts them with a plugin |

The lab's Deployment refers to the `itlpay-db` Secret by name only; External Secrets creates it.

## 6. The lab, in CI

`labs/gitops/kind-gitops-test.sh` runs on kind in the course's CI on every push. It uninstalls the Helm release from Module 9 (the database and Secret stay), installs Argo CD, points an Application at **the commit being tested**, waits for `Synced/Healthy`, checks `/health` reports `env: dev`, scales the Deployment to 5 by hand, and checks Argo CD puts it back to 2.

## Practice

1. Install Argo CD on kind and create the `itlpay-dev` Application pointing at your own repository. Open the UI and find the resource tree and the diff view.
2. Change `LOG_LEVEL` in the dev overlay, commit and push. Time how long until the pods have rolled, and explain why they rolled at all.
3. Delete the Service by hand (`kubectl -n itlpay delete svc itlpay`). What does Argo CD do, and which setting made it happen?
4. Add a staging overlay (3 replicas, `APP_ENV=staging`) and a second Application for it. Promote an image from dev to staging with a pull request, then roll it back with `git revert`.
5. Create an `AppProject` for the ITL Pay team that only allows the `itlpay` namespaces and your repository, and move both Applications into it. Show that an Application pointing at another namespace is refused.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [What is GitOps, How GitOps works and Why it's so useful](https://www.youtube.com/watch?v=f5EpcWp0THw) · TechWorld with Nana · 12 min. What GitOps is and why teams use it.
- [Kustomize 101: Simple Hands-On Demo with Code](https://www.youtube.com/watch?v=DAH5XnHlBXw) · Nodematic Tutorials · 8 min. Kustomize bases and overlays, hands on.
- [ArgoCD Tutorial for Beginners | GitOps CD for Kubernetes](https://www.youtube.com/watch?v=MeU5_k9ssrs) (optional, longer) · TechWorld with Nana · 48 min. A full Argo CD tutorial for beginners.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**AWS (AWS Skill Builder):**

- [GitOps for Amazon EKS Automation](https://skillbuilder.aws/learn/KB9MZUXHSF/gitops-for-amazon-eks-automation/52PNE2AN58)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Implement CI/CD Pipelines on Google Cloud (Cloud Build and Cloud Deploy)](https://www.skills.google/course_templates/691)

