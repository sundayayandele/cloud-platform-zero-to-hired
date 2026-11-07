## What you will be able to do

- Explain cloud security posture management (CSPM), threat detection and runtime security, and how they fit with what you built in earlier modules.
- Turn on and read AWS Security Hub with GuardDuty, Microsoft Defender for Cloud, and Google Security Command Center.
- Use benchmarks (CIS, the clouds' own) to find misconfigurations, and prioritise findings by real risk.
- Scan your own configuration in CI with Trivy, and know kube-bench for cluster benchmarks.
- Detect suspicious behaviour inside running containers with Falco.
- Design identity boundaries (accounts, subscriptions, projects) that limit the damage of a breach.

## Why this matters at work

Most cloud breaches don't start with a clever exploit; they start with a misconfiguration: a public bucket, an over-powerful role, a forgotten access key, an open port. The clouds' posture services find these in minutes, and security teams expect platform engineers to keep the findings down and fix them by default in code. Runtime detection catches what slips through. "How do you know your cloud is configured securely?" and "what would you do if a container was compromised?" are standard questions for platform, SRE and DevSecOps roles.

## 1. Layers of defence

You've been building security into every module. Here it is as layers, from earliest to latest:

| Layer | Stops or finds | Course |
| --- | --- | --- |
| Secure defaults in code | Problems before they exist | Terraform modules (7), golden path (14.1) |
| Checks on every change | Misconfigurations in pull requests | checkov (7.4), Trivy and actionlint (8), policy tests (14.3) |
| Supply chain | Vulnerable or tampered software | Image scanning, SBOMs, signatures (8.2), pinned actions |
| Identity | Stolen keys, too much access | OIDC and workload identity (8.3, 9.5), per-secret access (10.2) |
| Admission and guardrails | Unsafe workloads and resources | Pod Security (9.1), Kyverno, organisation policies (14.3) |
| **Posture management** | Misconfigurations in what's running | **This topic** |
| **Threat and runtime detection** | Attacks in progress | **This topic** |
| Audit and response | Who did what; how to recover | Audit logs (15.2), incidents (13.2), backups (13.4) |

No single layer is enough; each catches what the others miss.

## 2. The clouds' posture and threat services

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Posture (misconfigurations against benchmarks) | **Security Hub** CSPM: AWS Foundational Security Best Practices, CIS | **Microsoft Defender for Cloud**: secure score and recommendations against the Microsoft cloud security benchmark (Foundational CSPM is free) | **Security Command Center**: Security Health Analytics |
| Threat detection | **GuardDuty** (from CloudTrail, VPC flow logs, DNS; EKS and runtime monitoring add-ons) | **Defender plans** per resource type (servers, containers, storage, databases, Key Vault) | SCC **Event Threat Detection** and Container Threat Detection (Premium) |
| Kubernetes | GuardDuty EKS protection and runtime monitoring | Defender for Containers | GKE security posture dashboard; Container Threat Detection |
| Organisation-wide | Delegated administrator for the organisation | Management group scope | Organisation-level activation |

`labs/security/posture/README.md` has the commands to turn on the basic tiers. Check prices first: posture is free or cheap; threat protection is charged per resource.

**Prioritising findings.** A new account often shows hundreds of findings. Fix in this order:

1. **Exposed to the internet and sensitive**: public storage with data, open admin ports, databases with public IPs.
2. **Identity**: root or owner accounts without MFA, long-lived access keys, wildcard permissions.
3. **Detection gaps**: audit logging off, GuardDuty or Defender off in some regions.
4. Everything else, **fixed in code** (the Terraform module or the golden path), so it doesn't come back.

Suppress a finding only with a written reason, as with checkov skips in topic 7.4.

## 3. Scanning your own configuration: Trivy

**Trivy** scans images (topic 8.2), and also **configuration**: Kubernetes YAML, Helm charts, Terraform, Dockerfiles. The course's CI scans its own manifests, the ITL Pay chart and the GitOps base, and fails on any HIGH or CRITICAL finding:

```bash
trivy config --severity HIGH,CRITICAL --exit-code 1 labs/kubernetes/manifests
trivy config --severity HIGH,CRITICAL --exit-code 1 labs/kubernetes/chart/itlpay
trivy config --severity HIGH,CRITICAL --exit-code 1 labs/gitops/kustomize/base
```

The first run found one HIGH finding, in the course's own lab: the PostgreSQL StatefulSet didn't set `readOnlyRootFilesystem: true` (KSV-0014), so an attacker who got into the database container could change its files. ITL Pay itself was clean. The fix was a read-only root file system, with writable volumes only where PostgreSQL needs them (its data, its socket directory and `/tmp`), in Module 9's manifest and the Crossplane composition; the course's Kubernetes, backup and platform tests then proved PostgreSQL still works. That's the loop to aim for: scan, fix in code, prove nothing broke.

Remember Trivy's own supply-chain incident (topic 8.2): the CI pins Trivy 0.76.1, an immutable GitHub release, and checks the download against the release's checksums before running it. Treat security tools with the same care as anything else in your pipeline.

For the cluster itself, **kube-bench** checks nodes and the control plane against the **CIS Kubernetes Benchmark**. On EKS, AKS and GKE the control plane is managed, so run the provider-specific benchmark profiles (CIS EKS, AKS and GKE benchmarks) and focus on the node and workload sections.

## 4. Runtime detection: Falco

Posture tools look at configuration; **Falco** (a graduated CNCF project) watches what containers actually **do**, by observing system calls on each node with eBPF. Its default rules flag behaviour that rarely has a good reason in production: a shell started in a container, sensitive files read (`/etc/shadow`), binaries written into containers, unexpected outbound connections, privilege changes.

`labs/security/runtime/kind-falco-test.sh`, run by the course's CI, installs Falco 0.45 on kind with JSON output, starts a pod, reads `/etc/shadow` inside it as an attacker would, and checks Falco raised a **Read sensitive file untrusted** alert naming the pod.

The test pod runs in an unrestricted namespace on purpose. In the `itlpay` namespace, the restricted Pod Security level (topic 9.1) would have refused a root pod in the first place: prevention first, detection as the second line.

In production, send Falco's alerts (with Falcosidekick) to your alerting and SIEM (topic 11.2), route the critical ones to the on-call engineer (topic 13.2), and tune rules for your workloads so alerts stay rare and meaningful. The clouds' container threat detection (GuardDuty runtime monitoring, Defender for Containers, Container Threat Detection) offers the same idea as a managed service.

## 5. Identity boundaries

The strongest security boundary in each cloud is the **account, subscription or project**: separate ones for production, non-production, security tooling and log archives limit what a single compromised identity can reach.

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Boundary | Accounts in AWS Organizations (often set up with Control Tower) | Subscriptions under management groups (landing zones) | Projects under folders in an organisation |
| Guardrails above it | SCPs and resource control policies (topic 14.3) | Azure Policy | Organisation policies |
| Human access | IAM Identity Center (SSO) with short sessions; no IAM users for people | Microsoft Entra ID with Privileged Identity Management (just-in-time admin) | Cloud Identity / Google Workspace with groups; no service account keys |

Rules that hold on all three: no long-lived keys for people or pipelines (topics 8.3 and 9.5), MFA everywhere, admin rights only when needed (just-in-time), and a break-glass account that's monitored and rarely used.

## Practice

1. Turn on the free posture tier on one cloud (Security Hub with the foundational standard, Defender for Cloud's foundational CSPM, or Security Command Center Standard). Fix the three highest-priority findings, **in Terraform**, and record the before and after.
2. Run `trivy config` against your Capstone 2 repository. Fix each HIGH finding or record a justified exception.
3. Run `kind-falco-test.sh`, then trigger the "Terminal shell in container" rule with `kubectl exec -it`. Read the alert and say what an on-call engineer should do next.
4. Run kube-bench as a Job on kind (`kubectl apply -f job.yaml` from its repository), and explain three FAIL results and whether they matter on a managed service.
5. Draw the account, subscription or project layout you'd recommend for ITL Pay on one cloud, with what runs where and who can access it.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [What is CSPM (Cloud Security Posture Management)?](https://www.youtube.com/watch?v=V4wmb5KVmKM) · IBM Technology · 5 min. What cloud security posture management is.
- [AWS Security Hub Demo | Amazon Web Services](https://www.youtube.com/watch?v=nBusvrDEjdk) · Amazon Web Services · 5 min. AWS Security Hub, demonstrated by AWS.
- [Manage cloud security posture with Microsoft Defender for Cloud](https://www.youtube.com/watch?v=nE6tFjP7Juc) · Microsoft Security · 5 min. Managing posture with Microsoft Defender for Cloud.
- [What is Security Command Center?](https://www.youtube.com/watch?v=oL8nB5GHbd0) · Google Cloud Tech · 6 min. Google Cloud Tech on Security Command Center.
- [Falco for Kubernetes runtime security (eBPF, Rules, Tuning & Alerts)](https://www.youtube.com/watch?v=C8ephsD1_fM) · Sysdig · 9 min. Falco for Kubernetes runtime security: eBPF, rules and tuning.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Manage your cloud security posture management](https://learn.microsoft.com/training/modules/manage-cloud-security-posture-management/)
- [Enable Defender for Cloud on your Azure subscription](https://learn.microsoft.com/training/modules/enable-defender-cloud-azure-subscription/)
- [Remediate security alerts using Microsoft Defender for Cloud](https://learn.microsoft.com/training/modules/remediate-azure-defender-security-alerts/)

**AWS (AWS Skill Builder):**

- [AWS Security Hub CSPM Getting Started](https://skillbuilder.aws/learn/YJ5XKSDUNA/aws-security-hub-cspm-getting-started/JWRKYBXUXG)
- [Build with AWS Security Hub CSPM](https://skillbuilder.aws/learn/NJY3XVH2XW/build-with-aws-security-hub-cspm/B1YWZ2T3YS)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Manage Security in Google Cloud](https://www.skills.google/course_templates/21)
- [Security & Identity Fundamentals](https://www.skills.google/course_templates/770)

