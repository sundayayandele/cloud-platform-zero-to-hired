## What you will be able to do

- Configure **readiness, liveness and startup probes**, and explain why a liveness probe must not check the database.
- Set **requests and limits** for CPU and memory, and explain scheduling, OOMKilled and CPU throttling.
- Scale pods with the **HorizontalPodAutoscaler** and nodes with the cluster autoscaler or Karpenter.
- Keep the app available during node maintenance with **PodDisruptionBudgets** and spread across zones with **topology spread constraints**.
- Give stateful workloads disks with **PersistentVolumeClaims, StorageClasses and StatefulSets**, and decide when a database belongs in Kubernetes.
- Limit which pods may talk to each other with a **NetworkPolicy**.

## Why this matters at work

A Deployment that "works" on day one can still cause outages: a liveness probe that restarts every pod when the database blips, a memory limit that kills the app under load, a cluster upgrade that drains all replicas at once. These settings are what separates a demo from a production workload, and platform teams review them in every pull request. Expect interview questions such as "what's the difference between readiness and liveness?" and "what happens when a container exceeds its memory limit?".

## 1. Probes: is it alive, and is it ready?

The kubelet runs three kinds of check:

| Probe | Question | On failure |
| --- | --- | --- |
| **startup** | Has the app finished starting? | Keeps waiting until `failureThreshold`, then restarts the container. Liveness and readiness don't run until it passes |
| **readiness** | Should this pod get traffic right now? | Removed from the Service's endpoints; **not** restarted |
| **liveness** | Is the process stuck beyond saving? | Container **restarted** |

The lab's choices (`manifests/30-itlpay.yaml`):

```yaml
readinessProbe:
  httpGet: { path: /health, port: http }   # /health checks the database
  periodSeconds: 5
livenessProbe:
  tcpSocket: { port: http }                # only "is the process accepting connections?"
  periodSeconds: 10
startupProbe:
  tcpSocket: { port: http }
  periodSeconds: 2
  failureThreshold: 30                     # up to 60 s to start
```

The rule: **liveness must not depend on anything outside the container.** If liveness called `/health`, a 30-second database outage would make every API pod fail liveness, Kubernetes would restart them all, and the restarts would pile load onto the database as it recovers. With readiness on `/health`, the pods simply stop receiving traffic during the outage and come back on their own. This exact mistake has caused real, widely discussed outages.

## 2. Requests and limits

```yaml
resources:
  requests: { cpu: 100m, memory: 128Mi }   # reserved: the scheduler only places the pod where this fits
  limits:   { memory: 256Mi }              # the most it may use
```

- `cpu: 100m` is a tenth of a CPU core; `128Mi` is 128 mebibytes.
- **Requests** drive scheduling and autoscaling. Too high wastes money (nodes look full but are idle); too low packs pods onto nodes that then run out.
- A **memory limit** is a hard ceiling: exceed it and the kernel kills the container (**OOMKilled**, exit code 137, then a restart). Set it with headroom above normal use.
- A **CPU limit** throttles the container even when the node has idle CPU, which shows up as mysterious latency. Many teams set CPU requests but no CPU limit, as the lab does; others set limits for strict multi-tenant fairness. Know the trade-off.

```bash
kubectl -n itlpay top pods                    # needs metrics-server (on by default or an add-on on EKS, AKS, GKE)
kubectl -n itlpay describe pod <pod> | grep -A3 "Last State"   # Reason: OOMKilled
```

Pods with requests equal to limits for both CPU and memory get the **Guaranteed** quality-of-service class and are the last to be evicted when a node runs short.

## 3. Autoscaling

Two layers work together:

```text
HorizontalPodAutoscaler: more pods when average CPU passes 70% of the request  (3 → 10)
    └─ new pods are Pending because the nodes are full
cluster autoscaler / Karpenter / node auto-provisioning: adds a node  → pods start
    └─ later, nodes sit mostly empty → pods are moved and the node removed
```

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: itlpay }
  minReplicas: 3
  maxReplicas: 10
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
```

Utilisation is measured **against the request**, so the HPA only works if requests are set and realistic. Scaling on queue length or requests per second needs custom metrics (KEDA is the common tool; Phase 3).

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Node autoscaling | **Karpenter** (built into EKS Auto Mode) or the Cluster Autoscaler | Cluster autoscaler on node pools; node auto-provisioning (Karpenter-based) | Cluster autoscaler; node auto-provisioning; Autopilot does it for you |

## 4. Staying up during maintenance

Node upgrades and scale-downs **drain** nodes: their pods are evicted and rescheduled. Two settings stop this from taking the app down:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: 2                        # a drain waits rather than leave fewer than 2 pods
  selector: { matchLabels: { app.kubernetes.io/name: itlpay } }
```

