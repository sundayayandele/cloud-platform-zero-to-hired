## What you will be able to do

- Explain how a name such as `api.itlpay.example` becomes an IP address, step by step, from your machine to the authoritative server.
- Read and write the common record types: A, AAAA, CNAME, MX, TXT, NS and the cloud "alias" records.
- Look up records with `dig` and `nslookup`, and read the answer section and the TTL.
- Explain TTLs and caching, and plan a DNS change so it takes effect quickly and safely.
- Explain public and private DNS zones, and how they work in AWS (Route 53) and Azure (Azure DNS and private DNS zones).
- Recognise the classic DNS failures, including "it works on my machine but not on the server".

## Why this matters at work

There's a well-known joke among engineers: "It's not DNS. There's no way it's DNS. It was DNS." A wrong record, an expired domain, a cached old answer or a private name that can't be resolved from the right network causes outages at companies of every size. Moving a website or an API between servers, between regions, or from AWS to Azure is mostly a DNS change, and doing it without downtime takes planning. Email deliverability (SPF, DKIM, DMARC) and proof that you own a domain (for TLS certificates in topic 2.4) are also DNS records.

## 1. What DNS does

People remember names; networks route to IP addresses. The **Domain Name System** is the internet's distributed directory that maps one to the other. Nobody holds the whole directory: it's split into **zones**, each run by whoever owns that part of the name.

Names are read from right to left, from the most general to the most specific:

```text
api . itlpay . example . (root)
host  domain   top-level domain
```

- The **root** zone knows where to find each **top-level domain** (`.com`, `.ng`, `.org`, `.example`).
- The `.ng` servers know which servers are in charge of `itlearning.ng`.
- The servers for `itlearning.ng`, its **authoritative name servers**, hold the actual records.

## 2. A lookup, step by step

When the app asks for `api.itlpay.example`:

