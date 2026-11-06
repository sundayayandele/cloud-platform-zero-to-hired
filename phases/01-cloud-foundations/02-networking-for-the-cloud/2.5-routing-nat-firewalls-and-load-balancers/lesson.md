## What you will be able to do

- Explain how a router decides where to send a packet, and read a route table, including the cloud kind.
- Explain the default route, and how "public" and "private" subnets differ only by their routes.
- Explain NAT, and why private servers can reach the internet without being reachable from it.
- Write firewall rules, and explain the difference between **stateful** and **stateless** firewalls.
- Explain what a load balancer does, the difference between layer-4 and layer-7 load balancers, and how health checks decide where traffic goes.
- Map each idea to its AWS and Azure building blocks, ready for Module 6.

## Why this matters at work

A cloud network is built from exactly four things: address ranges (topic 2.2), routes, firewall rules and load balancers. When a server "can't reach the internet", "can't be reached", or "gets no traffic from the load balancer", the cause is almost always one of these. A single wrong route or rule can take a whole service offline, or expose a database to the internet. Reading routes and rules calmly is what makes you trusted with production networks.

## 1. Routing: where does this packet go next?

A **router** connects networks. For every packet, it looks at the destination address and its **route table**, and picks the **most specific** matching route (the one with the longest prefix).

A home or office route table might look like this:

| Destination | Next hop |
| --- | --- |
| `192.168.1.0/24` | Directly connected (local network) |
| `0.0.0.0/0` | `192.168.1.1` (the home router) |

`0.0.0.0/0` matches **every** address; it's the **default route**: "anything I don't know a better route for, send here". Because routers pick the most specific match, traffic for `192.168.1.40` stays local, and everything else goes to the router.

On Linux:

```bash
ip route                    # this machine's route table
ip route get 1.1.1.1        # which route and interface would be used for this address
traceroute -n 1.1.1.1       # each router hop on the way (sudo apt install -y traceroute)
mtr -n 1.1.1.1              # traceroute that keeps running, showing loss at each hop
```

## 2. Routing in the cloud: public and private subnets

In AWS and Azure, every subnet uses a route table. The difference between a "public" and a "private" subnet is **only** its routes:

| Route table for... | Destination | Next hop (AWS) | Next hop (Azure) |
| --- | --- | --- | --- |
| Every subnet | The network's own range (`10.20.0.0/16`) | `local` | Virtual network (automatic) |
| A **public** subnet | `0.0.0.0/0` | An **internet gateway** | Internet (the default system route) |
| A **private** subnet | `0.0.0.0/0` | A **NAT gateway** (in a public subnet) | A **NAT gateway** attached to the subnet, or a firewall |

There's an important difference between the clouds:

- In **AWS**, a new subnet has no route to the internet until you add one to an internet gateway. Private is the default.
- In **Azure**, subnets have a **default system route** to the internet, and virtual machines have historically been given **default outbound access** automatically. Microsoft is retiring that default for new networks, and best practice is already to make subnets private and give them a NAT gateway on purpose. Never assume a subnet is private because you didn't make it public: check.

You can also add routes that send traffic through a **firewall appliance** (AWS Network Firewall, Azure Firewall) or to other networks (peering, VPNs), which come in Phase 2.

## 3. NAT: many private addresses, one public address

Private addresses (topic 2.2) can't travel on the internet. **NAT** (Network Address Translation) lets machines with private addresses reach the internet anyway:

1. A private server `10.20.16.7` sends a request to a public API.
2. The **NAT gateway** replaces the source address with its own public address, and remembers the connection.
3. The reply comes back to the NAT gateway, which sends it on to `10.20.16.7`.

