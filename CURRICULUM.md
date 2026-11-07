# Cloud & Platform Engineer: Zero to Hired: full curriculum

AWS, Azure and Google Cloud are taught side by side in every phase: the idea first, then the same task on each cloud with the same checks, then a short comparison. Terraform is the main infrastructure tool for all three.

## Phase 1: Cloud Foundations (weeks 1–14)

Linux, networking, Bash and Python, Git, containers, and the foundations of AWS, Azure and Google Cloud side by side. Capstone 1 deploys ITL Pay on all three clouds.

Certification targets: AWS Certified Cloud Practitioner; Microsoft Azure Fundamentals (AZ-900); Google Cloud Digital Leader.

### Module 1: Linux and the command line (weeks 1–2)

| Topic | Week | Status |
| --- | --- | --- |
| [1.1 Your lab: a terminal, a Linux machine and how this course works](phases/01-cloud-foundations/01-linux-and-the-command-line/1.1-your-lab-a-terminal-a-linux-machine/lesson.md) | 1 | Written |
| [1.2 Files, directories, text and pipes](phases/01-cloud-foundations/01-linux-and-the-command-line/1.2-files-directories-text-and-pipes/lesson.md) | 1 | Written |
| [1.3 Users, groups, permissions and sudo](phases/01-cloud-foundations/01-linux-and-the-command-line/1.3-users-groups-permissions-and-sudo/lesson.md) | 1 | Written |
| [1.4 Processes, services with systemd, and logs](phases/01-cloud-foundations/01-linux-and-the-command-line/1.4-processes-services-with-systemd-and-logs/lesson.md) | 2 | Written |
| [1.5 Packages, SSH keys and working on a remote server](phases/01-cloud-foundations/01-linux-and-the-command-line/1.5-packages-ssh-keys-and-working/lesson.md) | 2 | Written |

### Module 2: Networking for the cloud (weeks 3–4)

| Topic | Week | Status |
| --- | --- | --- |
| [2.1 How data moves: IP, TCP, UDP and ports](phases/01-cloud-foundations/02-networking-for-the-cloud/2.1-how-data-moves-ip-tcp-udp-and-ports/lesson.md) | 3 | Written |
| [2.2 Addresses and subnets: IPv4, CIDR and private ranges](phases/01-cloud-foundations/02-networking-for-the-cloud/2.2-addresses-and-subnets-ipv4-cidr/lesson.md) | 3 | Written |
| [2.3 DNS: how names become addresses](phases/01-cloud-foundations/02-networking-for-the-cloud/2.3-dns-how-names-become-addresses/lesson.md) | 3 | Written |
| [2.4 HTTP, HTTPS and TLS certificates](phases/01-cloud-foundations/02-networking-for-the-cloud/2.4-http-https-and-tls-certificates/lesson.md) | 4 | Written |
| [2.5 Routing, NAT, firewalls and load balancers](phases/01-cloud-foundations/02-networking-for-the-cloud/2.5-routing-nat-firewalls-and-load-balancers/lesson.md) | 4 | Written |
| [2.6 Troubleshooting a connection step by step](phases/01-cloud-foundations/02-networking-for-the-cloud/2.6-troubleshooting-a-connection-step/lesson.md) | 4 | Written |

### Module 3: Scripting and automation (weeks 5–6)

| Topic | Week | Status |
| --- | --- | --- |
| [3.1 Bash scripting: variables, conditions, loops and functions](phases/01-cloud-foundations/03-scripting-and-automation/3.1-bash-scripting-variables-conditions/lesson.md) | 5 | Written |
| [3.2 Safe scripts: quoting, errors and running twice](phases/01-cloud-foundations/03-scripting-and-automation/3.2-safe-scripts-quoting-errors-and-running/lesson.md) | 5 | Written |
| [3.3 Scheduling: cron and systemd timers](phases/01-cloud-foundations/03-scripting-and-automation/3.3-scheduling-cron-and-systemd-timers/lesson.md) | 5 | Written |
| [3.4 Python for operations: files, JSON and REST APIs](phases/01-cloud-foundations/03-scripting-and-automation/3.4-python-for-operations-files-json/lesson.md) | 6 | Written |
| [3.5 Testing your automation with pytest](phases/01-cloud-foundations/03-scripting-and-automation/3.5-testing-your-automation-with-pytest/lesson.md) | 6 | Written |

