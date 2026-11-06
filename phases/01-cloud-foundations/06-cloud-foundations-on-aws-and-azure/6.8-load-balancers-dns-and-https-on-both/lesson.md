## What you will be able to do

- Put a layer-7 load balancer in front of ITL Pay Lite on both clouds: an **Application Load Balancer** (AWS) and an **Application Gateway** (Azure).
- Configure target groups / backend pools, listeners, rules and **health probes** on `/health`.
- Serve **HTTPS** with a managed certificate (ACM; Key Vault or a managed certificate), and redirect HTTP to HTTPS.
- Point a DNS name at each load balancer with **Route 53** and **Azure DNS** alias records.
- Spread backends across two zones and show the service survives one server being stopped.
- Explain the other options (NLB, Azure Load Balancer, Front Door, CloudFront, WAF) and when each fits.

## Why this matters at work

The load balancer is the front door of almost every production web service: it's where TLS ends, where unhealthy servers are taken out of service, and where traffic is spread so one failed server doesn't become an outage. "Users get 502/503" (topic 2.4) is one of the most common incidents, and fixing it means reading target health, probes and security rules quickly. This topic completes the stack Capstone 1 asks you to build on both clouds.

## 1. The pieces

| Piece | AWS ALB | Azure Application Gateway |
| --- | --- | --- |
| The load balancer, in the public subnets/subnet | ALB (spans ≥2 AZ subnets) | Application Gateway v2 (its own dedicated subnet; zone-redundant when deployed across zones) |
| Where it listens | **Listener**: protocol + port (HTTPS:443, HTTP:80) | **Listener** with a frontend IP and port |
| Where traffic goes | **Target group** of instances/IPs on port 8080 | **Backend pool** of VMs/IPs, with **backend settings** (port 8080, protocol) |
| How it decides health | Target group **health check** (`/health`, interval, thresholds) | **Health probe** (`/health`, interval, thresholds) |
| Routing | **Listener rules** (path, host, header) | **Routing rules** (basic or path-based) |
| Certificate | From **ACM** | From **Key Vault** (via a managed identity) or uploaded |
| Web application firewall | **AWS WAF** attached to the ALB | **WAF_v2** SKU / WAF policy |

## 2. AWS: ALB in front of the app servers

Prepare: launch a second app VM in `app-b` (topic 6.5) so there are targets in two AZs.

```bash
tg=$(aws elbv2 create-target-group --name itlpay-tg --protocol HTTP --port 8080 --vpc-id "$vpc" \
      --health-check-path /health --health-check-interval-seconds 10 \
      --healthy-threshold-count 2 --unhealthy-threshold-count 3 --matcher HttpCode=200 \
      --query "TargetGroups[0].TargetGroupArn" --output text)
aws elbv2 register-targets --target-group-arn "$tg" --targets Id="$i_app_a" Id="$i_app_b"

alb=$(aws elbv2 create-load-balancer --name itlpay-alb --type application --scheme internet-facing \
      --subnets "$pub_a" "$pub_b" --security-groups "$sg_lb" \
      --query "LoadBalancers[0].LoadBalancerArn" --output text)

# HTTPS listener with an ACM certificate (request it first: section 4)
aws elbv2 create-listener --load-balancer-arn "$alb" --protocol HTTPS --port 443 \
  --certificates CertificateArn="$cert_arn" --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 \
  --default-actions Type=forward,TargetGroupArn="$tg"

# HTTP listener that only redirects to HTTPS
aws elbv2 create-listener --load-balancer-arn "$alb" --protocol HTTP --port 80 \
  --default-actions 'Type=redirect,RedirectConfig={Protocol=HTTPS,Port=443,StatusCode=HTTP_301}'
aws ec2 authorize-security-group-ingress --group-id "$sg_lb" --protocol tcp --port 80 --cidr 0.0.0.0/0

aws elbv2 describe-target-health --target-group-arn "$tg" \
  --query "TargetHealthDescriptions[].[Target.Id, TargetHealth.State, TargetHealth.Description]" --output table
```

Before you have a domain and certificate, you can test with an **HTTP:80 listener forwarding** to the target group and the ALB's DNS name (`aws elbv2 describe-load-balancers --query "LoadBalancers[0].DNSName"`), then switch to the HTTPS setup.

