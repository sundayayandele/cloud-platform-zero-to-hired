## What you will be able to do

- Build ITL Pay's three-tier network (public, app and data subnets in two zones) on **AWS (VPC)** and on **Azure (VNet)**, from the address plan in topic 2.2.
- Create and attach route tables, an internet gateway (AWS) and NAT gateways on both clouds.
- Write security groups and network ACLs (AWS), and network security groups and application security groups (Azure), for the three tiers.
- Turn on flow logs and use them, with Reachability Analyzer and Network Watcher, to find a blocked connection.
- Explain private endpoints and VPC endpoints, and peering, at a high level.
- Compare the two clouds' networking defaults, and tear everything down so it costs nothing.
- Do the same on **Google Cloud**, and compare the three clouds.

## Why this matters at work

The network is the first thing built for any new system and the hardest to change later. Building one by hand on both clouds, following an address plan and a security design, is exactly what Capstone 1 asks for, and it's a common interview task ("draw and explain the network for a three-tier app on AWS/Azure"). Most cloud security reviews start with the network: is the database reachable from the internet? Which ports are open, to whom? Can you prove it with logs?

## 1. The design (from Module 2)

| Tier | Zone A | Zone B | Route to the internet | Who can reach it |
| --- | --- | --- | --- | --- |
| Public | `10.20.0.0/24` | `10.20.1.0/24` | Direct (internet gateway / default route) | Anyone, on 443 only (the load balancer) |
| App | `10.20.16.0/20` | `10.20.32.0/20` | Outbound only, via NAT | Load balancer on 8080; admins via Session Manager / Bastion |
| Data | `10.20.48.0/24` | `10.20.49.0/24` | None | App tier on 5432 only |

Use `10.20.0.0/16` for the AWS VPC and `10.30.0.0/16` for the Azure VNet (same layout, `10.30.x.x`), so the two never overlap if you connect them later (topic 2.2).

## 2. AWS: the VPC

The console's **VPC → Create VPC → "VPC and more"** wizard builds most of this in one screen and shows a diagram; use it once to see the pieces, then build it with the CLI below so you understand each one.

```bash
set -euo pipefail
export AWS_REGION=af-south-1
tag() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=owner,Value=ada},{Key=purpose,Value=topic-6.4}]"; }

vpc=$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 --tag-specifications "$(tag vpc itlpay-vpc)" \
      --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id "$vpc" --enable-dns-hostnames

azs=($(aws ec2 describe-availability-zones --query "AvailabilityZones[0:2].ZoneName" --output text))
mk_subnet() {   # name cidr az
  aws ec2 create-subnet --vpc-id "$vpc" --cidr-block "$2" --availability-zone "$3" \
    --tag-specifications "$(tag subnet "$1")" --query Subnet.SubnetId --output text
}
pub_a=$(mk_subnet public-a 10.20.0.0/24 "${azs[0]}");  pub_b=$(mk_subnet public-b 10.20.1.0/24 "${azs[1]}")
app_a=$(mk_subnet app-a 10.20.16.0/20 "${azs[0]}");    app_b=$(mk_subnet app-b 10.20.32.0/20 "${azs[1]}")
data_a=$(mk_subnet data-a 10.20.48.0/24 "${azs[0]}");  data_b=$(mk_subnet data-b 10.20.49.0/24 "${azs[1]}")

# Public subnets: route 0.0.0.0/0 to an internet gateway
igw=$(aws ec2 create-internet-gateway --tag-specifications "$(tag internet-gateway itlpay-igw)" \
      --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --vpc-id "$vpc" --internet-gateway-id "$igw"
rt_pub=$(aws ec2 create-route-table --vpc-id "$vpc" --tag-specifications "$(tag route-table rt-public)" \
         --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$rt_pub" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw"
for s in "$pub_a" "$pub_b"; do aws ec2 associate-route-table --route-table-id "$rt_pub" --subnet-id "$s"; done

# App subnets: outbound only, through a NAT gateway in public-a (one NAT keeps the lab cheap;
# production uses one per zone so a zone failure doesn't cut off the other)
eip=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
nat=$(aws ec2 create-nat-gateway --subnet-id "$pub_a" --allocation-id "$eip" \
      --tag-specifications "$(tag natgateway itlpay-nat)" --query NatGateway.NatGatewayId --output text)
aws ec2 wait nat-gateway-available --nat-gateway-ids "$nat"
rt_app=$(aws ec2 create-route-table --vpc-id "$vpc" --tag-specifications "$(tag route-table rt-app)" \
         --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$rt_app" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$nat"
for s in "$app_a" "$app_b"; do aws ec2 associate-route-table --route-table-id "$rt_app" --subnet-id "$s"; done

# Data subnets: keep the VPC's main route table, which only has the local route: no internet at all
echo "VPC $vpc ready"
```