1. Your computer checks its own **cache** (and the `/etc/hosts` file). If it has a recent answer, it uses it.
2. Otherwise it asks its configured **resolver**: usually your ISP's, your company's, or a public one such as `1.1.1.1` (Cloudflare) or `8.8.8.8` (Google). In the cloud, it's the provider's resolver (`169.254.169.253` or the VPC's `.2` address on AWS; `168.63.129.16` on Azure).
3. If the resolver has no cached answer, it **walks the tree**: it asks a root server, which refers it to the `.example` servers, which refer it to the authoritative servers for `itlpay.example`, which give the answer.
4. The resolver caches the answer for as long as the record's **TTL** says, and returns it to you.

You can watch the whole walk:

```bash
dig +trace api.github.com
```

## 3. Record types

| Type | Maps | Example |
| --- | --- | --- |
| **A** | A name to an IPv4 address | `api.itlpay.example. 300 IN A 203.0.113.10` |
| **AAAA** | A name to an IPv6 address | `api.itlpay.example. 300 IN AAAA 2001:db8::10` |
| **CNAME** | A name to **another name** (an alias) | `www.itlpay.example. 300 IN CNAME itlpay-web.azurewebsites.net.` |
| **MX** | A domain to its mail servers, with priorities | `itlpay.example. 3600 IN MX 10 mail.itlpay.example.` |
| **TXT** | Free text: domain ownership checks, email policies (SPF, DMARC) | `itlpay.example. 3600 IN TXT "v=spf1 include:_spf.google.com ~all"` |
| **NS** | Which servers are authoritative for a zone | `itlpay.example. 86400 IN NS ns1.example-dns.net.` |
| **CAA** | Which certificate authorities may issue certificates for the domain | `itlpay.example. 3600 IN CAA 0 issue "letsencrypt.org"` |

Two rules trip people up:

- A **CNAME can't sit at the zone apex** (the bare domain, `itlpay.example`), because the apex must also have NS and SOA records. That's a problem when your load balancer only gives you a name. The clouds solve it with **alias records**: AWS Route 53 **alias** records and Azure DNS **alias record sets** point the apex at a load balancer or other cloud resource, and follow its addresses automatically.
- A name with a CNAME can't have **any other record**. Point `www` at the load balancer with a CNAME, and put the TXT records elsewhere.

## 4. Looking things up: dig

`dig` is the standard tool (install with `sudo apt install -y dnsutils` if missing):

```bash
dig itlearning.ng                  # A record, with full detail
dig +short itlearning.ng           # just the answer
dig AAAA itlearning.ng +short      # IPv6
dig MX itlearning.ng +short        # mail servers
dig TXT itlearning.ng +short       # TXT records
dig NS itlearning.ng +short        # authoritative name servers
dig @1.1.1.1 itlearning.ng         # ask a specific resolver
dig @ns1.example-dns.net itlpay.example   # ask the authoritative server directly (no cache)
dig -x 8.8.8.8 +short              # reverse lookup: address to name
```

In the full output, the **ANSWER SECTION** shows each record with its **remaining TTL** in seconds; the footer shows which server answered and how long it took. `nslookup` does similar jobs and exists on Windows too.

## 5. TTL and caching: why changes "take time"

Every record has a **TTL** (time to live): how many seconds resolvers may cache it. A TTL of 3600 means that after you change the record, some users can keep getting the old answer for up to an hour. People say DNS changes take time to "propagate"; really, old answers are waiting to expire from caches.

How to move `api.itlpay.example` from an old server to a new one without downtime:

1. **Days before:** lower the record's TTL, for example from 3600 to 60. Wait at least the **old** TTL (one hour here) so every cache has picked up the short TTL.
2. **Change day:** keep the old server running, change the record to the new address, and watch traffic arrive at the new server.
3. **After:** when the old server has had no traffic for a while, switch it off, and raise the TTL again (very short TTLs mean more lookups and slower first requests).

The same plan works for moving an application from AWS to Azure, or from one region to another.

Negative answers are cached too: if someone looked up a name **before** you created it, the "no such name" (NXDOMAIN) answer can be cached for the zone's negative-caching time. Test new names with `dig @<authoritative server>` to bypass caches.

## 6. Public and private DNS in the cloud

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Public zones (names the internet can resolve) | Route 53 **public hosted zones** | Azure DNS **public zones** | Cloud DNS **public zones** |
| Private zones (names only your networks can resolve) | Route 53 **private hosted zones**, associated with VPCs | Azure **Private DNS zones**, linked to VNets | Cloud DNS **private zones**, visible to chosen VPCs |
| Pointing the apex at a load balancer | Alias records | Alias record sets | A records pointing at the load balancer's static anycast IP (no alias type needed) |
| Built-in resolver for machines in the network | The VPC resolver (`.2` address, also `169.254.169.253`) | Azure-provided DNS (`168.63.129.16`) | The metadata server (`169.254.169.254`) |
| Health-checked and routing policies | Route 53 health checks; weighted, latency, failover, geolocation routing | Azure Traffic Manager (DNS-based routing) | Cloud DNS routing policies (weighted, geolocation, failover) |

**Private DNS** lets you give internal services names such as `db.internal.itlpay` that only resolve inside your network, so applications don't hard-code IP addresses. It's also how **private endpoints** work: a managed database or storage account gets a private IP address in your network, and a private DNS zone makes its usual name resolve to that private address from inside the network, while the internet still sees the public one. When that zone isn't linked to the right VNet or VPC, the name resolves to the public address and the connection fails or goes the wrong way. It's one of the most common cloud DNS faults.

To use a domain you bought elsewhere (say, from a `.ng` registrar) with Route 53 or Azure DNS, you create the zone in the cloud and then change the **NS records at the registrar** to the cloud's name servers.

## 7. Classic DNS failures

| Symptom | Likely cause | How to check |
| --- | --- | --- |
| Works for you, not for a colleague (or the other way round) | One of you has a cached old answer | `dig +short name` on both, and compare TTLs; ask the authoritative server directly |
| Works on your laptop, not on the server | The server uses a different resolver, or the name only exists in a private zone the server's network isn't linked to | `resolvectl status` (or `cat /etc/resolv.conf`) on the server; `dig` from the server |
| "NXDOMAIN" right after creating a record | A negative answer was cached, or the record went in the wrong zone | `dig @authoritative-server name` |
| The whole domain stopped working | The domain registration expired, or the NS records at the registrar are wrong | `whois`, `dig NS domain +trace` |
| An app connects to an old address for hours after a change | The app caches DNS itself (some runtimes cache forever by default) | Restart the app; set the runtime's DNS cache TTL |
| A hand-edited `/etc/hosts` line overrides DNS | Someone added a test entry and forgot it | `grep name /etc/hosts`, `getent hosts name` |

`getent hosts name` asks the system the same way applications do (including `/etc/hosts`), so it's the best check of what an application on that machine will see.

## Practice

1. Use `dig` to find the A, AAAA (if any), MX, TXT and NS records for `itlearning.ng` and `itlearning.tech`. Write down the TTLs. Which provider runs their DNS, judging by the NS records?
2. Run `dig +trace` for one name and label each step in your learning log: root, top-level domain, authoritative.
3. Compare `dig +short` results for one busy name (for example `www.microsoft.com`) from `1.1.1.1` and `8.8.8.8`. Are the answers the same? Why might they differ?
4. Add a line to `/etc/hosts` mapping `test.local` to `127.0.0.1`. Show that `getent hosts test.local` and `ping -c1 test.local` use it, but `dig test.local` doesn't. Explain why, then remove the line.
5. Write a migration plan (5–8 steps, with times) to move `api.itlpay.example`, which has a TTL of 86400, from an AWS load balancer to an Azure one with no downtime.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [How a DNS Server (Domain Name System) works.](https://www.youtube.com/watch?v=mpQZVYPuDGU) · PowerCert Animated Videos · 6 min. How a DNS lookup works, step by step.
- [What is DNS? (and how it makes the Internet work)](https://www.youtube.com/watch?v=NiQTs9DbtW4) · NetworkChuck · 24 min. DNS in depth: records, resolvers and caching.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Introduction to Azure DNS](https://learn.microsoft.com/training/modules/intro-to-azure-dns/)
- [Host your domain on Azure DNS](https://learn.microsoft.com/training/modules/host-domain-azure-dns/)

**AWS (AWS Skill Builder):**

- [Amazon Route 53 - Basics](https://skillbuilder.aws/learn/XQA7PTD4D6/amazon-route-53--basics/Y4ERFCYTP1)
- [Amazon Route 53 Getting Started](https://skillbuilder.aws/learn/XJBJ1PF1R2/amazon-route-53-getting-started/J1VS14GBPM)