## 3. Azure: Application Gateway in front of the app servers

Application Gateway needs **its own subnet** (no other resources in it). Create it in the public range, and give it a **Standard** public IP:

```bash
az network vnet subnet create -g rg-itlpay-net --vnet-name itlpay-vnet -n appgw --address-prefixes 10.30.4.0/24 -o none
az network public-ip create -g rg-itlpay-net -n itlpay-agw-ip --sku Standard --zone 1 2 3 -o none

ip1=$(az vm show -d -g rg-itlpay-net -n itlpay-app-1 --query privateIps -o tsv)
ip2=$(az vm show -d -g rg-itlpay-net -n itlpay-app-2 --query privateIps -o tsv)

az network application-gateway create -g rg-itlpay-net -n itlpay-agw --sku Standard_v2 --capacity 1 \
  --vnet-name itlpay-vnet --subnet appgw --public-ip-address itlpay-agw-ip --zones 1 2 3 \
  --servers "$ip1" "$ip2" --http-settings-port 8080 --http-settings-protocol Http \
  --frontend-port 80 --priority 100 -o none

az network application-gateway probe create -g rg-itlpay-net --gateway-name itlpay-agw -n health \
  --protocol Http --host 127.0.0.1 --path /health --interval 10 --threshold 3 -o none
az network application-gateway http-settings update -g rg-itlpay-net --gateway-name itlpay-agw \
  -n appGatewayBackendHttpSettings --probe health -o none

az network application-gateway show-backend-health -g rg-itlpay-net -n itlpay-agw \
  --query "backendAddressPools[].backendHttpSettingsCollection[].servers[].[address,health]" -o table
```

Remember the NSG on the `app` subnet from topic 6.4: it allows 8080 **from the gateway's subnet**. Update that rule's source to `10.30.4.0/24` (the `appgw` subnet), or backend health will show *Unhealthy* with a timeout: exactly the "timed out, so it's a firewall" lesson from topic 2.6. Application Gateway v2 also needs inbound **65200–65535** from `GatewayManager` on its own subnet if you put an NSG there.

For HTTPS, add a listener on 443 with a certificate from **Key Vault** (the gateway reads it with a user-assigned managed identity that has *Key Vault Secrets User*), and a redirect from the port-80 listener to it. Application Gateway is billed per hour plus capacity units even when idle; it's the most expensive item in this module, so build, test and delete in one session.

## 4. Certificates and DNS

You need a domain you control for real HTTPS. Options for learners: a cheap domain from any registrar, or a subdomain your instructor delegates to you (for example `ada.labs.example`).

**AWS:**

```bash
# Request a certificate, validated by DNS (ACM gives you a CNAME to create)
cert_arn=$(aws acm request-certificate --domain-name api.ada.labs.example --validation-method DNS \
           --query CertificateArn --output text)
aws acm describe-certificate --certificate-arn "$cert_arn" \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord"
# Create that CNAME in Route 53 (the console's "Create records in Route 53" button does it in one click),
# then wait: aws acm wait certificate-validated --certificate-arn "$cert_arn"

# Alias record pointing the name at the ALB (no IP addresses to manage)
alb_dns=$(aws elbv2 describe-load-balancers --load-balancer-arns "$alb" --query "LoadBalancers[0].DNSName" --output text)
alb_zone=$(aws elbv2 describe-load-balancers --load-balancer-arns "$alb" --query "LoadBalancers[0].CanonicalHostedZoneId" --output text)
aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" --change-batch "{
  \"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"api.ada.labs.example\",\"Type\":\"A\",
  \"AliasTarget\":{\"HostedZoneId\":\"$alb_zone\",\"DNSName\":\"$alb_dns\",\"EvaluateTargetHealth\":true}}}]}"
```

**Azure:**

```bash
az network dns record-set a create -g rg-dns -z ada.labs.example -n api-az \
  --target-resource "$(az network public-ip show -g rg-itlpay-net -n itlpay-agw-ip --query id -o tsv)"
```

That's an **alias record set** pointing at the public IP resource, so the record follows it automatically (topic 2.3). For the certificate, create or import one in **Key Vault** (Key Vault can issue certificates through partner CAs, or import one from Let's Encrypt made with `certbot --manual --preferred-challenges dns`), and reference it from the HTTPS listener.