(Some `azs=($(...))` lines trigger `shellcheck` warnings; in your own script, read the output into an array with `read -ra`.)

Now the **security groups**, which reference **each other** rather than IP addresses (topic 2.5):

```bash
sg() { aws ec2 create-security-group --vpc-id "$vpc" --group-name "$1" --description "$2" \
         --tag-specifications "$(tag security-group "$1")" --query GroupId --output text; }
sg_lb=$(sg sg-lb "Load balancer: HTTPS from the internet")
sg_app=$(sg sg-app "App servers: 8080 from the load balancer")
sg_db=$(sg sg-db "Database: 5432 from the app servers")

aws ec2 authorize-security-group-ingress --group-id "$sg_lb" --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id "$sg_app" --protocol tcp --port 8080 --source-group "$sg_lb"
aws ec2 authorize-security-group-ingress --group-id "$sg_db" --protocol tcp --port 5432 --source-group "$sg_app"
```

There's **no SSH rule**: admins reach app servers with **Session Manager** (topic 6.5), which needs no inbound port at all.

**Network ACLs** are optional here; the default ACL allows everything and the security groups do the work. Use custom NACLs for extra subnet-level rules (for example, explicitly deny the data subnets any traffic from the public subnets), remembering they're **stateless** (topic 2.5).

## 3. Azure: the VNet

The portal's **Create virtual network** screen lets you add subnets and see the address space; again, build it once by hand, then with the CLI:

```bash
set -euo pipefail
rg=rg-itlpay-net; loc=southafricanorth
az group create -n "$rg" -l "$loc" --tags owner=ada purpose=topic-6.4 -o none

az network vnet create -g "$rg" -n itlpay-vnet --address-prefixes 10.30.0.0/16 -o none
for s in "public 10.30.0.0/23" "app 10.30.16.0/20" "data 10.30.48.0/23" "AzureBastionSubnet 10.30.2.0/26"; do
  set -- $s
  az network vnet subnet create -g "$rg" --vnet-name itlpay-vnet -n "$1" --address-prefixes "$2" -o none
done
```

Notice the differences from AWS:

- **Azure subnets aren't tied to one zone.** A subnet spans the region's zones; you choose a zone for each VM or zone-redundant service instead. So Azure needs one subnet per tier, not one per tier per zone (here `/23`s replace the AWS pairs of `/24`s).
- **`AzureBastionSubnet`** has a required name and minimum size (`/26`), for Azure Bastion (topic 6.5).
- **Outbound internet:** Azure subnets get a default route to the internet, and historically VMs got **default outbound access** without anything configured. Microsoft is retiring this for new networks; make the app subnet's outbound access explicit with a **NAT gateway**, and mark subnets private (`--default-outbound false`) where your CLI version supports it:

```bash
az network public-ip create -g "$rg" -n itlpay-nat-ip --sku Standard -o none
az network nat gateway create -g "$rg" -n itlpay-nat --public-ip-addresses itlpay-nat-ip -o none
az network vnet subnet update -g "$rg" --vnet-name itlpay-vnet -n app --nat-gateway itlpay-nat -o none
```

The **data** subnet gets no NAT gateway, and its NSG (below) denies outbound internet.

**Network security groups** with **application security groups** (the Azure equivalent of referencing security groups):