NAT works **one way**: private servers can start connections **out** (to download updates or call a payment provider's API), but nobody on the internet can start a connection **in** to them. That's exactly what you want for application and database servers.

Two practical points:

- A partner bank often asks for your **fixed outbound IP addresses** to add to their allow list. With a NAT gateway, all your private servers leave through its public IP, so you give them that one address.
- NAT gateways **cost money** on both clouds, by the hour and by the gigabyte. They're often the surprise item on a learner's bill (topic 6.1 shows how to avoid it).

## 4. Firewalls: rules about what may connect

A firewall checks each connection against **rules**: protocol, source, destination and port, and allows or denies it.

| Rule | Protocol | Port | Source | Action |
| --- | --- | --- | --- | --- |
| HTTPS from anywhere to the load balancer | TCP | 443 | `0.0.0.0/0` | Allow |
| App traffic from the load balancer only | TCP | 8080 | The load balancer's subnet or group | Allow |
| PostgreSQL from the app tier only | TCP | 5432 | The app subnet or group | Allow |
| SSH from the admin's IP | TCP | 22 | `102.89.34.11/32` | Allow |
| Everything else | Any | Any | Any | Deny |

**Stateful** firewalls remember connections: if a request was allowed **out**, its reply is automatically allowed back **in**. You write rules only for the direction the connection **starts**. **Stateless** firewalls check every packet on its own, so you must allow the reply traffic too (usually on the high ephemeral ports, 1024–65535).

| | AWS | Azure |
| --- | --- | --- |
| Main firewall, attached to... | **Security group**: stateful, attached to network interfaces (instances, load balancers, databases). **Allow rules only**; everything else is denied | **Network security group (NSG)**: stateful, attached to a subnet and/or a network interface. **Allow and deny rules** with priorities (lower number wins) and built-in default rules |
| Subnet-level extra layer | **Network ACL**: stateless, numbered allow and deny rules | NSG on the subnet does this job |
| Referring to "the app servers" instead of IP addresses | A rule's source can be **another security group** | A rule's source can be an **application security group** or a service tag (for example `AzureLoadBalancer`, `Internet`) |
| Central firewall service | AWS Network Firewall | Azure Firewall |

Referring to groups rather than IP addresses is the professional way: "PostgreSQL is allowed only from members of the app group" keeps working when servers are replaced and their addresses change.

On a Linux machine, `ufw` (topic 1.5) or `nftables` does the same job locally. Defence in depth means both: the cloud firewall and the machine's own.

## 5. Load balancers

A **load balancer** receives traffic on one address and spreads it across several servers (its **targets** or **backends**). It gives you:

- **availability**: if one server fails, traffic goes to the others;
- **scale**: add servers behind it as traffic grows;
- **one place for TLS** (topic 2.4) and, often, for routing rules.

**Health checks** decide which targets get traffic. The load balancer calls something like `GET /health` on each target every few seconds; targets that fail a few times in a row are taken out of rotation until they pass again. If **every** target fails, users get a `503`. A good health endpoint checks that the app can really serve requests, but doesn't fail just because a non-essential dependency is slow; otherwise one slow service can take the whole site offline.

Layer 4 versus layer 7:

| | Layer 4 (transport) | Layer 7 (application) |
| --- | --- | --- |
| Sees | IP addresses and ports, TCP/UDP | Full HTTP: host names, paths, headers, cookies |
| Can do | Very fast forwarding, any TCP/UDP protocol, fixed IP addresses | Route `/api/*` to one service and `/` to another, terminate TLS, redirect HTTP to HTTPS, add a web application firewall |
| AWS | **Network Load Balancer (NLB)** | **Application Load Balancer (ALB)** |
| Azure | **Azure Load Balancer** | **Application Gateway** (regional) and **Front Door** (global, at the edge) |

For ITL Pay, a layer-7 load balancer in the public subnets terminates HTTPS, sends `/api/*` to the app servers in the private subnets on port 8080, and checks `/health` on each.

## 6. Putting it together: ITL Pay's network

```text
Internet
   │  HTTPS 443
   ▼
[Load balancer]  public subnets   ──▶ security group / NSG: allow 443 from anywhere
   │  HTTP 8080
   ▼
[App servers]    private subnets  ──▶ allow 8080 from the load balancer only
   │  PostgreSQL 5432          │ outbound only, via NAT gateway (updates, partner APIs)
   ▼                           ▼
[Database]       data subnets     ──▶ allow 5432 from the app servers only; no internet route
```

You'll build exactly this, on both clouds, in Module 6 and Capstone 1.

## Practice

1. Run `ip route` and `ip route get 8.8.8.8`. Which interface and gateway would be used? Run `traceroute -n 8.8.8.8` and count the hops.
2. A route table has `10.20.0.0/16 → local`, `10.20.48.0/24 → firewall` and `0.0.0.0/0 → NAT gateway`. Where does a packet for `10.20.48.9` go? For `10.20.16.4`? For `52.95.110.1`? Explain using "most specific match".
3. Write the full firewall rule set (as a table) for the diagram in section 6, once in AWS style (security groups that reference each other) and once in Azure style (NSGs with priorities and a final deny).
4. A developer says: "The new server in the private subnet can't download packages, but SSH from the bastion works fine." List three likely causes in order of likelihood.
5. In your learning log, explain to a teammate why the database should have **no** route to the internet at all, not even through NAT.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [NAT Explained - Network Address Translation](https://www.youtube.com/watch?v=FTUV0t6JaDA) · PowerCert Animated Videos · 4 min. Network address translation (NAT) with animations.
- [What is a Load Balancer?](https://www.youtube.com/watch?v=sCR3SAVdyCc) · IBM Technology · 8 min. What a load balancer does and why.
- [Stateful vs Stateless Firewalls - You NEED to know the difference](https://www.youtube.com/watch?v=rL4-vbsN35w) · LearnCantrill · 14 min. Stateful versus stateless firewalls: the difference you need for security groups and NACLs.

## Further learning (free)

Free, self-paced courses from the two clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn and a free AWS Builder ID for AWS Skill Builder to track your progress.

**Azure (Microsoft Learn):**

- [Configure network security groups](https://learn.microsoft.com/training/modules/configure-network-security-groups/)
- [Introduction to Azure Load Balancer](https://learn.microsoft.com/training/modules/intro-to-azure-load-balancer/)
- [Introduction to Secure Network Infrastructure with Azure network security (learning path)](https://learn.microsoft.com/training/paths/secure-networking-infrastructure/)

**AWS (AWS Skill Builder):**

- [Understanding AWS Networking Gateways](https://skillbuilder.aws/learn/DYWKWCJ9Y1/understanding-aws-networking-gateways/484J82ZCEZ)
- [Differences Between Security Groups and NACLs](https://skillbuilder.aws/learn/WZ7B7G3RZ4/differences-between-security-groups-and-nacls/G59RY3EZGG)
- [Elastic Load Balancing (ELB) Getting Started](https://skillbuilder.aws/learn/2Q7X7W6V7G/elastic-load-balancing-elb-getting-started/XHYHBUHUTA)

