## What you will be able to do

- Read an HTTP request and response: method, path, headers, status code and body.
- Explain what each family of status codes means, and which side (client, server or something in between) is usually at fault.
- Use `curl` to test an API like an engineer: headers, methods, JSON bodies, timings and redirects.
- Explain what TLS does, how a certificate proves a server's identity, and what a certificate chain is.
- Inspect a site's certificate and find when it expires, with `openssl` and `curl`.
- Get free certificates (Let's Encrypt) and managed certificates (AWS Certificate Manager, Azure Key Vault and App Service), and explain where TLS ends in a cloud setup.

## Why this matters at work

Almost everything you'll run speaks HTTP: web apps, APIs, health checks, cloud provider APIs, webhooks from payment providers. Status codes tell you where to look: a `502` points at the load balancer and the app behind it, a `403` at permissions. Expired certificates are a famous cause of outages, even at the largest companies, because a certificate works perfectly for a year and then fails all at once. Regulators and card schemes (for example PCI DSS for card payments) require encryption in transit, so HTTPS everywhere is a requirement, not a nice-to-have.

## 1. HTTP: a request and a response

HTTP is a text conversation. The client sends a **request**:

```text
POST /api/v1/transfers HTTP/1.1
Host: api.itlpay.example
Content-Type: application/json
Authorization: Bearer eyJhbGciOi...
Content-Length: 61

{"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 500000}
```

- The **method** says what to do: `GET` (read), `POST` (create or act), `PUT` (replace), `PATCH` (change part), `DELETE` (remove).
- The **path** says what to act on.
- **Headers** add information: which site (`Host`, so one server can host many sites), the body's format, credentials, caching rules.
- The **body** carries data, often JSON.

The server sends back a **response**:

```text
HTTP/1.1 201 Created
Content-Type: application/json
Location: /api/v1/transfers/TRF-88231

{"id": "TRF-88231", "status": "PENDING"}
```

HTTP itself is **stateless**: each request stands alone. Logins are carried by cookies or tokens sent with every request.

## 2. Status codes

| Range | Meaning | Common codes and what they usually point to |
| --- | --- | --- |
| 1xx | Information | Rarely seen directly |
| 2xx | Success | `200 OK`, `201 Created`, `204 No Content` |
| 3xx | Redirect: look elsewhere | `301` moved permanently, `302`/`307` temporary, `304` not modified (use your cache) |
| 4xx | **The client** did something wrong | `400` bad request (invalid data), `401` not authenticated (no or bad credentials), `403` forbidden (authenticated but not allowed), `404` not found, `409` conflict, `429` too many requests (rate limited) |
| 5xx | **The server side** failed | `500` the application crashed or threw an error, `502` bad gateway (the proxy or load balancer got a bad or no answer from the app), `503` service unavailable (overloaded, or no healthy servers), `504` gateway timeout (the app took too long) |

For a cloud engineer, the 5xx codes from a load balancer are the important ones:

- **502** from a load balancer: the app behind it closed the connection, crashed, or speaks something other than what the load balancer expects (for example HTTP to an HTTPS port).
- **503**: often **no healthy targets**: every server failed its health check (topic 2.5).
- **504**: the app is up but too slow; look at the app, its database, and timeouts.

## 3. curl: the engineer's HTTP client

```bash
curl https://itlearning.tech                            # GET, print the body
curl -I https://itlearning.tech                         # headers only (a HEAD request)
curl -i https://itlearning.tech                         # headers and body
curl -L http://itlearning.tech                          # follow redirects
curl -v https://itlearning.tech -o /dev/null            # verbose: DNS, TCP, TLS, headers
curl -s -o /dev/null -w "%{http_code}\n" https://itlearning.tech   # just the status code

# Send JSON
curl -X POST https://httpbin.org/post \
  -H "Content-Type: application/json" \
  -d '{"amount_kobo": 500000}'

# Where does the time go?
curl -s -o /dev/null -w "dns %{time_namelookup}s  connect %{time_connect}s  tls %{time_appconnect}s  first byte %{time_starttransfer}s  total %{time_total}s\n" https://itlearning.tech
```

The timing line splits a slow request into DNS, TCP connection, TLS handshake, waiting for the server, and total. If "first byte" is large but connect and TLS are quick, the application is slow; if TLS is slow, look at the network or certificate setup.

`curl --resolve api.itlpay.example:443:203.0.113.10 https://api.itlpay.example/health` sends a request to a specific IP address while keeping the right name, which is how you test a new server **before** changing DNS (topic 2.3).

## 4. HTTPS and TLS

Plain HTTP sends everything, passwords included, as readable text that anyone on the path (a café Wi-Fi, an ISP, a compromised router) can read or change. **HTTPS** is HTTP inside **TLS** (Transport Layer Security), which gives three things:

- **Encryption:** nobody in between can read the traffic.
- **Integrity:** nobody can change it without being detected.
- **Authentication:** the server proves it really is `api.itlpay.example`, using a **certificate**.

When a connection starts, client and server do a **TLS handshake**: they agree on the TLS version (use TLS 1.2 or 1.3; older versions are insecure and should be off) and encryption methods, the server presents its certificate, and they agree on keys for the session.

## 5. Certificates and the chain of trust

A **certificate** is a signed statement: "this public key belongs to `api.itlpay.example`, valid from 1 May to 30 July". It includes:

- the **names** it covers (the *Subject Alternative Names*, such as `api.itlpay.example` and `www.itlpay.example`; a **wildcard** `*.itlpay.example` covers one level of subdomains);
- **validity dates**: not before and not after;
- the **issuer**: the **certificate authority (CA)** that signed it;
- the server's **public key**. The matching **private key** stays on the server (or in the load balancer or a key vault) and must be protected like an SSH private key.

Why does a browser believe the certificate? It's signed by an **intermediate CA**, which is signed by a **root CA** that the browser or operating system already trusts. Server → intermediate → root is the **chain**. The server must send its certificate **and** the intermediates; a missing intermediate is a common mistake that works in some browsers and fails in others and in `curl`.

Before issuing, the CA checks that you control the domain, usually by asking you to put a file on the web server (HTTP-01) or a **TXT record** in DNS (DNS-01).

Inspect a certificate:

```bash
# Who issued it, which names, and when it expires
echo | openssl s_client -connect itlearning.tech:443 -servername itlearning.tech 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

# The whole chain the server sends
echo | openssl s_client -connect itlearning.tech:443 -servername itlearning.tech -showcerts 2>/dev/null | grep -E "s:|i:"

# Days until expiry, the quick way
curl -sv https://itlearning.tech -o /dev/null 2>&1 | grep -i "expire date"
```

## 6. Getting certificates

| Option | Cost | Renewal | Where it's used |
| --- | --- | --- | --- |
| **Let's Encrypt** (with `certbot` or Caddy) | Free | Automatic, every 60–90 days | Your own servers, VMs, Kubernetes (with cert-manager, Phase 2) |
| **AWS Certificate Manager (ACM)** | Free for use with AWS load balancers, CloudFront and API Gateway | Automatic | AWS load balancers; you can't download the private key |
| **Azure**: App Service managed certificates, Front Door managed certificates, or certificates in **Key Vault** | Free managed options; Key Vault can also hold certificates from a CA you pay | Automatic for managed ones; Key Vault can auto-renew with partner CAs | App Service, Front Door, Application Gateway (which reads the certificate from Key Vault) |
| **Google Cloud**: Google-managed certificates and **Certificate Manager** | Free with Google Cloud load balancers | Automatic | Google Cloud load balancers; issued once DNS points at the load balancer |
| Paid CA (for extended validation or company policy) | Paid | Manual or semi-automatic | Some banks and regulated companies |

The rule: **automate renewal**. Manual renewals are how certificates expire. Even with automation, monitor expiry (Phase 3) and alert 30 days ahead.

On a Linux VM with nginx, Let's Encrypt takes two commands, once DNS points at the server and port 80 is open:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d app.example.com
```

`certbot` gets the certificate, configures nginx, and installs a timer that renews it automatically (`systemctl list-timers | grep certbot`).

## 7. Where TLS ends: termination

In the cloud, you choose where the encrypted connection is decrypted (**terminated**):

- **At the load balancer** (most common): the load balancer holds the certificate, decrypts, and sends plain HTTP to the app servers inside the private network. Simple, and the certificate is managed in one place (ACM, Key Vault or Google Certificate Manager).
- **At the load balancer, then encrypted again** to the app servers: required by many banks and by PCI DSS rules for card data, so traffic is never plain text, even inside the network.
- **Passed through to the app**: the load balancer forwards encrypted traffic untouched (a layer-4 load balancer) and the app holds the certificate.

Whichever you choose, redirect HTTP to HTTPS (`301`), and add the `Strict-Transport-Security` header so browsers stop trying plain HTTP at all.

## Practice

1. Use `curl -s -o /dev/null -w "%{http_code}\n"` to get the status codes of `http://itlearning.tech`, `https://itlearning.tech` and `https://itlearning.tech/no-such-page`. Explain each.
2. Use the timing command from section 3 on three sites (one in Nigeria, one in Europe, one in the United States). Where does each spend its time?
3. Find the issuer, the names covered and the expiry date of the certificates for `itlearning.tech` and `github.com`. Which CA issued each? How many days are left?
4. Send a JSON `POST` to `https://httpbin.org/post` and find your body echoed back in the response. Then send it with a wrong `Content-Type` and compare.
5. In your learning log, explain to a non-technical manager, in five sentences, why the payments API must use HTTPS and what happens if its certificate expires.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [SSL, TLS, HTTPS Explained](https://www.youtube.com/watch?v=j9QmMEWmcfo) · ByteByteGo · 6 min. SSL, TLS and HTTPS in under six minutes.
- [HTTP Status Codes Explained In 5 Minutes](https://www.youtube.com/watch?v=qmpUfWN7hh4) · ByteByteGo · 5 min. HTTP status codes and what each family means.
- [TLS Handshake Explained - Computerphile](https://www.youtube.com/watch?v=86cQJ0MMses) · Computerphile · 17 min. The TLS handshake, explained carefully.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Manage certificates and monitor Azure Key Vault](https://learn.microsoft.com/training/modules/manage-certificates-monitor-key-vault/)

**AWS (AWS Skill Builder):**

- [AWS Certificate Manager Getting Started](https://skillbuilder.aws/learn/P9ZA4PJ1RM/aws-certificate-manager-getting-started/CBRYCPRHHJ)
- [Automate certificates with ACME support in AWS Certificate Manager](https://skillbuilder.aws/learn/8539TFPHDF/automate-certificates-with-acme-support-in-aws-certificate-manager/C6K59ZQ86M)