```yaml
topologySpreadConstraints:               # in the Deployment: spread pods across zones
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector: { matchLabels: { app.kubernetes.io/name: itlpay } }
```

Three replicas spread over three zones survive a zone outage (Capstone 1's lesson, now automatic). Don't set `minAvailable` equal to the replica count: then no drain can ever proceed and upgrades get stuck.

## 5. Storage: volumes, claims and StatefulSets

Containers lose their files when they restart. For data that must survive:

```text
PersistentVolumeClaim (PVC)   "I need 1 GiB, ReadWriteOnce"           ← the app asks
StorageClass                  "gp3 on EBS" / "Azure managed disk" / "pd-balanced"  ← how to make one
PersistentVolume (PV)         the actual disk, created on demand by the cloud's CSI driver
```

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Block disk (one node at a time) | EBS CSI driver | Azure Disk CSI driver | Compute Engine persistent disk CSI driver |
| Shared files (many nodes) | EFS CSI driver | Azure Files | Filestore |

A **StatefulSet** is a Deployment for workloads that need a stable identity and their own disk: pods are named `postgres-0`, `postgres-1`, start in order, and each gets its own PVC from `volumeClaimTemplates` that stays when the pod is replaced. The lab runs PostgreSQL this way (`manifests/10-postgres.yaml`).

**Should the database run in Kubernetes?** For learning and for throwaway environments, yes. For ITL Pay in production, use the managed database (RDS, Azure Database for PostgreSQL, Cloud SQL: topic 6.7): backups, patching, failover and point-in-time recovery are done for you. Teams that do run databases on Kubernetes use an **operator** (such as CloudNativePG) and accept the operational work. A bare StatefulSet like the lab's has no backups, so never put real money in it.

## 6. NetworkPolicy: who may talk to whom

By default every pod can reach every other pod. The lab allows only the API to reach PostgreSQL:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-from-itlpay-only
spec:
  podSelector: { matchLabels: { app.kubernetes.io/name: postgres } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app.kubernetes.io/name: itlpay } }
      ports: [{ port: 5432 }]
```

The policy only works if the cluster's network plugin enforces it: on EKS enable network policy in the VPC CNI, on AKS use Azure CNI powered by Cilium (or Calico), on GKE use Dataplane V2. kind's default plugin ignores it, so test it on a cloud cluster in topic 9.5.

## Practice

1. Apply `50-scaling.yaml`. Stop PostgreSQL (`kubectl -n itlpay scale statefulset/postgres --replicas=0`) and watch the API pods: do they restart, or just become `0/1` Ready? Start it again.
2. Change the liveness probe to `httpGet /health` and repeat exercise 1. Record the restart counts, then revert. Write a paragraph for your learning log explaining what you saw.
3. Set the API's memory limit to `40Mi` and watch for `OOMKilled`. Revert.
4. Install metrics-server on kind (its README has the kind flag), run a load test (`hey` or a loop of `curl` from a temporary pod), and watch the HPA scale out with `kubectl get hpa -w`.
5. Delete `postgres-0` and show the data survives (a transfer you made earlier is still there). Then delete the StatefulSet **and** its PVC and show it doesn't.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Kubernetes Health Checks: Liveness vs. Readiness vs. Startup Probe](https://www.youtube.com/watch?v=fqfieWP1jY4) · Anton Putra · 3 min. Liveness, readiness and startup probes in under three minutes.
- [All You Need to Know in 12 Minutes: Pods' Requests and Limits in Kubernetes](https://www.youtube.com/watch?v=lKH1K5R3kqg) · The Good Guy · 13 min. Requests and limits, and what happens when pods exceed them.
- [Kubernetes Volumes explained | Persistent Volume, Persistent Volume Claim & Storage Class](https://www.youtube.com/watch?v=0swOh5C3OVM) · TechWorld with Nana · 21 min. Persistent volumes, claims and storage classes.
- [Kubernetes StatefulSet simply explained | Deployment vs StatefulSet](https://www.youtube.com/watch?v=pPQKAR1pA9U) · TechWorld with Nana · 16 min. StatefulSets compared with Deployments.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Configure scaling in Azure Kubernetes Service](https://learn.microsoft.com/training/modules/configure-scaling-azure-kubernetes-service/)
- [Monitor and troubleshoot applications on Azure Kubernetes Service](https://learn.microsoft.com/training/modules/monitor-apps-azure-kubernetes-service/)

**AWS (AWS Skill Builder):**

- [Amazon Elastic Kubernetes Service (EKS) Getting Started](https://skillbuilder.aws/learn/MHH12MUT32/amazon-elastic-kubernetes-service-eks-getting-started/41CC6FD698)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Architecting with Google Kubernetes Engine: Production](https://www.skills.google/course_templates/33)
- [Optimize Costs for Google Kubernetes Engine](https://www.skills.google/course_templates/655)

