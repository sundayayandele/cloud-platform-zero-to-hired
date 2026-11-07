## What you will be able to do

- Explain progressive delivery, and compare rolling updates, blue-green and canary releases.
- Turn a Deployment into an Argo Rollouts **Rollout** with canary steps.
- Write an **AnalysisTemplate** that tests the new version automatically, with a Job or with Prometheus metrics.
- Make a bad release roll back by itself: failed analysis, and a progress deadline for versions that never become ready.
- Shift real traffic by percentage with the Gateway API, and know what each cloud offers.
- Operate a rollout: watch, promote, abort and retry.

## Why this matters at work

Most outages start with a change. A rolling update (topic 9.1) replaces pods gradually, but it only checks that pods are *ready*, not that they're *right*: a version that returns wrong balances, or fails one transfer in ten, rolls out to everyone. **Progressive delivery** sends a small share of traffic to the new version first, measures it, and continues only if it's healthy. That's how large payment companies and banks release many times a day without many incidents, and "how do you release safely?" is a standard SRE interview question. Argo Rollouts is the most common Kubernetes tool for it, alongside Flagger.

## 1. Release strategies

| Strategy | How | Risk | Cost |
| --- | --- | --- | --- |
| **Recreate** | Stop all old pods, start new ones | Downtime | Cheapest |
| **Rolling update** | Replace pods a few at a time (Deployment default) | A bad version reaches everyone, gradually | No extra capacity |
| **Blue-green** | Run the full new version beside the old, switch traffic at once, keep the old ready | Everyone moves at once, but switching back is instant | Double capacity during the release |
| **Canary** | Give the new version a small share (5%, 25%, 50%...), check it, then continue | Only the canary's share is affected, and only until the check fails | A little extra capacity |

Canary plus **automated analysis** is the goal: no one has to watch a dashboard and decide.

## 2. A Rollout

Argo Rollouts adds a `Rollout` resource that replaces a Deployment: the same pod template, plus a `strategy`. The lab's (`labs/gitops/rollouts/rollout.yaml`):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: itlpay
spec:
  replicas: 2
  progressDeadlineSeconds: 90
  progressDeadlineAbort: true
  strategy:
    canary:
      stableService: itlpay          # Argo Rollouts points this Service at the stable pods...
      canaryService: itlpay-canary   # ...and this one at the new version's pods
      steps:
        - setWeight: 50
        - analysis:
            templates: [{ templateName: smoke-test }]
            args: [{ name: service, value: itlpay-canary }]
        - setWeight: 100
  template: ...                      # the same pod template as the Deployment
```

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts --server-side -f https://github.com/argoproj/argo-rollouts/releases/download/v1.10.1/install.yaml
kubectl apply -k labs/gitops/rollouts
kubectl argo rollouts get rollout itlpay -n itlpay --watch     # with the kubectl plugin from the same release
```

