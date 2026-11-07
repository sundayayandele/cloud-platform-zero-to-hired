## What you will be able to do

- Explain chaos engineering as an experiment: steady state, hypothesis, controlled fault, measurement, and a limited blast radius.
- Run fault experiments on Kubernetes with Chaos Mesh: killing pods and adding network latency, with steady traffic measured from inside the cluster.
- Use AWS Fault Injection Service, Azure Chaos Studio, and Chaos Mesh on GKE, with stop conditions.
- Turn a rejected hypothesis into fixes, and prove them by running the experiment again.
- Plan game days, and move experiments safely from dev to production.

## Why this matters at work

Every resilience feature you've built so far (replicas, probes, disruption budgets, timeouts, failover) is a **belief** until it's tested. Chaos engineering tests those beliefs on purpose, at a time you choose, with people ready, instead of finding out at 2 a.m. on salary day. Netflix made it famous; AWS, Microsoft and Google now sell managed fault-injection services, and banks use them to prove resilience to regulators (the EU's DORA requires resilience testing, and African regulators increasingly ask for it). This topic has a real example: the course's own experiments found two problems in ITL Pay that every earlier test had missed.

## 1. Chaos engineering is an experiment

From the Principles of Chaos Engineering:

1. **Define the steady state**: what normal looks like, in numbers customers care about. For ITL Pay: requests succeed, `/health` answers in a few milliseconds.
2. **Form a hypothesis**: "if X fails, the steady state holds". Write it down before you start.
3. **Inject a realistic fault**: a pod dies, a zone fails, the database gets slow, a dependency returns errors.
4. **Measure**, and compare with the steady state.
5. **Limit the blast radius**: one pod, one service, a short duration, a stop condition that ends the experiment automatically if customers are hurt.

If the hypothesis holds, you've gained confidence. If it's rejected, you've found a weakness cheaply. Both are good outcomes; the bad outcome is not running the experiment.

## 2. Chaos Mesh on Kubernetes

**Chaos Mesh** (a CNCF project) injects faults with Kubernetes resources: `PodChaos` (kill or fail pods), `NetworkChaos` (latency, loss, partitions), `StressChaos` (CPU and memory), `IOChaos`, `TimeChaos` and more.

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh --version 2.8.6 -n chaos-mesh --create-namespace \
  -f labs/sre/chaos/chaos-mesh-values.yaml          # containerd runtime and socket, for kind and AKS
```

The lab's two experiments (`labs/sre/chaos/`):

```yaml
# pod-kill.yaml. Hypothesis: if one ITL Pay pod dies suddenly, customers barely notice (at most 5% of requests fail).
kind: PodChaos
spec:
  action: pod-kill
  mode: one            # one random pod: a limited blast radius
  gracePeriod: 0       # no graceful shutdown, like a node dying
  selector: { namespaces: [itlpay], labelSelectors: { app.kubernetes.io/name: itlpay } }
```

```yaml
# db-latency.yaml. Hypothesis: with 300 ms extra latency to the database, the API gets slower but nothing fails.
kind: NetworkChaos
spec:
  action: delay
  mode: all
  selector: { namespaces: [itlpay], labelSelectors: { app.kubernetes.io/name: postgres } }
  delay: { latency: 300ms }
  duration: 90s        # it ends by itself, even if no one is watching
```

**Measure from inside the cluster.** `traffic-job.yaml` calls the API five times a second and prints `RESULT ok=… failed=… median_s=…`. A `kubectl port-forward` from your laptop would be pinned to one pod, so killing that pod would break your measurement rather than the service.

## 3. What the course's experiments found

`kind-chaos-test.sh` runs both experiments on every push to the course repository. Here's the history, as it happened:

| Run | Pod kill | 300 ms database latency |
| --- | --- | --- |
| First | 0 of 199 requests failed: **hypothesis held** | Median `/health` **2.4 s**; **17 of 20 requests failed**: **rejected** |
| After fix 1 (a connection pool) | 0 of 215 failed | Median **1.2 s**; **14 failed**, with "could not connect": still rejected |
| After fix 2 (fewer round trips, probe timeout) | 0 of 212 failed | Median **303 ms**; **0 failed**: **hypothesis held** |
| Latest | 1 of 215 failed (0.47%): within the 5% hypothesis; an in-flight request on the killed pod | Median 303 ms; 0 failed |

**Finding 1: a new database connection for every request.** Opening a PostgreSQL connection takes several network round trips (TCP, startup, authentication). With 300 ms added to each, one request took 2.4 s and most hit the 3-second client timeout. Every functional test had passed, because on a fast network a new connection costs a millisecond. Fix: ITL Pay 1.2.0 keeps connections in a **pool** (`psycopg_pool`), so a request costs round trips for its queries only.

**Finding 2: the readiness probe turned slowness into an outage.** At 1.2 s per `/health`, the readiness probe hit Kubernetes' **default 1-second timeout** on every pod, so Kubernetes removed **all** pods from the Service: the "could not connect" errors. A slow database became a total outage. Fixes: the probe's `timeoutSeconds: 3`, and pooled connections in autocommit mode with no extra check on every checkout, so a health check is one round trip (303 ms).

Two lessons that apply far beyond ITL Pay:

- **Latency is a harder test than failure.** Systems are usually built for things that break cleanly; slow dependencies cause timeouts, retries and queues that fail in surprising ways.
- **Readiness probes that check dependencies need timeouts sized for degraded dependencies**, or one slow database takes every pod out of service at once (topic 9.3's warning about liveness, extended to readiness).

## 4. The clouds' fault-injection services

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Service | **AWS Fault Injection Service (FIS)** | **Azure Chaos Studio** | No first-party service: **Chaos Mesh** (or LitmusChaos) on GKE, plus managed failure tests such as Cloud SQL failover |
| Kubernetes faults | `aws:eks:pod-delete`, pod network latency, CPU stress on EKS | AKS faults run Chaos Mesh under the hood (`azureKubernetesServiceChaosMesh` faults) | Chaos Mesh |
| Infrastructure faults | Stop or terminate instances, an AZ power interruption scenario, RDS failover, network disruption | Shut down VMs, Cosmos DB failover, NSG rules that block traffic, zone-down scenarios | Simulate zone failure by stopping instances in a zone; regional failover tests |
| Stop conditions | A CloudWatch alarm stops the experiment | Experiments can be stopped; combine with Azure Monitor alerts | Your own monitoring and Chaos Mesh's duration |

The lab has templates for both managed services: `aws-fis-eks-pod-delete.json` (one pod, stopped automatically if the `itlpay-error-budget-burn` alarm fires) and `azure-chaos-studio-aks-pod-kill.json`. Both need a role or managed identity with permission to inject the fault, and nothing more.

**Always define a stop condition** tied to your SLO alert: the experiment ends itself the moment customers are hurt.

## 5. From dev to production, and game days

1. **Start in dev or staging**, with synthetic traffic, as the lab does.
2. **Automate** the experiments that pass (the course runs its own on every push), so a change that breaks resilience is caught like a failing test.
3. **Move to production carefully**: small blast radius, working hours, stop conditions, the on-call team told in advance, and error budget to spare (topic 13.1's policy: chaos experiments are a planned use of budget when more than half remains).
4. **Run game days**: a planned session where the team runs a bigger scenario (a zone down, the database failing over, the secret store unreachable) and practises the response from topic 13.2: detection, roles, runbooks, communication. The mentor-verified capstones in this course include one.

## Practice

1. Install Chaos Mesh on kind and run `kind-chaos-test.sh`. Record the three RESULT lines.
2. Recreate finding 2 on purpose: set the readiness probe's `timeoutSeconds` back to 1, run the latency experiment, and capture the "could not connect" errors and the pods' `0/1` Ready state.
3. Write and run a new experiment with a written hypothesis: `NetworkChaos` with 20% packet loss to the database, or `StressChaos` on the API pods with the HPA from topic 9.3. Did the hypothesis hold?
4. On one cloud, run the managed equivalent (AWS FIS with the template and a real CloudWatch alarm as the stop condition, or Azure Chaos Studio on AKS). Show the stop condition ending an experiment.
5. Plan a one-hour game day for ITL Pay: scenario, hypothesis, stop conditions, roles, what you'll measure, and how you'll tell stakeholders in advance.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [What is Chaos Engineering?](https://www.youtube.com/watch?v=CXhd30tDqBc) · Reliability Engineering · 4 min. What chaos engineering is.
- [Back to Basics: Chaos Engineering with AWS Fault Injection Simulator](https://www.youtube.com/watch?v=AThR8dFmPP4) · Amazon Web Services · 7 min. AWS on chaos engineering with Fault Injection Service.
- [An introduction to Azure Chaos Studio | Azure Friday](https://www.youtube.com/watch?v=pSEDDiWfnVY) · Microsoft Azure · 17 min. An introduction to Azure Chaos Studio, from Azure Friday.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Introduction to application resiliency in Azure](https://learn.microsoft.com/training/modules/introduction-application-resiliency-azure/)

