# Cloud & Platform Engineer: Zero to Hired: full curriculum

AWS and Azure are taught side by side in every phase: the idea first, then the same task on each cloud with the same checks, then a short comparison. Terraform is the main infrastructure tool for both.

## Phase 1: Cloud Foundations (weeks 1–13)

Linux, networking, Bash and Python, Git, containers, and the foundations of AWS and Azure side by side. Capstone 1 deploys ITL Pay on both clouds.

Certification targets: AWS Certified Cloud Practitioner and Microsoft Azure Fundamentals (AZ-900).

### Module 1: Linux and the command line (weeks 1–2)

| Topic | Week |
| --- | --- |
| [1.1 Your lab: a terminal, a Linux machine and how this course works](phases/01-cloud-foundations/01-linux-and-the-command-line/1.1-your-lab-a-terminal-a-linux-machine/lesson.md) | 1 |
| [1.2 Files, directories, text and pipes](phases/01-cloud-foundations/01-linux-and-the-command-line/1.2-files-directories-text-and-pipes/lesson.md) | 1 |
| [1.3 Users, groups, permissions and sudo](phases/01-cloud-foundations/01-linux-and-the-command-line/1.3-users-groups-permissions-and-sudo/lesson.md) | 1 |
| [1.4 Processes, services with systemd, and logs](phases/01-cloud-foundations/01-linux-and-the-command-line/1.4-processes-services-with-systemd-and-logs/lesson.md) | 2 |
| [1.5 Packages, SSH keys and working on a remote server](phases/01-cloud-foundations/01-linux-and-the-command-line/1.5-packages-ssh-keys-and-working/lesson.md) | 2 |

### Module 2: Networking for the cloud (weeks 3–4)

| Topic | Week |
| --- | --- |
| [2.1 How data moves: IP, TCP, UDP and ports](phases/01-cloud-foundations/02-networking-for-the-cloud/2.1-how-data-moves-ip-tcp-udp-and-ports/lesson.md) | 3 |
| [2.2 Addresses and subnets: IPv4, CIDR and private ranges](phases/01-cloud-foundations/02-networking-for-the-cloud/2.2-addresses-and-subnets-ipv4-cidr/lesson.md) | 3 |
| [2.3 DNS: how names become addresses](phases/01-cloud-foundations/02-networking-for-the-cloud/2.3-dns-how-names-become-addresses/lesson.md) | 3 |
| [2.4 HTTP, HTTPS and TLS certificates](phases/01-cloud-foundations/02-networking-for-the-cloud/2.4-http-https-and-tls-certificates/lesson.md) | 4 |
| [2.5 Routing, NAT, firewalls and load balancers](phases/01-cloud-foundations/02-networking-for-the-cloud/2.5-routing-nat-firewalls-and-load-balancers/lesson.md) | 4 |
| [2.6 Troubleshooting a connection step by step](phases/01-cloud-foundations/02-networking-for-the-cloud/2.6-troubleshooting-a-connection-step/lesson.md) | 4 |

### Module 3: Scripting and automation (weeks 5–6)

| Topic | Week |
| --- | --- |
| [3.1 Bash scripting: variables, conditions, loops and functions](phases/01-cloud-foundations/03-scripting-and-automation/3.1-bash-scripting-variables-conditions/lesson.md) | 5 |
| [3.2 Safe scripts: quoting, errors and running twice](phases/01-cloud-foundations/03-scripting-and-automation/3.2-safe-scripts-quoting-errors-and-running/lesson.md) | 5 |
| [3.3 Scheduling: cron and systemd timers](phases/01-cloud-foundations/03-scripting-and-automation/3.3-scheduling-cron-and-systemd-timers/lesson.md) | 5 |
| [3.4 Python for operations: files, JSON and REST APIs](phases/01-cloud-foundations/03-scripting-and-automation/3.4-python-for-operations-files-json/lesson.md) | 6 |
| [3.5 Testing your automation with pytest](phases/01-cloud-foundations/03-scripting-and-automation/3.5-testing-your-automation-with-pytest/lesson.md) | 6 |

