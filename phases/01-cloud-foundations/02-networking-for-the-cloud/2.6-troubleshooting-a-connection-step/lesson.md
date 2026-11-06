## What you will be able to do

- Work through any "can't connect" problem with the same ordered method, from name to path to port to application.
- Choose the right tool for each step: `getent`/`dig`, `ping`/`traceroute`/`mtr`, `nc`/`curl`, `ss`, `tcpdump`, and the cloud's own tools.
- Tell from the symptom alone (timeout, refused, reset, TLS error, HTTP error) which layer to look at.
- Capture and read a small packet trace with `tcpdump` to prove where packets stop.
- Use the cloud providers' network diagnostics: AWS Reachability Analyzer and VPC Flow Logs, and Azure Network Watcher (IP flow verify, connection troubleshoot, NSG/VNet flow logs).
- Write up a connection incident clearly: symptom, evidence, cause, fix.

## Why this matters at work

Networking problems feel mysterious to people who poke at them randomly, and become routine for people with a method. In interviews for cloud and SRE roles, "a user says the site is slow / unreachable, walk me through what you do" is one of the most common questions, and the method in this topic is what interviewers want to hear. At work, it's how you avoid wasting an hour restarting things that were never broken.

## 1. The method: follow the request

Ask the questions in the order the request travels, and stop at the first one that fails:

| Step | Question | Tools |
| --- | --- | --- |
| 1. Name | Does the name resolve, to the address I expect, **from the machine that's failing**? | `getent hosts name`, `dig +short name` |
| 2. Path | Can packets get from here to there? | `ip route get addr`, `ping`, `traceroute`/`mtr`, cloud route tables |
| 3. Port | Is the port reachable, and is anything listening? | `nc -vz host port`, `curl -v telnet://host:port`; on the server, `ss -tlnp` |
| 4. Firewalls | Is a firewall dropping it on the way or at the target? | Security groups / NSGs, NACLs, `ufw status`, flow logs |
| 5. TLS | Does the TLS handshake succeed, with a valid certificate for this name? | `curl -v https://...`, `openssl s_client` |
| 6. Application | Does the app answer correctly? | `curl -i`, the app's logs (`journalctl -u app`) |

Two rules make the method work:

- **Test from where the failure is.** "It works from my laptop" proves little if the failing caller is a server in a private subnet. SSH (or Session Manager / Azure Bastion) to the caller and test from there.
- **Change one thing at a time**, and write down what you tried and what happened.

## 2. Reading the symptom

The exact error tells you which step to start at:

| Symptom | Most likely layer | Typical causes |
| --- | --- | --- |
| `Could not resolve host` / `NXDOMAIN` | Name | Missing record, wrong zone, private zone not linked to this network, typo |
| `Connection timed out` (no reply at all) | Path or firewall | Security group / NSG missing a rule, no route (private subnet without NAT), server off, wrong IP |
| `Connection refused` | Port, on the target | Nothing listening on that port, or it listens on `127.0.0.1` only |
| `Connection reset by peer` | Target or something in between | App crashed mid-request, a proxy or firewall closed it, protocol mismatch |
| `SSL certificate problem` / `certificate has expired` / name mismatch | TLS | Expired certificate, missing intermediate, wrong name, clock wrong on the client |
| `HTTP 502 / 503 / 504` | Application, behind a load balancer | App down, unhealthy targets, app too slow (topic 2.4) |
| Works sometimes, fails sometimes | Several | One bad server behind a load balancer, DNS returning several addresses with one broken, intermittent packet loss |

## 3. The tools, step by step

**Name:**

```bash
getent hosts db.internal.itlpay      # what this machine's applications will get
dig +short db.internal.itlpay        # what DNS says (bypasses /etc/hosts)
```

**Path:**

```bash
ip route get 10.20.48.9              # which route and interface will be used
ping -c 3 10.20.48.9                 # may be blocked on purpose; no reply isn't proof
mtr -n -c 20 api.partnerbank.example # where along the path packets are lost
```

**Port:** `nc` (netcat) opens a TCP connection and reports the result without sending anything:

```bash
nc -vz -w 3 10.20.48.9 5432          # -z: just test; -w 3: give up after 3 seconds
# "succeeded" / "open"  → the path and firewall allow it, and something listens
# "Connection refused"  → reached the machine, nothing listening there
# timeout               → dropped on the way: firewall or route
```

On the target server:

```bash
sudo ss -tlnp | grep 5432            # is it listening, and on which address?
sudo ufw status                      # the machine's own firewall
```

**TLS and application:**

```bash
curl -v https://api.itlpay.example/health
curl -sv --resolve api.itlpay.example:443:10.20.0.15 https://api.itlpay.example/health   # test one specific target
```

## 4. tcpdump: seeing the packets

When you can't tell where packets stop, look at them. `tcpdump` prints the packets passing through a network interface:

```bash
sudo tcpdump -i any -n port 5432                 # all packets to or from port 5432
sudo tcpdump -i any -n host 10.20.16.7 and port 8080
sudo tcpdump -i any -n -c 20 'tcp[tcpflags] & tcp-syn != 0'   # only connection attempts
sudo tcpdump -i any -n port 443 -w capture.pcap  # save to a file for Wireshark
```

How to read a TCP connection in the output:

```text
10.20.16.7.51734 > 10.20.48.9.5432: Flags [S]      ← client: SYN (let's connect)
10.20.48.9.5432 > 10.20.16.7.51734: Flags [S.]     ← server: SYN-ACK (OK)
10.20.16.7.51734 > 10.20.48.9.5432: Flags [.]      ← client: ACK (connected)
```

