## What you will be able to do

- Read an IPv4 address in binary, and explain what a subnet mask does.
- Read CIDR notation (`10.0.1.0/24`) and work out how many addresses a block has, its first and last address, and whether an address is inside it.
- Name the private address ranges and explain why cloud networks use them.
- Split a network into subnets for a three-tier application, without overlaps.
- Explain why AWS and Azure each reserve some addresses in every subnet, and plan for it.
- Avoid the address-planning mistakes that are expensive to fix later (overlapping ranges, subnets that are too small).

## Why this matters at work

Every AWS VPC and every Azure virtual network starts with an address range, and every subnet inside it is a slice of that range. Choose badly and you find out months later: the network can't be connected to the office or to another team's network because the ranges overlap, or a Kubernetes cluster runs out of addresses and can't add servers. Changing a network's addresses after systems are running is slow and risky. Getting the plan right on day one is a core cloud skill, and interviewers often ask subnetting questions.

## 1. An IPv4 address is 32 bits

An IPv4 address like `10.0.1.25` is four **octets** (8 bits each, values 0 to 255), 32 bits in total:

```text
10       .0        .1        .25
00001010 .00000000 .00000001 .00011001
```

Each bit position in an octet has a value: 128, 64, 32, 16, 8, 4, 2, 1. `25` is 16 + 8 + 1, so `00011001`. You won't convert by hand often, but it explains everything that follows.

## 2. Network and host: the subnet mask

