## What you will be able to do

- Give pods a stable address with a **Service**, and choose between ClusterIP, NodePort, LoadBalancer and headless Services.
- Explain how cluster DNS turns `postgres` into an address.
- Bring traffic in from outside with the **Gateway API** (Gateway and HTTPRoute), and read the older **Ingress** you'll still meet.
- Keep settings in **ConfigMaps** and passwords in **Secrets**, and pass them to containers.
- Explain what a Kubernetes Secret does and doesn't protect, and how teams keep secrets out of Git.

## Why this matters at work

Most "the app is up but nobody can reach it" incidents on Kubernetes come down to a Service whose selector matches nothing, a route pointing at the wrong port, or a missing Secret. Knowing how traffic flows from the internet to a pod, and how configuration reaches a container, is everyday platform work and a standard interview topic. So is the classic mistake of thinking Kubernetes Secrets are encrypted: auditors and security teams will ask how you protect them.

## 1. Services: a stable address for changing pods

Pods come and go, and each new pod gets a new IP. A **Service** gives a fixed name and virtual IP, and load-balances across whichever pods match its **selector** and are **Ready**:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: itlpay
  namespace: itlpay
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: itlpay     # every Ready pod with this label
  ports:
    - name: http
      port: 80                         # what clients call
      targetPort: http                 # the container's named port (8080)
```

```bash
kubectl -n itlpay get endpointslices -l kubernetes.io/service-name=itlpay   # the pod IPs behind the Service
```

An **empty endpoint list** is the first thing to check when a Service doesn't answer: either the selector matches no pods, or none is Ready.

| Type | Reachable from | Use it for |
| --- | --- | --- |
| **ClusterIP** (default) | Inside the cluster only | Almost every Service |
| **NodePort** | Every node's IP on a high port (30000–32767) | Rarely directly; load balancers use it underneath |
| **LoadBalancer** | The internet or your VPC, through a cloud load balancer the cluster creates | Non-HTTP traffic (TCP/UDP), or a quick test. One load balancer per Service gets expensive |
| **Headless** (`clusterIP: None`) | DNS returns the pod IPs directly | StatefulSets: `postgres-0.postgres` always means the same pod (topic 9.3) |

## 2. DNS inside the cluster

CoreDNS gives every Service a name:

```text
itlpay                                   from a pod in the same namespace
itlpay.itlpay                            <service>.<namespace>, from any namespace
itlpay.itlpay.svc.cluster.local          the full name
```

That's why the database URL is simply `postgresql://itlpay:...@postgres:5432/itlpay`. To test from inside:

```bash
kubectl -n itlpay run tmp --rm -it --restart=Never --image=curlimages/curl:8.11.1 \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65534,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"tmp","image":"curlimages/curl:8.11.1","args":["-s","http://itlpay/health"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
```