Test both:

```bash
curl -sv https://api.ada.labs.example/health 2>&1 | grep -E "subject:|expire date|HTTP/"
curl -sI http://api.ada.labs.example | head -3        # should be a 301 to https
```

## 5. Proving it's highly available

1. With both backends healthy, send 20 requests and check both servers answered (`docker logs itlpay` on each, or add the hostname to the response in a test build).
2. Stop the app on one server (`sudo systemctl stop itlpay`). Watch target health / backend health mark it unhealthy within about 30 seconds. Requests keep succeeding.
3. Stop the second one too. Users now get **503** (no healthy targets). Start one again and watch recovery.
4. Write down how long detection took, and how you'd shorten or lengthen it (interval × unhealthy threshold).

That's the essence of high availability: redundant servers in different zones, health checks that notice failure, and a load balancer that routes around it.

## 6. The other front doors

| Need | AWS | Azure |
| --- | --- | --- |
| HTTP routing, TLS, WAF in one region | ALB (+ AWS WAF) | Application Gateway (+ WAF) |
| Raw TCP/UDP, very high throughput, fixed IPs | **Network Load Balancer** | **Azure Load Balancer** (Standard) |
| Global entry point, caching at the edge, failover between regions | **CloudFront** (+ Route 53 failover/latency routing) | **Front Door** |
| Load balancing inside the network (app to internal service) | Internal ALB/NLB | Internal Load Balancer, internal Application Gateway |
| Containers on a managed platform | Built into App Runner; ALB with ECS | Built into Container Apps; ingress for AKS |

## 7. Tear down

Load balancers bill every hour. Delete the ALB, its listeners and target group; on Azure delete the Application Gateway and its public IP (or the whole resource group). Keep your scripts: Capstone 1 rebuilds all of this.

## Practice

1. Build the ALB with two targets in two AZs, first with HTTP only, and show both targets healthy. Then do the same with Application Gateway and two VMs.
2. Break the Azure backend health on purpose by leaving the app NSG's source as the old range. Diagnose it from backend health and IP flow verify, and fix it.
3. Add HTTPS with a real certificate on at least one cloud (both if you have a domain), plus the HTTP→HTTPS redirect. Check the certificate with `curl -v` or `openssl s_client`.
4. Run the high-availability test in section 5 on both clouds and record detection times.
5. Use the pricing calculators to estimate one month of your setup on each cloud (load balancer, two small VMs, smallest database, NAT gateway). Which items dominate?

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [Create an Application Load Balancer (ALB) in AWS | AWS Elastic Load Balancing Tutorial for Beginners](https://www.youtube.com/watch?v=ZGGpEwThhrM) · Tiny Technical Tutorials · 11 min. Creating an Application Load Balancer in AWS.
- [Introduction to Azure Application Gateway | AZ-104 | Episode 14](https://www.youtube.com/watch?v=53rKarX6e34) · Microsoft Learn · 9 min. Introduction to Azure Application Gateway, from Microsoft Learn.

## Further learning (free)

Free, self-paced courses from the two clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn and a free AWS Builder ID for AWS Skill Builder to track your progress.

**Azure (Microsoft Learn):**

- [Introduction to Azure Application Gateway](https://learn.microsoft.com/training/modules/intro-to-azure-application-gateway/)
- [Introduction to Azure DNS](https://learn.microsoft.com/training/modules/intro-to-azure-dns/)
- [Manage certificates and monitor Azure Key Vault](https://learn.microsoft.com/training/modules/manage-certificates-monitor-key-vault/)

**AWS (AWS Skill Builder):**

- [Application Load Balancer Getting Started](https://skillbuilder.aws/learn/72MYSKW681/application-load-balancer-getting-started/1TVTD6FGSD)
- [AWS Certificate Manager Getting Started](https://skillbuilder.aws/learn/P9ZA4PJ1RM/aws-certificate-manager-getting-started/CBRYCPRHHJ)
- [Amazon Route 53 Getting Started](https://skillbuilder.aws/learn/XJBJ1PF1R2/amazon-route-53-getting-started/J1VS14GBPM)

