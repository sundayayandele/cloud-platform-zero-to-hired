# Phase 1: Cloud Foundations (weeks 1–13)

Linux, networking, Bash and Python, Git, containers, and the foundations of AWS and Azure side by side. Capstone 1 deploys ITL Pay on both clouds.

Certification targets: AWS Certified Cloud Practitioner and Microsoft Azure Fundamentals (AZ-900).

Every cloud topic follows four steps: the idea without a vendor, the AWS lab, the Azure lab with the same checks, and a comparison.

## Module 1: Linux and the command line (weeks 1–2)

- [1.1 Your lab: a terminal, a Linux machine and how this course works](01-linux-and-the-command-line/1.1-your-lab-a-terminal-a-linux-machine/lesson.md) (week 1)
- [1.2 Files, directories, text and pipes](01-linux-and-the-command-line/1.2-files-directories-text-and-pipes/lesson.md) (week 1)
- [1.3 Users, groups, permissions and sudo](01-linux-and-the-command-line/1.3-users-groups-permissions-and-sudo/lesson.md) (week 1)
- [1.4 Processes, services with systemd, and logs](01-linux-and-the-command-line/1.4-processes-services-with-systemd-and-logs/lesson.md) (week 2)
- [1.5 Packages, SSH keys and working on a remote server](01-linux-and-the-command-line/1.5-packages-ssh-keys-and-working/lesson.md) (week 2)

## Module 2: Networking for the cloud (weeks 3–4)

- [2.1 How data moves: IP, TCP, UDP and ports](02-networking-for-the-cloud/2.1-how-data-moves-ip-tcp-udp-and-ports/lesson.md) (week 3)
- [2.2 Addresses and subnets: IPv4, CIDR and private ranges](02-networking-for-the-cloud/2.2-addresses-and-subnets-ipv4-cidr/lesson.md) (week 3)
- [2.3 DNS: how names become addresses](02-networking-for-the-cloud/2.3-dns-how-names-become-addresses/lesson.md) (week 3)
- [2.4 HTTP, HTTPS and TLS certificates](02-networking-for-the-cloud/2.4-http-https-and-tls-certificates/lesson.md) (week 4)
- [2.5 Routing, NAT, firewalls and load balancers](02-networking-for-the-cloud/2.5-routing-nat-firewalls-and-load-balancers/lesson.md) (week 4)
- [2.6 Troubleshooting a connection step by step](02-networking-for-the-cloud/2.6-troubleshooting-a-connection-step/lesson.md) (week 4)

## Module 3: Scripting and automation (weeks 5–6)

- [3.1 Bash scripting: variables, conditions, loops and functions](03-scripting-and-automation/3.1-bash-scripting-variables-conditions/lesson.md) (week 5)
- [3.2 Safe scripts: quoting, errors and running twice](03-scripting-and-automation/3.2-safe-scripts-quoting-errors-and-running/lesson.md) (week 5)
- [3.3 Scheduling: cron and systemd timers](03-scripting-and-automation/3.3-scheduling-cron-and-systemd-timers/lesson.md) (week 5)
- [3.4 Python for operations: files, JSON and REST APIs](03-scripting-and-automation/3.4-python-for-operations-files-json/lesson.md) (week 6)
- [3.5 Testing your automation with pytest](03-scripting-and-automation/3.5-testing-your-automation-with-pytest/lesson.md) (week 6)

## Module 4: Git, GitHub and docs-as-code (weeks 7)

- [4.1 Git and GitHub essentials](04-git-github-and-docs-as-code/4.1-git-and-github-essentials/lesson.md) (week 7)
- [4.2 Pull requests, code review and branch protection](04-git-github-and-docs-as-code/4.2-pull-requests-code-review-and-branch/lesson.md) (week 7)
- [4.3 Docs as code: READMEs, runbooks, diagrams and decision records](04-git-github-and-docs-as-code/4.3-docs-as-code-readmes-runbooks-diagrams/lesson.md) (week 7)

## Module 5: Containers (weeks 8–9)

- [5.1 Containers: what they are and how to run them](05-containers/5.1-containers-what-they-are-and-how-to-run/lesson.md) (week 8)
- [5.2 Building images: Dockerfiles, layers and multi-stage builds](05-containers/5.2-building-images-dockerfiles-layers/lesson.md) (week 8)
- [5.3 Docker Compose: running ITL Pay on your laptop](05-containers/5.3-docker-compose-running-itl-pay/lesson.md) (week 9)
- [5.4 Registries and image security: GHCR, ECR and ACR](05-containers/5.4-registries-and-image-security-ghcr-ecr/lesson.md) (week 9)

## Module 6: Cloud foundations on AWS and Azure (weeks 10–12)

- [6.1 Cloud concepts, accounts and subscriptions, regions, and billing guardrails](06-cloud-foundations-on-aws-and-azure/6.1-cloud-concepts-accounts/lesson.md) (week 10)
- [6.2 Identity and access: IAM, and Entra ID with Azure RBAC](06-cloud-foundations-on-aws-and-azure/6.2-identity-and-access-iam-and-entra-id/lesson.md) (week 10)
- [6.3 The AWS CLI and the Azure CLI side by side](06-cloud-foundations-on-aws-and-azure/6.3-the-aws-cli-and-the-azure-cli-side/lesson.md) (week 10)
- [6.4 Private networks: VPC and VNet](06-cloud-foundations-on-aws-and-azure/6.4-private-networks-vpc-and-vnet/lesson.md) (week 11)
- [6.5 Virtual machines: EC2 and Azure Virtual Machines](06-cloud-foundations-on-aws-and-azure/6.5-virtual-machines-ec2-and-azure-virtual/lesson.md) (week 11)
- [6.6 Object storage: S3 and Blob Storage](06-cloud-foundations-on-aws-and-azure/6.6-object-storage-s3-and-blob-storage/lesson.md) (week 11)
- [6.7 Managed PostgreSQL: RDS and Azure Database for PostgreSQL](06-cloud-foundations-on-aws-and-azure/6.7-managed-postgresql-rds-and-azure/lesson.md) (week 12)
- [6.8 Load balancers, DNS and HTTPS on both clouds](06-cloud-foundations-on-aws-and-azure/6.8-load-balancers-dns-and-https-on-both/lesson.md) (week 12)
- [6.9 Monitoring, logs and alerts: CloudWatch and Azure Monitor](06-cloud-foundations-on-aws-and-azure/6.9-monitoring-logs-and-alerts-cloudwatch/lesson.md) (week 12)

## Capstone 1 (week 13)

[ITL Pay on AWS and Azure, by hand then by script](capstone-1/README.md): the brief, the evidence checklist and the rubric.

## Labs

- [`labs/access-log`](../../labs/access-log/generate.py): the practice web server log (topic 1.2)
- [`labs/url-checker`](../../labs/url-checker/checker.py): a tested Python operations tool (topics 3.4 and 3.5)
- [`labs/itlpay-lite`](../../labs/itlpay-lite/README.md): the transfers API used in Module 5 and Capstone 1