```bash
for a in asg-app asg-db; do az network asg create -g "$rg" -n "$a" -o none; done

# App subnet NSG: 8080 only from the load balancer's subnet (Application Gateway, topic 6.8)
az network nsg create -g "$rg" -n nsg-app -o none
az network nsg rule create -g "$rg" --nsg-name nsg-app -n allow-lb-8080 --priority 100 \
  --direction Inbound --access Allow --protocol Tcp --destination-port-ranges 8080 \
  --source-address-prefixes 10.30.0.0/23 --destination-asgs asg-app -o none

# Data subnet NSG: 5432 only from the app servers; no internet outbound
az network nsg create -g "$rg" -n nsg-data -o none
az network nsg rule create -g "$rg" --nsg-name nsg-data -n allow-app-5432 --priority 100 \
  --direction Inbound --access Allow --protocol Tcp --destination-port-ranges 5432 \
  --source-asgs asg-app -o none
az network nsg rule create -g "$rg" --nsg-name nsg-data -n deny-internet-out --priority 4000 \
  --direction Outbound --access Deny --protocol '*' --destination-address-prefixes Internet \
  --destination-port-ranges '*' -o none

az network vnet subnet update -g "$rg" --vnet-name itlpay-vnet -n app --network-security-group nsg-app -o none
az network vnet subnet update -g "$rg" --vnet-name itlpay-vnet -n data --network-security-group nsg-data -o none
```

NSGs come with **default rules** (priorities 65000 and up): allow traffic **within the VNet**, allow the Azure load balancer's health probes, deny everything else inbound. "Within the VNet" is broader than you might expect: by default any subnet can talk to any other. If the data tier must accept only the app tier, add an explicit **deny from the VirtualNetwork** rule at a priority after your allow (for example priority 200), so the default allow never applies.

## 4. Side by side

| | AWS | Azure |
| --- | --- | --- |
| Network | VPC (one region) | VNet (one region) |
| Subnets and zones | Each subnet is in **one** AZ: make one per tier per zone | Subnets span zones: one per tier; pick zones per resource |
| Internet for public subnets | Internet gateway + a route | Default system route (plus public IPs on resources) |
| Private outbound | NAT gateway per AZ, routed from the app subnets | NAT gateway attached to the subnet |
| Instance-level firewall | Security groups (allow only, stateful) | NSG on the NIC (allow/deny, priorities) |
| Subnet-level firewall | Network ACLs (stateless) | NSG on the subnet (stateful) |
| "Members of this group" in rules | Security group references | Application security groups |
| Private access to the platform's own services | VPC endpoints (gateway for S3/DynamoDB, interface for others) | Private endpoints and service endpoints |
| Connect two networks | VPC peering, Transit Gateway | VNet peering, Virtual WAN |
| Flow logs | VPC Flow Logs (to CloudWatch Logs or S3) | VNet flow logs (Network Watcher, to a storage account; query with Traffic Analytics) |
| "Would this connection work?" | Reachability Analyzer | Network Watcher: IP flow verify, connection troubleshoot |

## 5. Private access to cloud services

The app servers will use S3/Blob Storage and a managed database. Without anything extra, that traffic leaves through the NAT gateway to the service's public address: it works, but it costs NAT data charges and leaves the private network.

- **AWS:** add a **gateway VPC endpoint** for S3 (free) to the app route table: S3 traffic then stays on AWS's network. **Interface endpoints** (PrivateLink, charged per hour) do the same for other services such as Secrets Manager and ECR.
- **Azure:** a **private endpoint** gives a storage account or database a private IP address in your subnet, with a **private DNS zone** linked to the VNet so its normal name resolves to that private address (topic 2.3). Forgetting the DNS zone link is the most common private-endpoint fault.

Topics 6.6 and 6.7 use these for storage and the database.

## 6. Flow logs and troubleshooting

Turn on flow logs so you can **prove** what was allowed and denied:

```bash
# AWS: VPC flow logs to CloudWatch Logs (needs an IAM role the service can assume; the console creates one for you)
aws ec2 create-flow-logs --resource-type VPC --resource-ids "$vpc" --traffic-type REJECT \
  --log-destination-type cloud-watch-logs --log-group-name /itlpay/vpc-flow \
  --deliver-logs-permission-arn arn:aws:iam::<account-id>:role/vpc-flow-logs-role

# Azure: VNet flow logs (Network Watcher), to a storage account
az network watcher flow-log create -g "$rg" -n itlpay-vnet-flow --location "$loc" \
  --vnet itlpay-vnet --storage-account <storage-account-id>
```