(`--server-side` again: like Argo CD's, these custom resource definitions are too large for client-side apply.)

Without a traffic router, `setWeight: 50` means "half the **pods**": with 2 replicas, 1 canary pod behind the shared Service. With a router (section 5), it means half the **requests**, independent of pod counts.

Other step types: `pause: {duration: 10m}` (wait), `pause: {}` (wait for a person to promote), and `setCanaryScale` (run canary pods without sending them traffic, to test them first).

## 3. Analysis: let the release test itself

An **AnalysisTemplate** defines measurements and what counts as success. The lab's runs a Job three times, 10 seconds apart, that calls the **canary** Service's `/health` and makes a 1-kobo transfer; one failure aborts the release:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: smoke-test
spec:
  args: [{ name: service }]
  metrics:
    - name: smoke
      count: 3
      interval: 10s
      failureLimit: 0
      provider:
        job:
          spec: ... curl -fsS http://{{args.service}}/health && curl -fsS -X POST http://{{args.service}}/api/v1/transfers ...
```

With Prometheus (topic 11.1) you can check what users actually experience, with the canary's own error ratio (scraped through a ServiceMonitor on the `itlpay-canary` Service, so its `job` label is that name):

```yaml
metrics:
  - name: error-ratio
    interval: 1m
    count: 5
    successCondition: result[0] < 0.01
    failureLimit: 1
    provider:
      prometheus:
        address: http://prometheus-operated.monitoring:9090
        query: |
          sum(rate(http_requests_total{job="itlpay-canary",status=~"5.."}[2m]))
          / sum(rate(http_requests_total{job="itlpay-canary"}[2m]))
```

Good analyses check **what the business cares about** (transfers succeed, error ratio, p95 latency), not only that pods are up. Run them long enough to see real traffic: 30 seconds of a quiet dev environment proves little.

## 4. Automatic rollback

Two safety nets in the lab's Rollout:

| Problem | Caught by | What happens |
| --- | --- | --- |
| The new version is **ready but wrong** (errors, failed transfers) | The analysis fails | The rollout is **aborted**: canary pods scaled down, all traffic stays on stable |
| The new version **never becomes ready** (bad image, crash, bad config) | `progressDeadlineSeconds: 90` with `progressDeadlineAbort: true` | Aborted after 90 seconds |

After an abort the Rollout shows `Degraded` with the stable version still serving. Fix forward (a new commit) or revert the change in Git; `kubectl argo rollouts retry rollout itlpay` tries the same version again.

The course's CI tests both nets on kind: a good change (a new setting) passes the smoke test and is promoted; a broken image is aborted at the deadline, and `/health` on the stable Service keeps answering throughout.

**With GitOps (topic 12.1)** the Rollout lives in Git and Argo CD syncs it. After an abort, Git still says "the new version", so Argo CD shows the application as *Degraded*: that's correct, it tells you Git describes a release that failed. Revert the commit to make Git and the cluster agree again.

## 5. Real traffic splitting

Pod-based weights are coarse (with 4 replicas, the smallest step is 25%). A **traffic router** splits requests precisely. Argo Rollouts supports the **Gateway API** through a plugin, which works with each cloud's implementation from topic 9.5, and service meshes:

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Gateway API weights (Rollouts Gateway API plugin) | AWS Load Balancer Controller | Application Gateway for Containers | GKE Gateway controller |
| Other options | Istio (AWS App Mesh reached end of support on 30 September 2026) | Istio-based service mesh add-on for AKS | Cloud Service Mesh (Istio-based) |
| Without Kubernetes | Lambda aliases and CodeDeploy traffic shifting | App Service and Container Apps traffic splitting | Cloud Run traffic splitting |

With the Gateway plugin, Argo Rollouts edits the `weight` on the HTTPRoute's two `backendRefs` (topic 9.2) at each step: 5% of requests, then 25%, then 100%.

## 6. Operating rollouts

```bash
kubectl argo rollouts get rollout itlpay -n itlpay              # steps, weights, analysis runs, ReplicaSets
kubectl argo rollouts promote itlpay -n itlpay                  # skip a pause (with care)
kubectl argo rollouts abort itlpay -n itlpay                    # stop now, back to stable
kubectl argo rollouts dashboard                                 # a local web UI
kubectl -n itlpay get analysisruns                              # each analysis and its result
```

Alerts (topic 11.1) still matter: page on an aborted production rollout, because it means a bad version reached a commit on `main`.

## Practice

1. Install Argo Rollouts on kind, apply `labs/gitops/rollouts`, and watch a change (a new `APP_ENV` value) go through the steps with `kubectl argo rollouts get rollout --watch`.
2. Break the release three ways and record what stops each: an image that doesn't exist, a wrong database password in a new Secret name, and a version whose `/health` works but transfers fail (point it at an empty database).
3. Add a `pause: {}` step before `setWeight: 100` and promote it by hand. When would a manual gate be right in a bank?
4. Replace the Job analysis with the Prometheus error-ratio analysis from section 3 on a cluster running the Module 11 stack. Generate traffic during the canary and make it fail on purpose.
5. On one cloud, install the Rollouts Gateway API plugin and run a 10% → 50% → 100% canary by request share. Show the HTTPRoute's weights changing.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Top 5 Most-Used Deployment Strategies](https://www.youtube.com/watch?v=AWVTKBUnoIg) · ByteByteGo · 10 min. The common deployment strategies compared, from ByteByteGo.
- [Argo Rollouts in 15 minutes!](https://www.youtube.com/watch?v=w3xdopP4aEk) · DevOps Journey · 14 min. Argo Rollouts in 15 minutes.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Implement canary releases and dark launching](https://learn.microsoft.com/training/modules/implement-canary-releases-dark-launching/)
- [Implement blue-green deployment and feature toggles](https://learn.microsoft.com/training/modules/implement-blue-green-deployment-feature-toggles/)
- [Implement A/B testing and progressive exposure deployment](https://learn.microsoft.com/training/modules/implement-test-progressive-exposure-deployment/)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Deploy Kubernetes Applications on Google Cloud (skill badge)](https://www.skills.google/course_templates/663)