### Module 4: Git, GitHub and docs-as-code (weeks 7)

| Topic | Week | Status |
| --- | --- | --- |
| [4.1 Git and GitHub essentials](phases/01-cloud-foundations/04-git-github-and-docs-as-code/4.1-git-and-github-essentials/lesson.md) | 7 | Written |
| [4.2 Pull requests, code review and branch protection](phases/01-cloud-foundations/04-git-github-and-docs-as-code/4.2-pull-requests-code-review-and-branch/lesson.md) | 7 | Written |
| [4.3 Docs as code: READMEs, runbooks, diagrams and decision records](phases/01-cloud-foundations/04-git-github-and-docs-as-code/4.3-docs-as-code-readmes-runbooks-diagrams/lesson.md) | 7 | Written |

### Module 5: Containers (weeks 8–9)

| Topic | Week | Status |
| --- | --- | --- |
| [5.1 Containers: what they are and how to run them](phases/01-cloud-foundations/05-containers/5.1-containers-what-they-are-and-how-to-run/lesson.md) | 8 | Written |
| [5.2 Building images: Dockerfiles, layers and multi-stage builds](phases/01-cloud-foundations/05-containers/5.2-building-images-dockerfiles-layers/lesson.md) | 8 | Written |
| [5.3 Docker Compose: running ITL Pay on your laptop](phases/01-cloud-foundations/05-containers/5.3-docker-compose-running-itl-pay/lesson.md) | 9 | Written |
| [5.4 Registries and image security: GHCR, ECR and ACR](phases/01-cloud-foundations/05-containers/5.4-registries-and-image-security-ghcr-ecr/lesson.md) | 9 | Written |

### Module 6: Cloud foundations on AWS, Azure and Google Cloud (weeks 10–12)

| Topic | Week | Status |
| --- | --- | --- |
| [6.1 Cloud concepts, accounts, subscriptions and projects, regions, and billing guardrails](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.1-cloud-concepts-accounts/lesson.md) | 10 | Written |
| [6.2 Identity and access: AWS IAM, Entra ID with Azure RBAC, and Google Cloud IAM](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.2-identity-and-access-iam-and-entra-id/lesson.md) | 10 | Written |
| [6.3 The AWS, Azure and Google Cloud CLIs side by side](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.3-the-aws-cli-and-the-azure-cli-side/lesson.md) | 10 | Written |
| [6.4 Private networks: VPC, VNet and Google Cloud VPC](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.4-private-networks-vpc-and-vnet/lesson.md) | 11 | Written |
| [6.5 Virtual machines: EC2, Azure Virtual Machines and Compute Engine](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.5-virtual-machines-ec2-and-azure-virtual/lesson.md) | 11 | Written |
| [6.6 Object storage: S3, Blob Storage and Cloud Storage](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.6-object-storage-s3-and-blob-storage/lesson.md) | 11 | Written |
| [6.7 Managed PostgreSQL: RDS, Azure Database for PostgreSQL and Cloud SQL](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.7-managed-postgresql-rds-and-azure/lesson.md) | 12 | Written |
| [6.8 Load balancers, DNS and HTTPS on all three clouds](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.8-load-balancers-dns-and-https-on-both/lesson.md) | 12 | Written |
| [6.9 Monitoring, logs and alerts: CloudWatch, Azure Monitor and Cloud Monitoring](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.9-monitoring-logs-and-alerts-cloudwatch/lesson.md) | 12 | Written |

### [Capstone 1 (weeks 13–14): ITL Pay on AWS, Azure and Google Cloud, by hand then by script](phases/01-cloud-foundations/capstone-1/README.md)

## Phase 2: DevOps and Infrastructure as Code (weeks 15–25)

Terraform on all three clouds, CI/CD with keyless login, Kubernetes and Helm (EKS, AKS and GKE), secrets and observability. Capstone 2: pipeline to production across three clouds.

Certification targets: AWS Certified Solutions Architect – Associate, Microsoft Azure Administrator (AZ-104) or Google Cloud Associate Cloud Engineer; HashiCorp Terraform Associate.

### Module 7: Terraform on AWS, Azure and Google Cloud (weeks 15–17)

