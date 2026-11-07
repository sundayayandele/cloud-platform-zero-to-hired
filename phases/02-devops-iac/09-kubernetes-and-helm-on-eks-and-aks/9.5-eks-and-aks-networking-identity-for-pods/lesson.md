## What you will be able to do

- Create a small cluster on **EKS**, **AKS** and **GKE**, connect `kubectl` to it, and delete it again.
- Explain how each cloud gives pods IP addresses, and what that means for subnet sizing.
- Bring traffic in through each cloud's Gateway API implementation.
- Give a pod its own cloud identity, without keys: **EKS Pod Identity**, **Microsoft Entra Workload ID** and **Workload Identity Federation for GKE**.
- Plan Kubernetes upgrades: version support windows, release channels, surge upgrades and PodDisruptionBudgets.
- Keep cluster costs under control while learning.

## Why this matters at work

The Kubernetes API is the same everywhere, but a cluster isn't just Kubernetes: it's the cloud's network, load balancers, identity and upgrade process around it. That's where most real platform work and most production incidents happen ("pods can't get IPs", "the pod can't read the bucket", "the upgrade is stuck draining a node"). Job adverts usually name a specific service (EKS, AKS or GKE), and being able to say how the three differ is a strong signal in interviews, especially for consultancies and multi-cloud companies.

## 1. Creating the clusters

For learning, create a cluster for a session and delete it afterwards: the control plane and nodes are billed by the hour. In production you'd create them with Terraform (Module 7's network modules, plus the community `terraform-aws-modules/eks`, `Azure/aks` and `terraform-google-modules/kubernetes-engine` modules), from the pipeline (Module 8).