Then use the method from topic 2.6: test from the source (`nc -vz`), check the route table, check the security rules (Reachability Analyzer; IP flow verify and *Effective security rules*), and look for `REJECT` / denied entries in the flow logs. Flow logs take a few minutes to appear.

## 7. Tear down

NAT gateways and public IPs cost money every hour. At the end of the session:

- **Azure:** `az group delete -n rg-itlpay-net --yes` removes everything in one go.
- **AWS:** delete in reverse order: NAT gateway (and wait), release the Elastic IP, detach and delete the internet gateway, delete subnets, route tables, security groups, then the VPC. Or delete the VPC from the console, which removes most dependent pieces for you after you've deleted the NAT gateway and released its IP.

Save your creation script; Capstone 1 rebuilds this network from one script, and Phase 2 rebuilds it with Terraform.

## Google Cloud: the VPC

Use `10.40.0.0/16` for Google Cloud, so none of the three networks overlap.

Google Cloud's network model has two big differences from the other two:

- A **VPC is global**: one VPC spans every region. **Subnets are regional** and span the region's zones (like Azure), so one subnet per tier per region is enough.
- **Firewall rules belong to the VPC**, not to subnets or interfaces, and they choose which VMs they apply to by **network tag** or **service account**. Every VPC has two **implied rules**: deny all inbound, allow all outbound.

There's no internet gateway to create: a VPC has a default route to the internet, but a VM with **no external IP** can't use it, so private VMs reach the internet only through **Cloud NAT** (attached to a **Cloud Router**). **Private Google Access** on a subnet lets private VMs reach Google APIs (Cloud Storage, Artifact Registry) without NAT.

```bash
gcloud services enable compute.googleapis.com servicenetworking.googleapis.com
gcloud compute networks create itlpay-vpc --subnet-mode=custom          # never "auto" mode: it creates subnets in every region
gcloud compute networks subnets create public --network=itlpay-vpc --region=africa-south1 --range=10.40.0.0/23
gcloud compute networks subnets create app --network=itlpay-vpc --region=africa-south1 --range=10.40.16.0/20 \
  --enable-private-ip-google-access --enable-flow-logs
gcloud compute networks subnets create data --network=itlpay-vpc --region=africa-south1 --range=10.40.48.0/23 \
  --enable-private-ip-google-access

# Outbound internet for the app tier only, through Cloud NAT
gcloud compute routers create itlpay-router --network=itlpay-vpc --region=africa-south1
gcloud compute routers nats create itlpay-nat --router=itlpay-router --region=africa-south1 \
  --nat-custom-subnet-ip-ranges=app --auto-allocate-nat-external-ips

# Firewall rules, targeting VMs by network tag
gcloud compute firewall-rules create allow-lb-to-app --network=itlpay-vpc --direction=INGRESS --action=ALLOW \
  --rules=tcp:8080 --source-ranges=35.191.0.0/16,130.211.0.0/22 --target-tags=app      # Google's load balancers and health checks
gcloud compute firewall-rules create allow-iap-ssh --network=itlpay-vpc --direction=INGRESS --action=ALLOW \
  --rules=tcp:22 --source-ranges=35.235.240.0/20 --target-tags=app                      # admin access through IAP only (topic 6.5)

# A private range for Google-managed services such as Cloud SQL (topic 6.7), connected by peering
gcloud compute addresses create google-managed-services --global --purpose=VPC_PEERING \
  --addresses=10.40.64.0 --prefix-length=20 --network=itlpay-vpc
gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com \
  --ranges=google-managed-services --network=itlpay-vpc
```

Notice there's no rule allowing anything from the internet to the app tier: the implied deny covers it. The load balancer (topic 6.8) reaches the app from Google's documented ranges `35.191.0.0/16` and `130.211.0.0/22`, which is also where health checks come from.

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Network scope | VPC per region | VNet per region | **VPC is global**; subnets are regional |
| Subnets and zones | One per tier per AZ | One per tier (spans zones) | One per tier per region (spans zones) |
| Firewall attached to | Network interfaces (security groups) | Subnets or interfaces (NSGs) | **The VPC**, targeting VMs by tag or service account |
| Private outbound | NAT gateway per AZ | NAT gateway on the subnet | Cloud NAT on a Cloud Router |
| Private access to the cloud's own services | VPC endpoints | Private endpoints, service endpoints | Private Google Access; Private Service Connect; private services access for Cloud SQL |
| Flow logs | VPC Flow Logs | VNet flow logs | VPC Flow Logs, per subnet; Firewall Rules Logging |
| "Would this connection work?" | Reachability Analyzer | Network Watcher | **Connectivity Tests** (Network Intelligence Center) |

