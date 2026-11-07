## What you will be able to do

- Explain what Kubernetes does, and what problems it solves that a VM and Docker Compose don't.
- Name the parts of a cluster (API server, etcd, scheduler, controllers, kubelet) and say what each one does.
- Explain the **declarative, reconciling** model: you describe the desired state, controllers make it true and keep it true.
- Use the core objects: Pod, Deployment, ReplicaSet, Namespace, labels and selectors.
- Run a local cluster with **kind**, deploy ITL Pay Lite, scale it, roll out a new version and roll back, with `kubectl`.
- Explain what EKS, AKS and GKE manage for you, and what stays your job.

## Why this matters at work

Kubernetes is where most container workloads in medium and large companies run: banks, telcos, fintechs and nearly every SaaS company with more than a handful of services. Platform engineering teams exist largely to run it well for everyone else. "Kubernetes" (or "EKS/AKS/GKE") appears in a large share of DevOps, SRE and platform job adverts, and the CKA and CKAD certifications are among the most recognised in the field. You don't need to know every object; you need to understand the model, read manifests fluently and debug a pod that won't start.

## 1. What Kubernetes is for

In Capstone 1 you ran ITL Pay on VMs behind a load balancer, and in Module 5 with Docker Compose on one machine. Both leave you to answer by hand:

| Question | VMs / Compose | Kubernetes |
| --- | --- | --- |
| A container crashes at 3 a.m. | Compose restarts it on that machine; if the machine dies, nothing does | A controller replaces it, on another node if needed |
| Run 3 copies across zones | Your scripts and the load balancer's target groups | `replicas: 3` plus a spread rule |
| Release a new version with no downtime | Your rolling script (Capstone 1) | `kubectl set image` or `helm upgrade`: a rolling update is built in |
| Find the other service's address | Fixed IPs or DNS you manage | Built-in service discovery: `http://postgres:5432` |
| Many teams share machines safely | Hard | Namespaces, quotas, RBAC, network policies |

The price: Kubernetes is a large system with its own learning curve and running costs. For one small app, a managed container service (AWS App Runner or ECS, Azure Container Apps, Cloud Run) is often the better choice; you'll compare them in Phase 3. Kubernetes pays off when many services and teams share one platform.

## 2. The parts of a cluster

```text
                 control plane (managed for you on EKS, AKS, GKE)
  kubectl ──►  API server ──── etcd (the cluster's database: every object, its spec and status)
                 │   ▲
                 │   └── scheduler (picks a node for each new pod)
                 │   └── controller manager (Deployment, ReplicaSet, Node, Job... controllers)
                 ▼
  node 1: kubelet ── container runtime (containerd) ── pods          node 2: ...
          kube-proxy or the network plugin (CNI): pod networking and Services
```

- **API server:** the only door. `kubectl`, controllers, the kubelet and your pipeline all talk to it, and it checks who you are (authentication), what you may do (RBAC) and whether the object is allowed (admission).
- **etcd:** stores the desired and current state of every object. Lose it without a backup and you lose the cluster's configuration (managed services back it up for you).
- **Scheduler:** places pods on nodes with enough free CPU and memory that match any rules.
- **Controllers:** loops that compare desired with actual state and act on the difference.
- **kubelet:** the agent on each node: starts the pod's containers through the container runtime, runs probes, reports status.

## 3. Declarative and reconciling

You never tell Kubernetes "start three containers". You **declare** "there should be a Deployment with 3 replicas of this image", and controllers keep working until reality matches, forever:

```text
you: kubectl apply -f deployment.yaml   (desired: 3 replicas)
Deployment controller: creates a ReplicaSet for this version
ReplicaSet controller: sees 0 pods, wants 3 → creates 3 Pod objects
scheduler: assigns each pod to a node
kubelet on each node: pulls the image, starts the container, reports Ready
later: a node dies → the ReplicaSet sees 2 → creates 1 more → it lands on a healthy node
```

It's the same idea as Terraform (Module 7), but continuous: Terraform reconciles when you run it; Kubernetes reconciles all the time. This is why you **edit the YAML and re-apply** instead of fixing things by hand: a hand edit to a pod is undone the moment the controller replaces it.

## 4. The core objects

Every object has the same shape:

