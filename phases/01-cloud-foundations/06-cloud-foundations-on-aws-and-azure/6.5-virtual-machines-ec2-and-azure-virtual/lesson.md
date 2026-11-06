## What you will be able to do

- Choose a VM image, size and disk on **AWS (EC2)** and **Azure (Virtual Machines)**, and read their naming schemes.
- Launch a Linux VM in a private subnet with no public IP and no open SSH port, and reach it with **Session Manager** (AWS) and **Azure Bastion** or the CLI (Azure).
- Configure a VM automatically at first boot with **user data** / **cloud-init**, so it installs Docker and runs ITL Pay Lite with no manual steps.
- Give the VM an identity (IAM role, managed identity) and use it to reach other services without keys.
- Stop, start, resize and delete VMs correctly, and know what keeps costing money afterwards.
- Explain scale sets / Auto Scaling groups and when to use containers or managed platforms instead.

## Why this matters at work

Virtual machines are still the backbone of most companies' cloud estates: legacy apps, databases some teams run themselves, build agents, bastion hosts, and the nodes underneath Kubernetes. A junior cloud engineer creates, patches, resizes, troubleshoots and retires VMs every week. Doing it **without** public IPs and SSH keys lying around, and **without** clicking through set-up by hand, is what separates a professional from a hobbyist, and it's exactly what Capstone 1 grades.

## 1. Choosing a VM

| Choice | AWS (EC2) | Azure |
| --- | --- | --- |
| Image | **AMI**: Ubuntu 24.04, Amazon Linux 2023, RHEL, Windows | **Image**: `Ubuntu2404`, RHEL, Windows Server; Marketplace |
| Size naming | `t3.small`: family `t` (burstable), generation 3, size small. `m7i` general, `c7i` compute, `r7i` memory, `g` suffix = Graviton ARM (`t4g`, `m7g`) | `Standard_B2s`: series B (burstable), 2 vCPU, s = premium storage capable. D (general), F (compute), E (memory), `p` = ARM (`D2ps_v5`) |
| Cheapest for labs | `t3.micro` / `t4g.micro` (free tier eligible on some offers) | `Standard_B1s` / `B2ats_v2` (free hours on some offers) |
| Disk | **EBS** volume: `gp3` general SSD | **Managed disk**: Standard SSD, Premium SSD |
| Discount for steady use | Savings Plans, Reserved Instances | Reservations, Savings Plan for compute |
| Cheap but can be taken away | **Spot** instances | **Spot** VMs |

**Burstable** sizes (`t`, `B`) give a small baseline of CPU and build up credits to burst; they're perfect for labs and light apps, and confusing when a busy app suddenly slows down because the credits ran out.

Check the free-tier rules for your offer (topic 6.1): they cover specific sizes and a number of hours per month.

## 2. No public IP, no open SSH: how admins get in

In topic 1.5 you used SSH keys. For production, both clouds offer access with **no inbound port at all**, through the cloud's identity system, with every session logged:

- **AWS Systems Manager Session Manager:** the VM runs the SSM Agent (preinstalled on Amazon Linux and Ubuntu AMIs), has an IAM role with the **`AmazonSSMManagedInstanceCore`** policy, and can reach the Systems Manager endpoints (through the NAT gateway, or VPC interface endpoints). Then: `aws ssm start-session --target i-0abc...` (needs the Session Manager plugin for the CLI), or **Connect → Session Manager** in the console.
- **Azure Bastion:** a managed service in `AzureBastionSubnet` that gives browser or native-client SSH/RDP to VMs with only private IPs. The **Developer** tier is free and good for labs (one session at a time, portal only); Basic and Standard are billed per hour. Also **`az ssh vm`** with **Microsoft Entra ID login** removes SSH key management altogether.

## 3. Configuring at first boot: user data and cloud-init

Never set up a server by hand: you can't repeat it exactly, and the next server will be different. Both clouds pass a **user data** / **custom data** script to the VM, which **cloud-init** runs on first boot. This one installs Docker and starts ITL Pay Lite from the image you pushed to GHCR in topic 5.4 (the database comes in topic 6.7; for now the app reports its database as down, which proves the server works):