**Amazon EKS** (with `eksctl`, AWS's official CLI for EKS):

```bash
eksctl create cluster --name itlpay-dev --region af-south-1 --enable-auto-mode
aws eks update-kubeconfig --name itlpay-dev --region af-south-1
kubectl get nodes        # Auto Mode starts nodes only when pods need them
```

**Azure AKS:**

```bash
az group create -n rg-itlpay-aks -l southafricanorth
az aks create -g rg-itlpay-aks -n itlpay-dev --tier free --node-count 2 --node-vm-size Standard_B2s \
  --network-plugin azure --network-plugin-mode overlay --network-dataplane cilium \
  --enable-oidc-issuer --enable-workload-identity --generate-ssh-keys
az aks get-credentials -g rg-itlpay-aks -n itlpay-dev
```

**Google GKE** (Autopilot: Google runs the nodes; you pay for the pods' requests):

```bash
gcloud container clusters create-auto itlpay-dev --region africa-south1
gcloud container clusters get-credentials itlpay-dev --region africa-south1
```

| | EKS | AKS | GKE |
| --- | --- | --- | --- |
| Control plane price | Per cluster-hour; much higher in "extended support" | Free tier (no SLA) or Standard tier per cluster-hour | Per cluster-hour, with a monthly free-tier credit covering one Autopilot or zonal cluster |
| "Run my nodes for me" | EKS Auto Mode | AKS Automatic | GKE Autopilot |
| Who can use `kubectl` | EKS access entries (IAM principals mapped to Kubernetes permissions) | Microsoft Entra ID with Kubernetes RBAC or Azure RBAC | Google IAM plus Kubernetes RBAC |

**Delete when you finish:** `eksctl delete cluster --name itlpay-dev --region af-south-1`; `az group delete -n rg-itlpay-aks`; `gcloud container clusters delete itlpay-dev --region africa-south1`. Then check the console for left-over load balancers and disks: anything created by a Service or PVC that you didn't delete first can outlive the cluster.

## 2. Pod networking

Every pod gets its own IP address. Where that address comes from differs, and it decides how big your subnets must be:

| | EKS (VPC CNI) | AKS (Azure CNI Overlay) | GKE (VPC-native) |
| --- | --- | --- | --- |
| Pod IPs come from | The **VPC subnet itself**: pods are first-class VPC addresses | A **private overlay range** (for example 10.244.0.0/16), separate from the VNet | A **secondary range** of the subnet (alias IPs) |
| Subnet sizing | Plan for nodes **and** pods: a /24 fills up fast. Use larger subnets or prefix delegation | Only nodes use VNet addresses: small subnets are fine | Plan the secondary range for the maximum pods |
| Reachable from the VPC directly | Yes | No (traffic leaves with the node's address) | Yes |
| Network policy | VPC CNI network policy (enable it) | Azure CNI powered by Cilium | Dataplane V2 (Cilium-based), on in Autopilot |

This is why topic 7.2's network modules use /20-sized subnets: an EKS cluster with a few hundred pods would exhaust a /24. "Pods stuck in `ContainerCreating` with *failed to assign an IP address*" on EKS is almost always a full subnet.

## 3. Traffic in: the Gateway on each cloud

The platform team installs or enables the cloud's Gateway API implementation and creates one shared `Gateway` named `public` in the `gateway` namespace (topic 9.2). Application teams then only add an HTTPRoute, which the chart does when `httpRoute.enabled` is true:

| | EKS | AKS | GKE |
| --- | --- | --- | --- |
| Implementation | AWS Load Balancer Controller (Helm chart; built into Auto Mode for load balancers) | Application Gateway for Containers (add-on or Helm) | GKE Gateway controller (built in) |
| What it creates | An Application Load Balancer | An Application Gateway for Containers | A Google Cloud Application Load Balancer |
| TLS certificates | ACM (topic 6.8) | Key Vault or cert-manager | Certificate Manager or Google-managed certificates |

```bash
helm upgrade --install itlpay chart/itlpay -n itlpay --create-namespace -f values/gke.yaml   # or eks.yaml, aks.yaml
kubectl -n itlpay get httproute itlpay -o yaml | grep -A5 "conditions"                     # Accepted: True, ResolvedRefs: True
```

On the clouds, ITL Pay uses the **managed database** from topic 6.7, not the lab's StatefulSet: create the `itlpay-db` Secret with that database's URL (and in topic 10.2, from the cloud's secret store).

## 4. Pod identity: cloud permissions without keys

Topic 8.3 let a **pipeline** sign in to the clouds without keys. The same problem exists inside the cluster: the External Secrets operator in topic 10.2 needs to read the secret store, and an app may need a bucket. The answer is again federation: the pod's **Kubernetes service account** is exchanged for a short-lived cloud credential.

**EKS Pod Identity:** an IAM role trusted by the EKS Pod Identity service, associated with a namespace and service account from outside the cluster:

```bash
aws iam create-role --role-name itlpay-pod --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{ "Effect": "Allow", "Principal": { "Service": "pods.eks.amazonaws.com" },
                  "Action": ["sts:AssumeRole", "sts:TagSession"] }]}'
aws eks create-pod-identity-association --cluster-name itlpay-dev \
  --namespace itlpay --service-account itlpay --role-arn arn:aws:iam::<account>:role/itlpay-pod
```

(Auto Mode includes the Pod Identity agent; on other clusters add the `eks-pod-identity-agent` add-on. The older **IRSA**, with a role ARN annotation on the service account, is still common in existing clusters.)

**Microsoft Entra Workload ID on AKS:** a user-assigned managed identity with a federated credential for the service account:

```bash
az identity create -g rg-itlpay-aks -n id-itlpay
issuer=$(az aks show -g rg-itlpay-aks -n itlpay-dev --query oidcIssuerProfile.issuerUrl -o tsv)
az identity federated-credential create -g rg-itlpay-aks --identity-name id-itlpay --name itlpay \
  --issuer "$issuer" --subject system:serviceaccount:itlpay:itlpay --audiences api://AzureADTokenExchange
```

The pod opts in with the service account annotation `azure.workload.identity/client-id` and the pod label `azure.workload.identity/use: "true"`: that's what `values/aks.yaml` sets.

**Workload Identity Federation for GKE** (on by default in Autopilot): grant IAM roles directly to the Kubernetes service account's principal:

```bash
gcloud projects add-iam-policy-binding PROJECT_ID --role roles/secretmanager.secretAccessor \
  --member "principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/itlpay/sa/itlpay"
```

| | EKS | AKS | GKE |
| --- | --- | --- | --- |
| Trust set up | Pod Identity association (outside the cluster) | Federated credential on a managed identity | IAM binding to the Kubernetes service account's principal |
| Chart changes | None | Service account annotation and pod label | None |
| Same idea as topic 8.3 | Yes: a short-lived token from a trusted issuer, exchanged for cloud credentials; no keys anywhere | | |

The lab's chart sets `automountToken: false` because ITL Pay itself doesn't call the clouds. A pod that uses workload identity needs its token: set `serviceAccount.automountToken: true` for that workload only.

## 5. Upgrades

Kubernetes releases three minor versions a year, and each cloud supports a version for a limited time:

| | EKS | AKS | GKE |
| --- | --- | --- | --- |
| Support window | About 14 months standard, then about 12 months of paid extended support | About 12 months; Long-Term Support available on the Premium tier | Release channels (Rapid, Regular, Stable, Extended) |
| Automatic upgrades | Auto Mode updates nodes; control plane upgrades you start | Auto-upgrade channels and planned maintenance windows | On by default, within maintenance windows and exclusions |

A safe upgrade, in order:

1. Read the Kubernetes release notes for **removed APIs** and check your manifests and charts (`kubeconform` against the new version, or the `pluto` tool).
2. Upgrade **dev first**, run the smoke tests, then staging, then production.
3. Upgrade the **control plane**, then the **nodes**: new nodes come up, old ones are cordoned and drained.
4. PodDisruptionBudgets and multiple replicas (topic 9.3) keep the app serving during the drains. A PDB that allows zero disruptions blocks the upgrade, so check `kubectl get pdb -A` first.
5. Upgrade add-ons (CNI, CoreDNS, the load balancer controller) to versions supported on the new Kubernetes version.

Falling behind is expensive: EKS charges much more per hour in extended support, and every cloud eventually upgrades unsupported clusters for you.

## Practice

Do this in one sitting per cloud, and delete the cluster at the end. Budget: a few dollars per cloud if you finish within two hours.

1. Create a cluster on each cloud as in section 1 and run `kubectl get nodes -o wide`. Record the node and pod IP ranges and match them to section 2.
2. Create a managed PostgreSQL database (or reuse Capstone 1's), create the `itlpay-db` Secret, and install the chart with that cloud's values file and your image from Module 8 (by digest). Run `helm test`.
3. Enable the cloud's Gateway implementation, create the `public` Gateway, and reach `/health` through it from your laptop.
4. Set up pod identity on one cloud, then prove it with a temporary pod using the `itlpay` service account (`aws sts get-caller-identity`, `az login --federated-token` or `gcloud auth list` in the matching CLI image).
5. Write a one-page comparison of the three for your portfolio: creation time, networking, identity, Gateway, upgrade policy and cost per hour, from your own measurements.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Amazon EKS Auto Mode | Fully Automated Kubernetes Clusters](https://www.youtube.com/watch?v=s9d61eYkGzs) · AWS Developers · 14 min. AWS on EKS Auto Mode.
- [EKS Pod Identity vs IRSA | Securely Connect Kubernetes Pods to AWS Services](https://www.youtube.com/watch?v=aUjJSorBE70) · Containers from the Couch · 5 min. EKS Pod Identity compared with IRSA, from AWS.
- [AKS Workload Identity - Quick Tutorial](https://www.youtube.com/watch?v=i2GobU0Wg48) · Azure Kubernetes Service (AKS) · 12 min. Workload identity on AKS, from the AKS team.
- [Introducing GKE Autopilot](https://www.youtube.com/watch?v=_JKsv2BtAnY) · Google Cloud Tech · 7 min. Google introduces GKE Autopilot.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Deploy an Azure Kubernetes Service cluster](https://learn.microsoft.com/training/modules/deploy-azure-kubernetes-service-cluster/)
- [Configure an Azure Kubernetes Service cluster](https://learn.microsoft.com/training/modules/configure-azure-kubernetes-service-cluster/)
- [Implement security controls for Azure Kubernetes Service](https://learn.microsoft.com/training/modules/implement-security-controls-kubernetes/)

**AWS (AWS Skill Builder):**

- [Amazon Elastic Kubernetes Service (EKS) Getting Started](https://skillbuilder.aws/learn/MHH12MUT32/amazon-elastic-kubernetes-service-eks-getting-started/41CC6FD698)
- [Why run your Kubernetes workloads on Amazon EKS?](https://skillbuilder.aws/learn/6MCV5DBF5N/why-run-your-kubernetes-workloads-on-amazons-elastic-kubernetes-service-eks/W4BB5XPWB8)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Architecting with Google Kubernetes Engine: Foundations](https://www.skills.google/course_templates/32)
- [Google Kubernetes Engine Best Practices: Security](https://www.skills.google/course_templates/732)
- [Manage Kubernetes in Google Cloud (skill badge)](https://www.skills.google/course_templates/783)