**Tear down:** delete the project, or delete in reverse order (firewall rules, NAT and router, peering and address, subnets, network): `gcloud compute networks delete itlpay-vpc` fails until everything in it is gone.

## Practice

1. Build the AWS VPC from section 2 and the Azure VNet from section 3. Draw each in Mermaid (topic 4.3) in your capstone repository, showing subnets, route tables, gateways and the security rules.
2. Using Reachability Analyzer (AWS) and IP flow verify (Azure), prove: the internet can reach port 443 on the public tier; the app tier can't be reached from the internet; the data tier accepts 5432 only from the app tier.
3. Add a deliberate mistake: on AWS, allow 5432 to `sg-db` from `10.20.0.0/16` instead of `sg-app`; on Azure, remove the "deny from VirtualNetwork" rule. Explain in your learning log why each is too broad and who could now reach the database.
4. Turn on flow logs on both and find one rejected/denied connection (try connecting to a port that isn't allowed from a VM in topic 6.5, or wait for internet scanners to hit a public IP).
5. Tear everything down and check both bills the next day show no leftover hourly charges.
6. **Google Cloud:** build the VPC from the Google Cloud section, run a **Connectivity Test** proving the internet can't reach a VM in the app subnet, and add it to your diagrams.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [How to Create an AWS VPC with Public and Private Subnets](https://www.youtube.com/watch?v=ApGz8tpNLgo) · Be A Better Dev · 13 min. Building an AWS VPC with public and private subnets.
- [AZ-900 Episode 10 | Networking Services | Virtual Network, VPN Gateway, CDN, Load Balancer, App GW](https://www.youtube.com/watch?v=5NMcM4zJPM4) · Adam Marczak - Azure for Everyone · 17 min. Azure networking: virtual networks, gateways and load balancers (AZ-900).
- [Security Groups vs. Network Access Control Lists (NACLs) in AWS: What’s the Difference?](https://www.youtube.com/watch?v=JWoNu2Mtpdg) · Tiny Technical Tutorials · 2 min. Security groups versus network ACLs in two minutes.
- [EP 11. GCP Networking | What is Google Cloud VPC | Google Cloud Networking Explained](https://www.youtube.com/watch?v=XLaFU1t9pM8) · Tech Tutorials with Piyush · 23 min. Google Cloud VPC networking explained.
- [VPC firewall rules in Google Cloud Platform](https://www.youtube.com/watch?v=8pqwoZflqPo) · Cloud Advocate · 17 min. VPC firewall rules on Google Cloud.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Introduction to Azure Virtual Networks](https://learn.microsoft.com/training/modules/introduction-to-azure-virtual-networks/)
- [Configure network security groups](https://learn.microsoft.com/training/modules/configure-network-security-groups/)
- [AZ-104: Configure and manage virtual networks for Azure administrators (learning path)](https://learn.microsoft.com/training/paths/az-104-manage-virtual-networks/)

**AWS (AWS Skill Builder):**

- [Introduction to Amazon Virtual Private Cloud (VPC)](https://skillbuilder.aws/learn/PH6Z6EVH8Z/introduction-to-amazon-virtual-private-cloud-vpc/PA8H7FUE15)
- [Configuring and Deploying VPCs with Multiple Subnets](https://skillbuilder.aws/learn/4HWA8PME5S/configuring-and-deploying-vpcs-with-multiple-subnets/BTRCDVX2RU)
- [Protecting Your Instance with Security Groups](https://skillbuilder.aws/learn/QEA4T3Y2EJ/protecting-your-instance-with-security-groups/EAG9U7MHB3)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Networking in Google Cloud: Fundamentals](https://www.skills.google/course_templates/35)
- [Networking in Google Cloud: Routing and Addressing](https://www.skills.google/course_templates/36)
- [Google Cloud Computing Foundations: Networking & Security in Google Cloud](https://www.skills.google/course_templates/155)