```yaml
#cloud-config
package_update: true
packages: [docker.io]
write_files:
  - path: /etc/systemd/system/itlpay.service
    content: |
      [Unit]
      Description=ITL Pay Lite
      After=docker.service
      Requires=docker.service
      [Service]
      Restart=always
      ExecStartPre=-/usr/bin/docker rm -f itlpay
      ExecStart=/usr/bin/docker run --name itlpay -p 8080:8080 \
        -e APP_ENV=lab -e DATABASE_URL=postgresql://none@127.0.0.1:1/none \
        ghcr.io/YOUR-USERNAME/itlpay-lite:1.0.0
      ExecStop=/usr/bin/docker stop itlpay
      [Install]
      WantedBy=multi-user.target
runcmd:
  - systemctl enable --now docker itlpay
```

Save it as `cloud-init.yaml`. It's the same on both clouds: that's the point. Check progress on the VM with `cloud-init status --long` and `/var/log/cloud-init-output.log`.

Never put secrets in user data: anyone who can read the VM's settings can read it (and on AWS, anything on the VM can read it from the metadata service). The database password comes from a secret store in topic 6.7.

## 4. Launching the VM on both clouds

Use the networks from topic 6.4.

**AWS:**

```bash
# A role the instance can assume, with Session Manager access
aws iam create-role --role-name itlpay-app-role --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name itlpay-app-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name itlpay-app-profile
aws iam add-role-to-instance-profile --instance-profile-name itlpay-app-profile --role-name itlpay-app-role

ami=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
      --query Parameter.Value --output text)
aws ec2 run-instances --image-id "$ami" --instance-type t3.micro \
  --subnet-id "$app_a" --security-group-ids "$sg_app" --no-associate-public-ip-address \
  --iam-instance-profile Name=itlpay-app-profile \
  --metadata-options HttpTokens=required \
  --user-data file://cloud-init.yaml \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=itlpay-app-a},{Key=owner,Value=ada},{Key=purpose,Value=topic-6.5}]'
```

- `--no-associate-public-ip-address` and a private subnet: unreachable from the internet.
- `HttpTokens=required` enforces **IMDSv2** (topic 6.2).
- The AMI ID comes from Canonical's public parameter, so the script always gets the current Ubuntu 24.04 image instead of a hard-coded ID that differs per region.

Then: `aws ssm start-session --target <instance-id>`, and on the VM `curl -s localhost:8080/health`.

**Azure:**

```bash
az vm create -g rg-itlpay-net -n itlpay-app-1 --image Ubuntu2404 --size Standard_B1s \
  --vnet-name itlpay-vnet --subnet app --public-ip-address "" --nsg "" \
  --asgs asg-app --assign-identity --custom-data cloud-init.yaml \
  --admin-username azureuser --generate-ssh-keys --zone 1 \
  --tags owner=ada purpose=topic-6.5
```