```yaml
apiVersion: apps/v1          # API group and version
kind: Deployment
metadata:
  name: itlpay
  namespace: itlpay
  labels: { app.kubernetes.io/name: itlpay }
spec: ...                    # what you want
# status: ...                # what is (written by Kubernetes, not by you)
```

| Object | What it is |
| --- | --- |
| **Pod** | One or more containers that share a network address and volumes; the smallest thing Kubernetes runs. Pods are disposable: you rarely create them directly |
| **ReplicaSet** | Keeps N identical pods running |
| **Deployment** | Manages ReplicaSets to roll out new versions gradually and roll back |
| **Namespace** | A folder for objects: one per app or team and environment, with its own permissions and quotas |
| **Labels and selectors** | Key/value tags on objects (`app.kubernetes.io/name: itlpay`). A Deployment finds its pods, and a Service its endpoints, by **selector**, not by name |

Open `labs/kubernetes/manifests/30-itlpay.yaml` and find the selector in the Deployment's `spec.selector.matchLabels` and the matching labels on the pod template. If they differ, the API server rejects the Deployment.

The lab's namespace (`00-namespace.yaml`) enforces the **restricted Pod Security** level: the API server refuses any pod that runs as root, allows privilege escalation or keeps Linux capabilities. That's why the Deployment sets `runAsNonRoot`, `runAsUser: 10001` (the image's `USER app` is a name, and Kubernetes needs the number to check it isn't root), `allowPrivilegeEscalation: false` and drops all capabilities. Build this habit from day one: it's what security reviews check first.

## 5. Your first cluster with kind

**kind** ("Kubernetes in Docker") runs a whole cluster inside a Docker container: free, local, created in a minute, and the same Kubernetes as the clouds. Codespaces from Module 1 works.

```bash
kind create cluster --name itlpay
kubectl get nodes                              # one node: itlpay-control-plane, Ready
kubectl get pods -A                            # the system pods: API server, etcd, CoreDNS, kube-proxy...

cd labs/kubernetes
docker build -t itlpay-lite:ci ../itlpay-lite
kind load docker-image itlpay-lite:ci --name itlpay   # copy the image into the cluster (no registry needed)
```

`kind-smoke-test.sh` does all of the steps in this module for you; walk through them by hand the first time:

```bash
kubectl apply -f manifests/00-namespace.yaml
kubectl -n itlpay create secret generic postgres --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 16)"
kubectl apply -f manifests/10-postgres.yaml
kubectl -n itlpay get pods -w                  # watch postgres-0 become Running and 1/1 Ready; Ctrl+C
kubectl apply -f manifests/20-config.yaml       # settings (topic 9.2)
pw=$(kubectl -n itlpay get secret postgres -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
kubectl -n itlpay create secret generic itlpay-db --from-literal=DATABASE_URL="postgresql://itlpay:$pw@postgres:5432/itlpay"
sed 's#IMAGE#itlpay-lite:ci#' manifests/30-itlpay.yaml | kubectl apply -f -
kubectl -n itlpay patch deployment itlpay -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","imagePullPolicy":"Never"}]}}}}'
kubectl -n itlpay rollout status deployment/itlpay
```

## 6. kubectl: the commands you'll use every day

| Task | Command |
| --- | --- |
| What's running | `kubectl -n itlpay get pods -o wide`, `get deploy,rs,svc` |
| Why isn't it starting | `kubectl -n itlpay describe pod <pod>` (read **Events** at the bottom) |
| Logs | `kubectl -n itlpay logs <pod>`, `logs -l app.kubernetes.io/name=itlpay --tail=50`, `logs <pod> --previous` (the crashed container) |
| A shell inside | `kubectl -n itlpay exec -it <pod> -- sh` (not in production as a habit) |
| Reach a service from your machine | `kubectl -n itlpay port-forward svc/itlpay 8080:80`, then `curl localhost:8080/health` |
| Scale | `kubectl -n itlpay scale deployment/itlpay --replicas=5` |
| See the YAML Kubernetes stores | `kubectl -n itlpay get deploy itlpay -o yaml` |
| Explain a field | `kubectl explain deployment.spec.strategy` |
| Default namespace | `kubectl config set-context --current --namespace itlpay` |

The usual pod problems, and where `describe` shows them:

| Status | Usual cause |
| --- | --- |
| `Pending` | No node has enough CPU/memory for the requests, or a volume can't attach |
| `ImagePullBackOff` / `ErrImagePull` | Wrong image name or tag, private registry without credentials |
| `CrashLoopBackOff` | The app starts and exits: read `logs --previous` |
| `CreateContainerConfigError` | A referenced Secret or ConfigMap doesn't exist |
| Running but `0/1` Ready | The readiness probe fails (topic 9.3) |

## 7. Rolling out and rolling back

```bash
kubectl -n itlpay set image deployment/itlpay api=itlpay-lite:does-not-exist
kubectl -n itlpay rollout status deployment/itlpay      # stalls: the new pod can't pull its image
kubectl -n itlpay get pods                              # the 3 old pods still serve traffic (maxUnavailable: 0)
kubectl -n itlpay rollout history deployment/itlpay
kubectl -n itlpay rollout undo deployment/itlpay        # back to the previous ReplicaSet
```

`maxUnavailable: 0` and `maxSurge: 1` mean Kubernetes starts one new pod, waits for it to be **Ready**, then removes one old pod, and repeats. A broken version never takes the healthy pods away. (In practice you'd change the YAML in Git and let the pipeline apply it, not use `set image`: Module 8 and topic 9.4.)

## 8. What the clouds manage for you

| | Amazon EKS | Azure AKS | Google GKE |
| --- | --- | --- | --- |
| Control plane (API server, etcd) | Managed; paid per cluster-hour | Managed; free tier without an SLA, paid Standard tier with one | Managed; paid per cluster-hour, with a monthly free-tier credit that covers one cluster's fee |
| Nodes | Managed node groups, or **EKS Auto Mode** (AWS runs the nodes too) | Node pools, or **AKS Automatic** | Node pools (Standard), or **Autopilot** (Google runs the nodes, you pay per pod) |
| Your job | Workloads, add-ons, upgrades, node capacity, security settings | Same | Same (less with Autopilot) |

Topic 9.5 goes into networking, identity and upgrades on each. Until then, kind is all you need, at no cost.

## Practice

1. Create the kind cluster and deploy PostgreSQL and the API by hand as in section 5. Draw the parts of section 2 and mark where each of your objects lives.
2. Delete one API pod (`kubectl delete pod <name>`) and watch a replacement appear. Which controller created it? (Hint: `kubectl get pod <new> -o yaml | grep -A3 ownerReferences`.)
3. Break it on purpose three ways and record the status and the `describe` event for each: a wrong image tag, a missing Secret name, and `runAsUser: 0` (what does the namespace's Pod Security say?).
4. Roll out a bad image and roll back, as in section 7. Note how long the healthy pods kept serving.
5. Edit a pod's labels by hand so it no longer matches the selector (`kubectl label pod <name> app.kubernetes.io/name=other --overwrite`). What does the ReplicaSet do, and why?

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [What is Kubernetes | Kubernetes explained in 15 mins](https://www.youtube.com/watch?v=VnvRFRk_51k) · TechWorld with Nana · 14 min. What Kubernetes is and the problems it solves.
- [Kubernetes Explained in 6 Minutes | k8s Architecture](https://www.youtube.com/watch?v=TlHvYWVUZyc) · ByteByteGo · 6 min. The architecture in six minutes: control plane and nodes.
- [Kubernetes Crash Course for Absolute Beginners [NEW]](https://www.youtube.com/watch?v=s_o8dwzRlu4) (optional, longer) · TechWorld with Nana · 72 min. A full beginner's crash course with hands-on examples.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Deploy containers by using Azure Kubernetes Service (learning path)](https://learn.microsoft.com/training/paths/deploy-manage-containers-azure-kubernetes-service/)
- [Plan an Azure Kubernetes Service deployment](https://learn.microsoft.com/training/modules/plan-azure-kubernetes-service-deployment/)

**AWS (AWS Skill Builder):**

- [Introduction to Kubernetes Core Concepts](https://skillbuilder.aws/learn/U4Z3BPGK9Y/introduction-to-kubernetes-core-concepts/DZCQ4QTSJT)
- [Why run your Kubernetes workloads on Amazon EKS?](https://skillbuilder.aws/learn/6MCV5DBF5N/why-run-your-kubernetes-workloads-on-amazons-elastic-kubernetes-service-eks/W4BB5XPWB8)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Getting Started with Google Kubernetes Engine](https://www.skills.google/course_templates/2)
- [Kubernetes in Google Cloud (skill badge)](https://www.skills.google/course_templates/744)