| Topic | Week | Status |
| --- | --- | --- |
| [7.1 Infrastructure as code and your first Terraform](phases/02-devops-iac/07-terraform-on-aws-and-azure/7.1-infrastructure-as-code-and-your-first/lesson.md) | 15 | Written |
| [7.2 Variables, outputs, data sources and modules](phases/02-devops-iac/07-terraform-on-aws-and-azure/7.2-variables-outputs-data-sources/lesson.md) | 15 | Written |
| [7.3 State: remote backends, locking and environments](phases/02-devops-iac/07-terraform-on-aws-and-azure/7.3-state-remote-backends-locking/lesson.md) | 16 | Written |
| [7.4 Quality gates: fmt, validate, tflint, checkov and plan review](phases/02-devops-iac/07-terraform-on-aws-and-azure/7.4-quality-gates-fmt-validate-tflint/lesson.md) | 16 | Written |
| [7.5 Drift, imports and refactoring safely](phases/02-devops-iac/07-terraform-on-aws-and-azure/7.5-drift-imports-and-refactoring-safely/lesson.md) | 17 | Written |
| [7.6 Reading CloudFormation and Bicep](phases/02-devops-iac/07-terraform-on-aws-and-azure/7.6-reading-cloudformation-and-bicep/lesson.md) | 17 | Written |

### Module 8: CI/CD with GitHub Actions (weeks 18–19)

| Topic | Week | Status |
| --- | --- | --- |
| [8.1 Pipelines in depth: jobs, runners, caching and reuse](phases/02-devops-iac/08-ci-cd-with-github-actions/8.1-pipelines-in-depth-jobs-runners-caching/lesson.md) | 18 | Written |
| [8.2 Build, scan, sign and publish images with an SBOM](phases/02-devops-iac/08-ci-cd-with-github-actions/8.2-build-scan-sign-and-publish-images/lesson.md) | 18 | Written |
| [8.3 Keyless login from GitHub to AWS, Azure and Google Cloud with OIDC](phases/02-devops-iac/08-ci-cd-with-github-actions/8.3-keyless-login-from-github-to-aws/lesson.md) | 19 | Written |
| [8.4 Terraform in the pipeline: environments and approvals](phases/02-devops-iac/08-ci-cd-with-github-actions/8.4-terraform-in-the-pipeline-environments/lesson.md) | 19 | Written |

### Module 9: Kubernetes and Helm on EKS, AKS and GKE (weeks 20–21)

| Topic | Week | Status |
| --- | --- | --- |
| [9.1 Kubernetes architecture and your first workloads](phases/02-devops-iac/09-kubernetes-and-helm-on-eks-and-aks/9.1-kubernetes-architecture-and-your-first/lesson.md) | 20 | Written |
| [9.2 Services, Ingress, ConfigMaps and Secrets](phases/02-devops-iac/09-kubernetes-and-helm-on-eks-and-aks/9.2-services-ingress-configmaps-and-secrets/lesson.md) | 20 | Written |
| [9.3 Probes, resources, autoscaling and storage](phases/02-devops-iac/09-kubernetes-and-helm-on-eks-and-aks/9.3-probes-resources-autoscaling-and-storage/lesson.md) | 21 | Written |
| [9.4 Packaging with Helm](phases/02-devops-iac/09-kubernetes-and-helm-on-eks-and-aks/9.4-packaging-with-helm/lesson.md) | 21 | Written |
| [9.5 EKS, AKS and GKE: networking, identity for pods and upgrades](phases/02-devops-iac/09-kubernetes-and-helm-on-eks-and-aks/9.5-eks-and-aks-networking-identity-for-pods/lesson.md) | 21 | Written |

### Module 10: Configuration and secrets (weeks 22)

| Topic | Week | Status |
| --- | --- | --- |
| [10.1 Configuration management with Ansible](phases/02-devops-iac/10-configuration-and-secrets/10.1-configuration-management-with-ansible/lesson.md) | 22 | Written |
| [10.2 Secrets in the cloud: Secrets Manager, Key Vault, Secret Manager and External Secrets](phases/02-devops-iac/10-configuration-and-secrets/10.2-secrets-in-the-cloud-secrets-manager-key/lesson.md) | 22 | Written |

### Module 11: Observability (weeks 23)

