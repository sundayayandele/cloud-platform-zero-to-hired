## What you will be able to do

- Explain, in plain words, how a request travels from a phone in Lagos to a server in a cloud data centre and back.
- Describe the layers of networking (link, internet, transport, application) and which problems live at each one.
- Explain what an IP address, a packet, a port and a socket are.
- Compare TCP and UDP, and say which common services use which.
- Name the well-known ports you'll meet every week (22, 53, 80, 443, 5432 and others).
- See which programs on a machine are listening, and on which ports, with `ss`.

## Why this matters at work

"It can't connect" is the second most common ticket after "it's down". To fix it you need to know which layer is failing: is there a network path at all, is the right port open, is anything listening, or is the application refusing the request? Cloud firewalls (AWS security groups, Azure network security groups) are written in exactly the terms of this topic: protocol, port and address. Get them wrong and either nothing works or everything is exposed.

## 1. A request's journey

Ada opens a banking app in Lagos and taps **Transfer**. In about a quarter of a second:

1. The app needs the address of `api.itlpay.example`. It asks a **DNS** server, which answers with an IP address (topic 2.3).
2. The phone opens a **TCP connection** to that IP address on **port 443** (HTTPS).
3. The request is cut into **packets**. Each packet carries the source and destination IP addresses.
4. Packets hop from the phone to the mobile network, across the internet through many **routers**, into the cloud provider's network and to a **load balancer** (topic 2.5).
5. The load balancer passes the request to one of several servers running the payments service.
6. The service answers; the reply travels back the same way, in packets, and the app shows "Transfer sent".

Each step can fail, and each failure looks different. This module teaches you to tell them apart.

## 2. Layers: a way to think about failures

Networking is described in **layers**. Each layer does one job and relies on the one below. The full OSI model has seven layers; for daily work, the four-layer TCP/IP model is enough:

| Layer | Job | Examples | What failure looks like |
| --- | --- | --- | --- |
| Application | What the programs say to each other | HTTP, DNS, SSH, PostgreSQL protocol | "404 Not Found", "invalid password", wrong JSON |
| Transport | Getting data between two programs, with ports | TCP, UDP | "Connection refused", "connection timed out" |
| Internet | Getting packets between two machines, across networks | IP, ICMP (ping), routing | "No route to host", "network unreachable" |
| Link | Getting frames across one local network | Ethernet, Wi-Fi, MAC addresses | No Wi-Fi, a cable unplugged, a virtual network interface missing |

Engineers often say "layer 4" (transport) and "layer 7" (application), from the OSI numbering: an AWS **Network** Load Balancer works at layer 4, an **Application** Load Balancer at layer 7. Topic 2.5 explains the difference.

When something can't connect, work **from the bottom up**: is there a path (internet layer)? Is the port reachable (transport)? Does the application answer correctly (application)?

## 3. IP addresses and packets

Every device on a network has an **IP address**. The most common form is **IPv4**: four numbers from 0 to 255, such as `102.89.34.11`. There are only about 4.3 billion IPv4 addresses, which isn't enough for everyone, so:

- **private addresses** (such as `10.0.1.25` or `192.168.1.10`) are used inside homes, offices and cloud networks, and can be reused by everyone (topic 2.2);
- **NAT** lets many private devices share one public address (topic 2.5);
- **IPv6** addresses, such as `2001:db8:1::25`, are long enough for every device on Earth. AWS and Azure both support IPv6, and some mobile networks in Africa already use it.

Data travels in **packets**: chunks of usually up to 1,500 bytes, each with a header saying where it comes from and where it's going. Packets can arrive out of order, be delayed, or be lost. The transport layer deals with that.

```bash
ip addr          # your machine's addresses (look for "inet")
ip route         # where packets go: the "default via" line is your gateway
ping -c 4 1.1.1.1      # is there a path to this address? (ICMP echo)
```

`ping` is useful but limited: many cloud servers block ping on purpose, so "no ping reply" doesn't always mean "no path".

## 4. Ports: which program on the machine?

An IP address gets a packet to the right **machine**. A **port** (a number from 0 to 65535) gets it to the right **program** on that machine. A web server **listens** on port 443; when your request arrives at that port, the operating system hands it to the web server.

A connection is identified by four things: source IP, source port, destination IP and destination port. Your side uses a random high-numbered port (for example 51734), so one laptop can hold hundreds of connections to the same server at once.

Ports you'll meet every week:

| Port | Protocol | Service |
| --- | --- | --- |
| 22 | TCP | SSH |
| 53 | UDP and TCP | DNS |
| 80 | TCP | HTTP (unencrypted web) |
| 443 | TCP (and UDP for HTTP/3) | HTTPS |
| 3306 | TCP | MySQL |
| 5432 | TCP | PostgreSQL |
| 6379 | TCP | Redis |
| 8080 | TCP | Common for application servers behind a load balancer |
| 3389 | TCP | Windows Remote Desktop (RDP) |

Ports below 1024 are **privileged**: only `root` can listen on them. That's one reason applications often listen on 8080 and a load balancer or reverse proxy takes 443.

## 5. TCP and UDP

The two main transport protocols make different promises.

**TCP** (Transmission Control Protocol) is **reliable**: before data flows, the two sides agree to talk with a three-step **handshake** (SYN, SYN-ACK, ACK). Every piece of data is numbered and acknowledged; anything lost is sent again; everything arrives in order. Most things you'll run use TCP: HTTP and HTTPS, SSH, databases.

**UDP** (User Datagram Protocol) just sends packets, with no handshake, no acknowledgements and no resending. It's faster and simpler, and used where speed matters more than perfection, or where the application handles losses itself: DNS lookups, video calls, online games, and HTTP/3 (QUIC).

Knowing TCP's handshake explains the two most common connection errors:

| Error | What happened | Usual cause |
| --- | --- | --- |
| **Connection refused** | The packet reached the machine, but nothing was listening on that port, so the machine replied "no" (a TCP reset) | The service isn't running, or listens on a different port or address |
| **Connection timed out** | No reply came back at all | A firewall dropped the packet silently, the route is wrong, or the machine is off |

"Refused" is good news: you reached the machine. "Timed out" usually means a firewall, such as a security group or network security group missing a rule.

## 6. What's listening on this machine?

```bash
sudo ss -tlnp
```

The options mean TCP (`-t`), listening sockets (`-l`), numbers instead of names (`-n`) and the process (`-p`). Typical output:

```text
State   Recv-Q Send-Q Local Address:Port  Peer Address:Port Process
LISTEN  0      4096   127.0.0.1:5432      0.0.0.0:*         users:(("postgres",pid=812))
LISTEN  0      511    0.0.0.0:80          0.0.0.0:*         users:(("nginx",pid=930))
LISTEN  0      128    0.0.0.0:22          0.0.0.0:*         users:(("sshd",pid=701))
```

Read the **local address** carefully:

- `0.0.0.0:80` (or `[::]:80` for IPv6) means "on every network interface": reachable from other machines, if the firewall allows it.
- `127.0.0.1:5432` means **localhost only**: reachable from this machine and nowhere else.

A very common ticket: "the app works on the server with `curl localhost:8080`, but not from the load balancer". The answer is often that the app listens on `127.0.0.1` instead of `0.0.0.0`.

Use `sudo ss -ulnp` for UDP, and `ss -tnp` (without `-l`) to see current connections.

## Practice

1. Run `ip addr` and `ip route`. Write down your machine's IP address and its default gateway.
2. Run `sudo ss -tlnp`. List each listening port, its process, and whether it's reachable from other machines or localhost only.
3. Start a test server on localhost only: `python3 -m http.server 8000 --bind 127.0.0.1`. In another terminal, try `curl localhost:8000` and `curl <your-ip>:8000`. Explain the difference. Then restart it with `--bind 0.0.0.0` and try again.
4. Run `curl -v telnet://localhost:9999` (or `nc -vz localhost 9999`) against a port where nothing is listening. Which error do you get, and what does it tell you?
5. Draw Ada's transfer from section 1 in your learning log (a photo of a paper sketch is fine), marking where DNS, TCP, the load balancer and the payments service come in.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [what is TCP/IP and OSI? // FREE CCNA // EP 3](https://www.youtube.com/watch?v=CRdL1PcherM) · NetworkChuck · 12 min. The TCP/IP and OSI models explained with real examples.
- [TCP vs UDP Comparison](https://www.youtube.com/watch?v=uwoD5YsGACg) · PowerCert Animated Videos · 5 min. TCP and UDP compared, with animations.

## Further learning (free)

Free, self-paced courses from the two clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn and a free AWS Builder ID for AWS Skill Builder to track your progress.

**Azure (Microsoft Learn):**

- [Introduction to Azure Virtual Networks](https://learn.microsoft.com/training/modules/introduction-to-azure-virtual-networks/)

**AWS (AWS Skill Builder):**

- [AWS Networking Basics](https://skillbuilder.aws/learn/S1VYRYHD8V/aws-networking-basics/SKP7248UVF)