(The long `--overrides` is the price of the restricted Pod Security level from topic 9.1; the chart's `helm test` in topic 9.4 does the same check more neatly.)

## 3. Traffic from outside: the Gateway API

For HTTP, you don't want one cloud load balancer per Service. You want **one entry point** that routes by host name and path, terminates TLS, and sends requests to the right Service. Kubernetes has two APIs for this:

- **Ingress**: the original, simple API. Its behaviour beyond basic routing lives in controller-specific annotations, so an Ingress written for one controller rarely works on another. The most widely used controller, the community **ingress-nginx**, was **retired in March 2026**: no more releases or security fixes. You'll still meet Ingress in existing clusters, and need to read it and plan migrations.
- **Gateway API**: the successor, part of Kubernetes since 2023 and implemented by all three clouds' load balancers. It splits responsibility by role:

```text
GatewayClass   which implementation (the cloud's load balancer)            → set up once by the cluster's owner
Gateway        an entry point: listeners, ports, TLS certificates          → owned by the platform team
HTTPRoute      "itlpay.example.com, path / → Service itlpay port 80"       → owned by the application team
```

The lab's route (`manifests/40-gateway.yaml`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: itlpay
  namespace: itlpay
spec:
  parentRefs:
    - name: public                  # the shared Gateway...
      namespace: gateway            # ...in the platform team's namespace
  hostnames: ["itlpay.example.com"]
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
      backendRefs:
        - name: itlpay
          port: 80
```

HTTPRoutes can also split traffic by weight (`backendRefs` with `weight: 90` and `weight: 10`), which is how canary releases work (Phase 3).

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Gateway API implementation | AWS Load Balancer Controller (an ALB per Gateway) | Application Gateway for Containers | GKE Gateway controller (Google's Application Load Balancers) |
| Ingress controllers you'll meet | AWS Load Balancer Controller with Ingress | Application Gateway Ingress Controller, the AKS application routing add-on | GKE Ingress |

The equivalent Ingress, for reading older clusters:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: itlpay
spec:
  ingressClassName: alb             # which controller
  rules:
    - host: itlpay.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: itlpay, port: { name: http } }
```

## 4. ConfigMaps: settings

Same image, different settings per environment (the twelve-factor rule from topic 5.3):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: itlpay
  namespace: itlpay
data:
  APP_ENV: dev
  LOG_LEVEL: INFO
```

Pass them in as environment variables (`envFrom: configMapRef`, as the lab does) or mount them as files (for config files such as `nginx.conf`). Two things to remember:

- Environment variables are read **once, at start**. Changing the ConfigMap doesn't change running pods; you must roll them. The Helm chart (topic 9.4) does this automatically with a `checksum/config` annotation.
- Mounted files do update (after a short delay), but only if the app re-reads them.

## 5. Secrets: passwords, keys and tokens

```bash
kubectl -n itlpay create secret generic itlpay-db \
  --from-literal=DATABASE_URL="postgresql://itlpay:$pw@postgres:5432/itlpay"
kubectl -n itlpay get secret itlpay-db -o yaml          # data: DATABASE_URL: cG9zdGdyZXNxbDov...
```

The value is **base64-encoded, not encrypted**: `base64 -d` reveals it. What actually protects a Secret:

| Protection | How |
| --- | --- |
| Who can read it | **RBAC**: only the app's service account and a few admins should `get secrets` in the namespace. Anyone who can create a pod in the namespace can also read its Secrets, by mounting them |
| Encryption at rest in etcd | EKS (envelope encryption with KMS, on by default), AKS (KMS etcd encryption with Key Vault, an option) and GKE (application-layer encryption with Cloud KMS, an option) |
| Not in Git | Never commit a Secret manifest. Create it from the cloud's secret store instead: **External Secrets Operator** (topic 10.2), or encrypt it for Git with Sealed Secrets or SOPS |
| Not in logs | Don't print environment variables at start-up; `kubectl describe pod` shows Secret names, not values |

The lab creates Secrets with `kubectl create secret` from values you never write down, and topic 10.2 replaces even that with AWS Secrets Manager, Azure Key Vault and Google Secret Manager.

## Practice

1. Change the Service's selector to a label no pod has. Show the empty endpoint list, and the error `curl` gets. Fix it.
2. From a temporary pod, call the API by its short name, its `<service>.<namespace>` name and its full name.
3. Change `LOG_LEVEL` to `DEBUG` in the ConfigMap and re-apply. Does the running API log more? Make it take effect without editing the Deployment (`kubectl rollout restart`).
4. Decode the `itlpay-db` Secret with `kubectl get secret ... -o jsonpath` and `base64 -d`. Write two sentences for your learning log on why this is fine for an admin and dangerous for everyone else.
5. Install a Gateway API implementation on kind (for example Envoy Gateway, following its quick start), create a Gateway named `public` in namespace `gateway`, apply `40-gateway.yaml`, and reach the API through it with `curl -H 'Host: itlpay.example.com'`.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Kubernetes Services explained | ClusterIP vs NodePort vs LoadBalancer vs Headless Service](https://www.youtube.com/watch?v=T4Z7visMM4E) · TechWorld with Nana · 24 min. ClusterIP, NodePort, LoadBalancer and headless Services.
- [The Differences between Ingress & Gateway API](https://www.youtube.com/watch?v=GhIrz-V9X6k) · That DevOps Guy · 17 min. How the Gateway API differs from Ingress.
- [Kubernetes ConfigMap and Secret as Kubernetes Volumes | Demo](https://www.youtube.com/watch?v=FAnQTgr04mU) · TechWorld with Nana · 17 min. ConfigMaps and Secrets, as variables and as files.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Configure applications on Azure Kubernetes Service](https://learn.microsoft.com/training/modules/configure-apps-azure-kubernetes-service/)
- [Deploy applications to Azure Kubernetes Service](https://learn.microsoft.com/training/modules/deploy-applications-azure-kubernetes-service/)

**AWS (AWS Skill Builder):**

- [Introduction to Kubernetes Core Concepts](https://skillbuilder.aws/learn/U4Z3BPGK9Y/introduction-to-kubernetes-core-concepts/DZCQ4QTSJT)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Architecting with Google Kubernetes Engine: Workloads](https://www.skills.google/course_templates/34)
- [Configure Google Kubernetes Engine Networking](https://www.skills.google/course_templates/660)