An address has two parts: the **network** part (which network it's on) and the **host** part (which device on that network). The **subnet mask** says where the split is: its 1 bits mark the network part.

```text
Address  10.0.1.25      00001010.00000000.00000001.00011001
Mask     255.255.255.0  11111111.11111111.11111111.00000000
Network  10.0.1.0       (first 24 bits)
Host     .25            (last 8 bits)
```

Two devices whose addresses share the network part are on the **same subnet** and talk directly. Anything else goes through a **router** (or, in the cloud, the network's route table).

## 3. CIDR notation

Writing masks in full is clumsy, so we count the 1 bits instead. `10.0.1.0/24` means "the first 24 bits are the network". This is **CIDR** (Classless Inter-Domain Routing) notation, and it's how both AWS and Azure describe every network and subnet.

The number of addresses in a block is 2 to the power of the host bits (32 minus the prefix):

| CIDR | Mask | Addresses | Typical cloud use |
| --- | --- | --- | --- |
| `/16` | 255.255.0.0 | 65,536 | A whole VPC or VNet |
| `/20` | 255.255.240.0 | 4,096 | A large subnet (for example Kubernetes nodes and pods) |
| `/22` | 255.255.252.0 | 1,024 | A medium subnet |
| `/24` | 255.255.255.0 | 256 | A common subnet size |
| `/26` | 255.255.255.192 | 64 | A small subnet |
| `/27` | 255.255.255.224 | 32 | Very small; minimum for some Azure services |
| `/28` | 255.255.255.240 | 16 | The smallest subnet AWS allows (Azure allows down to `/29`) |
| `/32` | 255.255.255.255 | 1 | Exactly one address (for example, "allow SSH from my IP /32") |

Each step of 1 in the prefix halves the size: a `/24` holds two `/25`s, four `/26`s, or sixteen `/28`s. A **smaller** prefix number means a **bigger** network.

## 4. Working out a block's range

For `10.0.4.0/22`:

1. Host bits: 32 − 22 = 10, so 2¹⁰ = 1,024 addresses.
2. 1,024 addresses is 4 blocks of 256, so the range covers 4 values of the third octet.
3. Blocks of 4 in the third octet start at multiples of 4: 0, 4, 8, ... So this block runs from `10.0.4.0` to `10.0.7.255`.

Is `10.0.6.200` inside `10.0.4.0/22`? Yes: 6 is between 4 and 7. Is `10.0.8.1`? No.

A block must **start on a multiple of its size**. `10.0.5.0/22` isn't a valid network start, because a /22 spans 4 in the third octet and 5 isn't a multiple of 4. AWS and Azure reject it or round it, which surprises people.

Python checks your working (and the `ipcalc` tool does too: `sudo apt install -y ipcalc`):

```bash
python3 -c "import ipaddress as i; n=i.ip_network('10.0.4.0/22'); print(n.num_addresses, n[0], n[-1]); print(i.ip_address('10.0.6.200') in n)"
```

## 5. Private ranges

Three ranges are reserved for **private** networks (RFC 1918). They're never routed on the public internet, so everyone can reuse them:

| Range | CIDR | Size |
| --- | --- | --- |
| 10.0.0.0 – 10.255.255.255 | `10.0.0.0/8` | 16.7 million |
| 172.16.0.0 – 172.31.255.255 | `172.16.0.0/12` | 1 million |
| 192.168.0.0 – 192.168.255.255 | `192.168.0.0/16` | 65,536 |

Cloud networks use these. Two more ranges are worth recognising: `127.0.0.0/8` is **loopback** (the machine itself; `127.0.0.1` is localhost), and `169.254.0.0/16` is **link-local**: both AWS and Azure serve their **instance metadata** at `169.254.169.254`, which a virtual machine uses to learn about itself and get temporary credentials (an address attackers try to reach, as you'll see in Phase 3).

## 6. Planning a network for a three-tier application

ITL Pay needs a network with three tiers, in **two availability zones** (two separate data centres in the same region, so one can fail; topic 6.1):

- **public** subnets: only the load balancer and a NAT gateway (reachable from the internet);
- **app** subnets: the application servers (private);
- **data** subnets: the databases (private, reachable only from the app tier).

A sound plan for a VPC or VNet of `10.20.0.0/16`:

| Subnet | Zone A | Zone B |
| --- | --- | --- |
| Public | `10.20.0.0/24` | `10.20.1.0/24` |
| App | `10.20.16.0/20` | `10.20.32.0/20` |
| Data | `10.20.48.0/24` | `10.20.49.0/24` |
| Spare (future) | `10.20.64.0` to `10.20.255.255` | |

Why like this:

- **The app tier gets big subnets.** In Phase 2, Kubernetes pods may take addresses from these subnets, and a `/24` fills fast.
- **Nothing overlaps.** Check every pair; overlapping subnets can't exist in one network.
- **Space is left over** for subnets you don't know you need yet.
- **The `/16` itself is chosen to be unique** across the organisation: the office network, other VPCs and VNets, partner banks. You'll connect them one day (peering, VPN), and overlapping ranges can't be connected without painful workarounds. Many companies keep an **IP address plan**, a shared table of which team has which range. Ask for it before choosing.

## 7. Reserved addresses in cloud subnets

Not every address in a subnet is usable. Both clouds keep **5 addresses** in every subnet:

| | AWS (in `10.20.0.0/24`) | Azure (in `10.20.0.0/24`) |
| --- | --- | --- |
| First address | `.0` network address | `.0` network address |
| `.1` | VPC router | Default gateway |
| `.2` | DNS server | Azure DNS mapping |
| `.3` | Reserved for future use | Azure DNS mapping |
| Last address | `.255` broadcast (reserved) | `.255` broadcast (reserved) |

So a `/24` gives you 251 usable addresses on either cloud, and a `/28` only 11. Remember this when sizing small subnets.

Azure has one more thing to know early: some services need a **dedicated subnet with a fixed name and minimum size**, for example `AzureBastionSubnet` (at least `/26`) and `GatewaySubnet` for VPN gateways. Leave room for them in the plan.

## Practice

1. How many addresses are in a `/23`? What are the first and last addresses of `172.16.10.0/23`?
2. Is `10.0.15.7` inside `10.0.8.0/21`? Show your working, then check with Python.
3. Split `10.50.0.0/24` into four equal subnets. Write each in CIDR, with its first and last address and how many addresses AWS or Azure would let you use in each.
4. Your company's office network is `10.0.0.0/16` and the existing production VPC is `10.1.0.0/16`. A colleague proposes `10.0.0.0/16` for a new Azure VNet. What's the problem, and what range would you suggest?
5. Design the address plan for a VNet `10.30.0.0/16` with public, app and data tiers in two zones, plus an `AzureBastionSubnet`. Present it as a table in your learning log, and check there are no overlaps with a short Python script using `ipaddress.ip_network(...).overlaps(...)`.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Subnetting Explained: Networking Basics](https://www.youtube.com/watch?v=hbdT_Q9DM8w) · WhiteboardDoodles · 12 min. Subnetting explained on a whiteboard.
- [IP addressing and Subnetting | CIDR | Subnet | TechTerms](https://www.youtube.com/watch?v=OqsXzkXfwRw) · TechTerms · 4 min. IP addressing, subnets and CIDR, animated.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Introduction to Azure Virtual Networks](https://learn.microsoft.com/training/modules/introduction-to-azure-virtual-networks/)
- [AZ-104: Configure and manage virtual networks for Azure administrators (learning path)](https://learn.microsoft.com/training/paths/az-104-manage-virtual-networks/)

**AWS (AWS Skill Builder):**

- [AWS Networking Basics](https://skillbuilder.aws/learn/S1VYRYHD8V/aws-networking-basics/SKP7248UVF)
- [Configuring and Deploying VPCs with Multiple Subnets](https://skillbuilder.aws/learn/4HWA8PME5S/configuring-and-deploying-vpcs-with-multiple-subnets/BTRCDVX2RU)
- [AWS IPv6 Fundamentals and VPC Connectivity](https://skillbuilder.aws/learn/MU4KD6CAFP/aws-ipv6-fundamentals-and-vpc-connectivity/2S862CT52F)

