## What you will be able to do

- Explain the problem Helm solves: one application, many environments and clusters, without copying YAML.
- Read and write a **chart**: `Chart.yaml`, `values.yaml`, templates, helpers and `NOTES.txt`.
- Install, upgrade, roll back and uninstall **releases**, and run `helm test`.
- Check charts before they reach a cluster with `helm lint`, `helm template` and schema validation.
- Publish a chart to an OCI registry (GHCR, ECR, ACR, Artifact Registry) and install third-party charts safely.
- Compare Helm with Kustomize, and know where GitOps fits.

## Why this matters at work

Almost every piece of software you'll install on a cluster (monitoring, ingress and gateway controllers, cert-manager, External Secrets, Argo CD) ships as a Helm chart, and most companies package their own services as charts too. DevOps engineers write charts, review values changes in pull requests, and run upgrades and rollbacks. "How do you deploy the same app to dev, staging and production with different settings?" is a standard interview question, and Helm is the most common answer.

## 1. The problem

The manifests from topics 9.1–9.3 hard-code the image, replica count, host name and environment. For three clouds and three environments you'd copy them nine times and they'd drift apart. Helm turns them into a **template** plus **values**:

```text
chart (templates + default values)  +  values/eks.yaml  ──helm──►  YAML for EKS  ──►  the cluster (a "release")
                                    +  values/gke.yaml  ──helm──►  YAML for GKE  ──►  ...
```

Helm also records each install as a **release** with numbered revisions, so you can see what's deployed and roll back.

## 2. Anatomy of the lab's chart

```text
labs/kubernetes/chart/itlpay/
  Chart.yaml                 name, chart version (0.1.0), appVersion (1.0.0)
  values.yaml                every setting, with safe defaults and comments
  templates/
    _helpers.tpl             named snippets: full name, labels, image reference
    deployment.yaml service.yaml configmap.yaml serviceaccount.yaml
    hpa.yaml pdb.yaml httproute.yaml ingress.yaml
    NOTES.txt                printed after install: how to check it works
    tests/test-health.yaml   the pod `helm test` runs
```

Templates are Kubernetes YAML with Go template expressions:

```yaml
# templates/deployment.yaml (extract)
metadata:
  name: {{ include "itlpay.fullname" . }}
  labels:
    {{- include "itlpay.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}          # with an HPA, the HPA owns the replica count
  {{- end }}
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      containers:
        - name: api
          image: {{ include "itlpay.image" . }}
          envFrom:
            - secretRef:
                name: {{ required "database.existingSecret is required" .Values.database.existingSecret }}
```

| Expression | Meaning |
| --- | --- |
| `.Values.x`, `.Chart.AppVersion`, `.Release.Name`, `.Release.Namespace` | Values, chart metadata, release details |
| `{{- ... }}` | Trim the whitespace before (keeps the YAML tidy) |
| `include "name" . \| nindent 4` | Insert a helper, indented 4 spaces on a new line |
| `default`, `required`, `quote`, `toYaml` | Fallback value, fail with a message if missing, quote a string, render a map or list |
| `if`, `with`, `range` | Conditionals and loops |

Three design choices in this chart are worth copying:

- **The image by digest when given** (`itlpay.image` helper): `image.digest` wins over `image.tag`, so production deploys exactly the signed image from topic 8.2.
- **The checksum annotation**: changing a value in the ConfigMap changes the pod template, so a `helm upgrade` rolls the pods (topic 9.2's "env vars are read once" problem, solved).
- **No secrets in values**: the chart takes the *name* of an existing Secret (`database.existingSecret`). Values files live in Git; passwords never should.

## 3. Releases: install, upgrade, roll back

```bash
cd labs/kubernetes
helm lint chart/itlpay
helm template itlpay chart/itlpay -n itlpay -f values/kind.yaml | less      # see exactly what would be applied
helm upgrade --install itlpay chart/itlpay -n itlpay -f values/kind.yaml --wait
helm test itlpay -n itlpay                    # runs tests/test-health.yaml: passes if /health returns 200
helm list -n itlpay
helm history itlpay -n itlpay

helm upgrade itlpay chart/itlpay -n itlpay -f values/kind.yaml --set env.LOG_LEVEL=DEBUG --wait
helm rollback itlpay 1 -n itlpay --wait       # back to revision 1
helm uninstall itlpay -n itlpay
```

- `upgrade --install` works whether or not the release exists, which is what pipelines use.
- `--wait` waits until the pods are Ready, so a failed rollout fails the command (and the pipeline). `--atomic` (called `--rollback-on-failure` in Helm 4) rolls back automatically if it fails.
- Values are merged in order: `values.yaml`, then each `-f` file, then `--set`. Prefer files in Git to `--set`, so every setting is reviewed.

`kind-smoke-test.sh` runs these steps, and the course's CI runs it on every push: a chart change that breaks the deployment fails the build.

## 4. Checking charts before they reach a cluster

| Check | Catches |
| --- | --- |
| `helm lint` | Template errors, missing chart fields |
| `helm template ... \| kubeconform -strict` | YAML that isn't valid Kubernetes (wrong field names, types). The course CI renders the chart with **every** values file |
| `values.schema.json` | Wrong types or missing required values, at install time |
| checkov or kube-linter on the rendered YAML | Security settings: root users, missing limits, privileged pods (topic 7.4's idea, for Kubernetes) |
| `helm diff upgrade` (a plugin) | What an upgrade would change, like `terraform plan`, for review |

## 5. Sharing charts: OCI registries

Charts are published to the same registries as images:

```bash
helm package chart/itlpay                                 # itlpay-0.1.0.tgz
echo "$GITHUB_TOKEN" | helm registry login ghcr.io -u YOU --password-stdin
helm push itlpay-0.1.0.tgz oci://ghcr.io/YOU/charts
helm upgrade --install itlpay oci://ghcr.io/YOU/charts/itlpay --version 0.1.0 -n itlpay -f values/gke.yaml
```

ECR, ACR and Artifact Registry all accept Helm charts the same way. Bump `version` in `Chart.yaml` on every chart change; bump `appVersion` when the default application version changes.

Installing **third-party charts** (you'll install several in Module 11 and Phase 3):

```bash
helm show values oci://ghcr.io/external-secrets/charts/external-secrets > es-values.yaml   # read the defaults first
helm upgrade --install external-secrets oci://ghcr.io/external-secrets/charts/external-secrets \
  --version <pinned> -n external-secrets --create-namespace -f es-values.yaml
```

Always **pin `--version`**, read the values (what does it create, what permissions does it ask for?), and keep your values file in Git.

## 6. Helm, Kustomize and GitOps

| | Helm | Kustomize (built into `kubectl apply -k`) |
| --- | --- | --- |
| Approach | Templates plus values | Plain YAML plus patches (overlays per environment) |
| Strengths | Packaging and sharing, releases and rollback, the ecosystem of public charts | No template language; easy to read; good for small differences |
| Weaknesses | Templates can become hard to read | No packaging, no release history |

Many teams use both: Helm for third-party software, Kustomize or Helm for their own. In Phase 3, **Argo CD** (GitOps) takes over the `helm upgrade` step: it watches Git and keeps the cluster matching it, the same reconciling idea as topic 9.1, applied to whole applications.

## Practice

1. Install the chart on kind with `values/kind.yaml`, run `helm test`, then run `helm upgrade` with a changed `LOG_LEVEL` and confirm the pods were replaced (pod names change) because of the checksum annotation.
2. Make the upgrade fail on purpose (`--set image.tag=missing --wait --timeout 60s`). What does `helm history` show? Roll back.
3. Add a `values.schema.json` that requires `database.existingSecret` and only allows `env.LOG_LEVEL` to be `DEBUG`, `INFO`, `WARNING` or `ERROR`. Show that `--set env.LOG_LEVEL=LOUD` is refused.
4. Add an optional `NetworkPolicy` template to the chart (off by default) that allows traffic to the API only from the gateway's namespace. Render it with `helm template` and check it with kubeconform.
5. Package the chart and push it to GHCR. Install it from the registry instead of the folder.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [What is Helm in Kubernetes? Helm and Helm Charts explained  | Kubernetes Tutorial 23](https://www.youtube.com/watch?v=-ykwb1d0DXU) · TechWorld with Nana · 14 min. What Helm and charts are, and why they exist.
- [How to Create Helm Charts - The Ultimate Guide](https://www.youtube.com/watch?v=jUYNS90nq8U) · DevOps Journey · 22 min. Creating your own Helm chart step by step.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Guided project: deploy applications to Azure Kubernetes Service](https://learn.microsoft.com/training/modules/project-deploy-applications-azure-kubernetes-service/)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Deploy Kubernetes Applications on Google Cloud (skill badge)](https://www.skills.google/course_templates/663)