- `--public-ip-address ""` and `--nsg ""`: no public IP, and no NIC-level NSG (the subnet's NSG from topic 6.4 applies).
- `--assign-identity` turns on a system-assigned **managed identity** (topic 6.2).
- `--zone 1` places it in availability zone 1, where the region supports zones.

Then connect through Bastion (portal: VM → **Connect → Bastion**), or with Entra ID login, and run the same `curl`. You can also run a command without any session: `az vm run-command invoke -g rg-itlpay-net -n itlpay-app-1 --command-id RunShellScript --scripts "curl -s localhost:8080/health"`. The AWS equivalent is `aws ssm send-command`.

## 5. Using the VM's identity

From the VM, with no keys anywhere:

```bash
# AWS (on the EC2 instance): the role's temporary credentials are found automatically
aws sts get-caller-identity          # shows assumed-role/itlpay-app-role/i-...

# Azure (on the VM)
az login --identity
az account show
```

In topic 6.6, you'll give these identities read access to one storage bucket/container, and read a file from the VM.

## 6. The VM lifecycle and its costs

| Action | AWS | Azure | Still costs money? |
| --- | --- | --- | --- |
| Stop | `aws ec2 stop-instances` | `az vm deallocate` (**not** just stop from inside the OS) | Disks and any public IPs: yes. Compute: no |
| Start | `start-instances` | `az vm start` | (Private IPs may change; use DNS or a load balancer, not IPs) |
| Resize | Stop, `modify-instance-attribute --instance-type`, start | `az vm resize` (may need deallocation) | |
| Delete | `terminate-instances` (root volume deleted by default) | `az vm delete` (disks, NICs and IPs may remain unless deleted too, or delete the resource group) | Leftover disks, snapshots, IPs: yes |

Patching: VMs are yours to patch (shared responsibility). Both clouds automate it: **AWS Systems Manager Patch Manager**, **Azure Update Manager**. In Phase 2 you'll prefer **replacing** servers with freshly built images over patching them in place.

## 7. Many identical VMs: scale sets

For more than one server, don't launch them one at a time. **Auto Scaling groups** (AWS, with a **launch template**) and **Virtual Machine Scale Sets** (Azure) keep a number of identical VMs running across zones, replace unhealthy ones, and add or remove VMs by load or schedule. Combined with a load balancer (topic 6.8), this is a highly available web tier. The same user data / cloud-init makes every new VM identical.

When not to use VMs at all: if the app is already a container, managed container platforms (App Runner, ECS Fargate, Azure Container Apps) remove the OS from your responsibility. Capstone 1 uses VMs on purpose, so you learn what those platforms do for you.

## Practice

1. Push your ITL Pay Lite image to GHCR (topic 5.4) and make it public, so the VMs can pull it without credentials.
2. Launch one VM in the app subnet on each cloud with the cloud-init file. Connect with Session Manager and Bastion (Developer tier), check `cloud-init status --long`, and `curl localhost:8080/health` (it should report the database as unreachable, with status 503: the VM and app work; the database comes in 6.7).
3. Prove the VM has no public IP and that nothing on the internet can reach it (Reachability Analyzer / IP flow verify from topic 6.4).
4. From each VM, show its cloud identity (`aws sts get-caller-identity`; `az login --identity && az account show`).
5. Stop/deallocate both VMs and check in each console that compute billing stopped; then delete them, and find and delete any leftover disks and IPs.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [UPDATED - Amazon/AWS EC2 Basics | Create an EC2 Instance | AWS Tutorials for Beginners](https://www.youtube.com/watch?v=YH_DVenJHII) · Tiny Technical Tutorials · 12 min. Creating an EC2 instance.
- [Azure Virtual Machine (VM) Tutorial | Infrastructure as a Service (IaaS) intro](https://www.youtube.com/watch?v=iUaTq06m26g) · Adam Marczak - Azure for Everyone · 25 min. Creating and using an Azure virtual machine.
- [AWS Sessions Manager Overview](https://www.youtube.com/watch?v=cUEFGKaZOyU) · Amazon Web Services · 5 min. AWS Systems Manager Session Manager, from AWS.
- [How to use Azure Bastion to access virtual machines | Azure Tips and Tricks](https://www.youtube.com/watch?v=epWKTGGa_wY) · Microsoft Azure · 2 min. Connecting to VMs with Azure Bastion, from Microsoft.

## Further learning (free)

Free, self-paced courses from the two clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn and a free AWS Builder ID for AWS Skill Builder to track your progress.

**Azure (Microsoft Learn):**

- [Introduction to Azure virtual machines](https://learn.microsoft.com/training/modules/intro-to-azure-virtual-machines/)
- [Plan and implement Azure Bastion](https://learn.microsoft.com/training/modules/plan-implement-azure-bastion/)
- [Introduction to Azure Virtual Machine Scale Sets](https://learn.microsoft.com/training/modules/intro-to-azure-virtual-machine-scale-sets/)

**AWS (AWS Skill Builder):**

- [Amazon EC2 Getting Started](https://skillbuilder.aws/learn/2JS8J94MC5/amazon-ec2-getting-started/9XXKVZU682)
- [Build with Amazon EC2](https://skillbuilder.aws/learn/DMG1BSGQNN/build-with-amazon-ec2/B7FZRSJADX)
- [AWS Systems Manager Getting Started (Session Manager)](https://skillbuilder.aws/learn/1AG8ZGZN4Z/aws-systems-manager-getting-started/PKCXBQX7M5)