### Module 4: Git, GitHub and docs-as-code (weeks 7)

| Topic | Week |
| --- | --- |
| [4.1 Git and GitHub essentials](phases/01-cloud-foundations/04-git-github-and-docs-as-code/4.1-git-and-github-essentials/lesson.md) | 7 |
| [4.2 Pull requests, code review and branch protection](phases/01-cloud-foundations/04-git-github-and-docs-as-code/4.2-pull-requests-code-review-and-branch/lesson.md) | 7 |
| [4.3 Docs as code: READMEs, runbooks, diagrams and decision records](phases/01-cloud-foundations/04-git-github-and-docs-as-code/4.3-docs-as-code-readmes-runbooks-diagrams/lesson.md) | 7 |

### Module 5: Containers (weeks 8–9)

| Topic | Week |
| --- | --- |
| [5.1 Containers: what they are and how to run them](phases/01-cloud-foundations/05-containers/5.1-containers-what-they-are-and-how-to-run/lesson.md) | 8 |
| [5.2 Building images: Dockerfiles, layers and multi-stage builds](phases/01-cloud-foundations/05-containers/5.2-building-images-dockerfiles-layers/lesson.md) | 8 |
| [5.3 Docker Compose: running ITL Pay on your laptop](phases/01-cloud-foundations/05-containers/5.3-docker-compose-running-itl-pay/lesson.md) | 9 |
| [5.4 Registries and image security: GHCR, ECR and ACR](phases/01-cloud-foundations/05-containers/5.4-registries-and-image-security-ghcr-ecr/lesson.md) | 9 |

### Module 6: Cloud foundations on AWS and Azure (weeks 10–12)

| Topic | Week |
| --- | --- |
| [6.1 Cloud concepts, accounts and subscriptions, regions, and billing guardrails](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.1-cloud-concepts-accounts/lesson.md) | 10 |
| [6.2 Identity and access: IAM, and Entra ID with Azure RBAC](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.2-identity-and-access-iam-and-entra-id/lesson.md) | 10 |
| [6.3 The AWS CLI and the Azure CLI side by side](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.3-the-aws-cli-and-the-azure-cli-side/lesson.md) | 10 |
| [6.4 Private networks: VPC and VNet](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.4-private-networks-vpc-and-vnet/lesson.md) | 11 |
| [6.5 Virtual machines: EC2 and Azure Virtual Machines](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.5-virtual-machines-ec2-and-azure-virtual/lesson.md) | 11 |
| [6.6 Object storage: S3 and Blob Storage](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.6-object-storage-s3-and-blob-storage/lesson.md) | 11 |
| [6.7 Managed PostgreSQL: RDS and Azure Database for PostgreSQL](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.7-managed-postgresql-rds-and-azure/lesson.md) | 12 |
| [6.8 Load balancers, DNS and HTTPS on both clouds](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.8-load-balancers-dns-and-https-on-both/lesson.md) | 12 |
| [6.9 Monitoring, logs and alerts: CloudWatch and Azure Monitor](phases/01-cloud-foundations/06-cloud-foundations-on-aws-and-azure/6.9-monitoring-logs-and-alerts-cloudwatch/lesson.md) | 12 |

### [Capstone 1 (week 13): ITL Pay on AWS and Azure, by hand then by script](phases/01-cloud-foundations/capstone-1/README.md)

Deploy ITL Pay (pre-built images) on both clouds: a private network with public and private subnets, a load balancer and HTTPS, managed PostgreSQL with backups, least-privilege access, alerts and a budget alert. Build it by hand on each cloud, then rebuild it from one script. Write a runbook, a diagram for each cloud, and a one-page comparison.

## Phase 2: DevOps and Infrastructure as Code (weeks 14–24)

Terraform on both clouds, CI/CD with keyless login, Kubernetes and Helm (EKS and AKS), secrets and observability. Capstone 2: pipeline to production on two clouds.

## Phase 3: Platform Engineering and SRE (weeks 25–34)

GitOps, reliability targets and incident response, a self-service platform that deploys to either cloud, cloud security, FinOps and AI for operations. Capstone 3: run a two-cloud platform.