What different results mean, running `tcpdump` on the **server**:

- **No SYN arrives:** the packet is dropped before the server: a cloud firewall rule, a route, or the client is sending to the wrong address.
- **SYN arrives, server replies with `[R]` (reset):** nothing listening on that port: "connection refused".
- **SYN arrives, no reply at all:** the server's own firewall drops it, or the reply goes out by a different route.
- **Full handshake, then a reset or silence:** look at the application, TLS or a proxy.

Captures can contain sensitive data (tokens, personal data in plain HTTP). Capture only what you need, store captures safely, and delete them afterwards.

## 5. The cloud's own network tools

In the cloud you can't run `tcpdump` on the provider's routers, but the providers give you tools that answer the same questions:

| Question | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| "Would traffic from A reach B on this port, given my routes and rules?" (no traffic needed) | **Reachability Analyzer** | **Network Watcher: IP flow verify** (checks NSG rules) and **connection troubleshoot** | **Connectivity Tests** (Network Intelligence Center) |
| "Which rule allowed or blocked real traffic?" | **VPC Flow Logs** (accepted and rejected connections) | **VNet flow logs** (replacing NSG flow logs) | **VPC Flow Logs** and **Firewall Rules Logging** |
| "Which route applies to this machine?" | The subnet's route table; Reachability Analyzer shows the path | **Network Watcher: next hop**, and **effective routes** on the network interface | The VPC's routes; Connectivity Tests show the path |
| "Which security rules apply to this machine, all combined?" | The instance's security groups plus the subnet's NACL | **Effective security rules** on the network interface | The VPC firewall rules that target the VM (by tag or service account), plus firewall policies |
| "Capture packets" | **Traffic Mirroring** (on supported instances) | **Network Watcher packet capture** | **Packet Mirroring** |

A flow log line that says **REJECT** for your connection is the cloud equivalent of "no SYN arrives": a rule is dropping it. Topic 6.4 has you turn flow logs on and find a dropped connection in them.

## 6. A worked example

**Ticket:** "Since this morning's change, the payments app can't reach the database. Error: `connection timed out` to `db.internal.itlpay:5432`."

1. **From the app server**, `getent hosts db.internal.itlpay` → `10.20.48.9`. That's the database's address. Name: fine.
2. `ip route get 10.20.48.9` → local network route. Path inside the VPC: fine.
3. `nc -vz -w 3 10.20.48.9 5432` → times out. Timeout, not refused: suspect a firewall.
4. On the database side (managed database, so no `tcpdump`), check the **database's security group**. Its inbound rule allows 5432 from the security group `sg-app-old`. This morning's change moved the app servers to a new group, `sg-app`.
5. **Fix:** allow 5432 from `sg-app` (and remove `sg-app-old` once nothing uses it). Re-test: `nc` succeeds, the app connects.
6. **Write-up:** "Symptom: timeouts from app to database after the security group change at 08:10. Evidence: DNS and route correct, `nc` timed out, database SG allowed only the old app SG. Cause: the database rule wasn't updated when the app moved to the new SG. Fix: allowed 5432 from `sg-app` at 09:02. Prevention: manage both groups in the same Terraform change (Phase 2) and add a connectivity check to the deployment."

Notice what the engineer **didn't** do: restart the database, reboot the app server, or open 5432 to the whole network to "see if it helps".

## Practice

1. On your machine, run a test server (`python3 -m http.server 8000 --bind 127.0.0.1`). From the same machine, test it with `nc -vz` and `curl` on `127.0.0.1` and on your machine's network IP. Explain both results using section 2.
2. Run `sudo tcpdump -i any -n port 8000` in one terminal and repeat exercise 1 in another. Find the SYN, SYN-ACK and ACK, and the reset for the failing case.
3. Turn on the machine's firewall (`sudo ufw enable`), block port 8000 (`sudo ufw deny 8000`), bind the server to `0.0.0.0`, and test from another machine or container. Is it refused or timed out? Undo the rule.
4. Answer the ticket: "From a server in the private subnet, `curl https://api.paystack.co` hangs and then times out, but `curl http://10.20.16.9:8080` (another private server) works." Write your steps and the three most likely causes.
5. Write your own one-page "can't connect" checklist in your learning log. You'll reuse it in every lab in Module 6.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [Linux for Programmers #6 | Networking Commands](https://www.youtube.com/watch?v=vDWY3PuHMX8) · Akamai Developers · 14 min. Linux networking commands for troubleshooting.
- [Basic Linux Network Troubleshooting](https://www.youtube.com/watch?v=PVOuff-p420) · Cumulus Networks · 7 min. A basic Linux network troubleshooting routine.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Troubleshoot network security issues with Microsoft Azure](https://learn.microsoft.com/training/modules/troubleshoot-network-security-issues/)

**AWS (AWS Skill Builder):**

- [Amazon Virtual Private Cloud (Amazon VPC) - Troubleshooting](https://skillbuilder.aws/learn/YHWW7BTY89/amazon-virtual-private-cloud-amazon-vpc--troubleshooting/YTMMRFE2KJ)
- [Elastic Load Balancing (ELB) - Troubleshooting](https://skillbuilder.aws/learn/5R5Q9TN3H4/elastic-load-balancing-elb--troubleshooting/GZTEH5S7D2)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Networking in Google Cloud: Routing and Addressing](https://www.skills.google/course_templates/36)