| Topic | Week | Status |
| --- | --- | --- |
| [11.1 Metrics and alerts with Prometheus and Grafana](phases/02-devops-iac/11-observability/11.1-metrics-and-alerts-with-prometheus/lesson.md) | 23 | Written |
| [11.2 Logs and traces: Loki, OpenTelemetry and the clouds' own tools](phases/02-devops-iac/11-observability/11.2-logs-and-traces-loki-opentelemetry/lesson.md) | 23 | Written |

### [Capstone 2 (weeks 24–25): Pipeline to production across three clouds](phases/02-devops-iac/capstone-2/README.md)

## Phase 3: Platform Engineering and SRE (weeks 26–35)

GitOps, reliability targets and incident response, a self-service platform that deploys to any of the three clouds, cloud security, FinOps and AI for operations. Capstone 3: run a three-cloud platform.

Certification targets: Certified Kubernetes Administrator (CKA); optionally AWS Certified DevOps Engineer – Professional, Microsoft Azure DevOps Engineer Expert (AZ-400) or Google Cloud Professional Cloud DevOps Engineer.

### Module 12: GitOps and progressive delivery (weeks 26–27)

| Topic | Week | Status |
| --- | --- | --- |
| [12.1 GitOps with Argo CD and Kustomize](phases/03-platform-sre/12-gitops-and-progressive-delivery/12.1-gitops-with-argo-cd-and-kustomize/lesson.md) | 26 | Written |
| [12.2 Canary releases with Argo Rollouts and automatic rollback](phases/03-platform-sre/12-gitops-and-progressive-delivery/12.2-canary-releases-with-argo-rollouts/lesson.md) | 26 | Written |
| [12.3 One repository, three clusters: Argo CD across EKS, AKS and GKE](phases/03-platform-sre/12-gitops-and-progressive-delivery/12.3-one-repository-three-clusters/lesson.md) | 27 | Written |

### Module 13: Site reliability engineering (weeks 28–29)

| Topic | Week | Status |
| --- | --- | --- |
| [13.1 Reliability in practice: SLO policy, toil and capacity](phases/03-platform-sre/13-site-reliability-engineering/13.1-reliability-in-practice-slo-policy-toil/lesson.md) | 28 | Written |
| [13.2 Incident response, on-call and blameless post-mortems](phases/03-platform-sre/13-site-reliability-engineering/13.2-incident-response-on-call-post-mortems/lesson.md) | 28 | Written |
| [13.3 Chaos engineering: AWS FIS, Azure Chaos Studio and Chaos Mesh](phases/03-platform-sre/13-site-reliability-engineering/13.3-chaos-engineering-on-three-clouds/lesson.md) | 29 | Written |
| [13.4 Backup and disaster recovery across clouds](phases/03-platform-sre/13-site-reliability-engineering/13.4-backup-and-disaster-recovery-across-clouds/lesson.md) | 29 | Written |

### Module 14: Platform engineering (weeks 30–31)

| Topic | Week | Status |
| --- | --- | --- |
| [14.1 Developer platforms and golden paths with Backstage](phases/03-platform-sre/14-platform-engineering/14.1-developer-platforms-and-golden-paths/lesson.md) | 30 | Written |
| [14.2 Self-service infrastructure: Crossplane and Terraform modules](phases/03-platform-sre/14-platform-engineering/14.2-self-service-infrastructure/lesson.md) | 30 | Written |
| [14.3 Policy as code: Kyverno, OPA and the clouds' organisation policies](phases/03-platform-sre/14-platform-engineering/14.3-policy-as-code/lesson.md) | 31 | Written |

### Module 15: Cloud security and compliance (week 32)

| Topic | Week | Status |
| --- | --- | --- |
| 15.1 Security posture: Security Hub, Defender for Cloud and Security Command Center | 32 | Coming next |
| 15.2 Audit, compliance and data residency in Africa | 32 | Coming next |

### Module 16: FinOps and choosing a cloud (week 33)

| Topic | Week | Status |
| --- | --- | --- |
| 16.1 Cost visibility and optimisation with OpenCost and the clouds' tools | 33 | Coming next |
| 16.2 Comparing the same system on three clouds | 33 | Coming next |

### Module 17: AI for operations (week 33)

| Topic | Week | Status |
| --- | --- | --- |
| 17.1 AI assistants in operations, safely | 33 | Coming next |
| 17.2 Running AI workloads: GPUs, model serving, Bedrock, Azure OpenAI and Vertex AI | 33 | Coming next |

### Capstone 3 (weeks 34–35): Run a three-cloud platform
