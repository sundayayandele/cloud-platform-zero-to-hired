## What you will be able to do

- Build a cost model for one system on AWS, Azure and Google Cloud from its architecture, not from guesses.
- Use the clouds' pricing calculators and public price APIs, and know which costs are easy to miss.
- Show how much each optimisation saves, and why fixed costs limit what compute discounts can do.
- Compare clouds on more than price: skills, services, regions, support, compliance and lock-in.
- Make and defend a cloud choice (one cloud, or more) in a short decision record.

## Why this matters at work

"Which cloud should we use?" is asked at every company, and usually answered by habit or by whichever salesperson called last. An engineer who can model the cost of the same system on three clouds, explain where the differences come from, and weigh them against skills, regions and regulation, is the person leadership listens to. It's also a classic senior interview question ("would you run this on one cloud or two, and why?"), and you'll answer it in Capstone 3.

## 1. Model the architecture, then price it

Start from what the system needs, as quantities. ITL Pay's architecture from Capstone 2, per environment:

| Component | Quantity |
| --- | --- |
| Kubernetes cluster | 1 managed control plane |
| Worker nodes | 3 × (2 vCPU, 8 GiB), one per zone |
| Load balancer | 1 (one shared Gateway) |
| NAT | 1 gateway, ~200 GB a month through it |
| Database | 1 small managed PostgreSQL, 50 GB storage |
| Internet egress | ~300 GB a month |

`labs/finops/compare/compare_costs.py` multiplies these quantities by unit prices from `prices.json` for each cloud, before and after optimisation:

```bash
cd labs/finops/compare
python3 compare_costs.py                       # 50% spot, 70% of the rest committed, nodes rightsized to 70%
python3 compare_costs.py --hours 0.36          # the same, plus a weekdays 08:00-20:00 schedule (non-production)
```

**The prices in `prices.json` are illustrative**: only the cluster management fees (US$0.10 an hour on all three, before GKE's free-tier credit and AKS's free tier) are published list prices; the rest are placeholders of a realistic size. The first exercise is to replace them with your region's real figures. The model, not the numbers, is what you learn here.

## 2. Where the prices come from

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Calculator | AWS Pricing Calculator | Azure Pricing Calculator | Google Cloud Pricing Calculator |
| Machine-readable prices | Price List API and bulk files | **Retail Prices API** (public, no sign-in: `https://prices.azure.com/api/retail/prices`) | Cloud Billing Catalog API (needs an API key) |
| Your real prices (with discounts) | Cost and Usage Report | Cost Management exports | BigQuery billing export |

Things learners (and many companies) forget to price:

- **Data transfer**: internet egress, traffic between zones and regions, NAT processing per GB.
- **Managed control planes and gateways**: per hour, even when idle.
- **Logs and metrics**: ingestion per GB (topic 11.2) often rivals compute.
- **Support plans**: production support is often a percentage of the bill.
- **African regions are often priced higher** than the largest US and European regions for the same service, so always price the region you'll actually use.

## 3. What the model teaches

With the lab's prices, compute optimisations alone (half the nodes on spot, 70% of the rest committed, nodes rightsized by 30%) cut the bill by **27% on AWS, 31% on Azure and 28% on Google Cloud**. They don't reach 30% everywhere, because in a small system the **fixed costs** (the cluster fee, NAT, the load balancer, the database) are a large share, and compute discounts don't touch them. The model's tests encode exactly this:

```python
def test_compute_discounts_alone_dont_reach_30_percent_somewhere(): ...
def test_adding_a_working_hours_schedule_reaches_30_percent_everywhere(): ...
```

Adding a working-hours schedule for non-production (running about 36% of the month) brings the saving to **53–56%** on all three. Lessons that hold with real prices too:

1. **Know your cost structure before optimising.** If fixed costs dominate, discounts on compute barely move the total; architecture and scheduling do.
2. **Schedules are for non-production; commitments are for production.** Committing to capacity you switch off at night wastes the commitment.
3. **Differences between clouds are usually smaller than differences in how you use them.** A well-run system on the "expensive" cloud often beats a careless one on the "cheap" one.

## 4. More than price

| Factor | Questions |
| --- | --- |
| **Skills** | Which cloud does the team know? Which can you hire for locally? Training time is a real cost |
| **Services** | Does one cloud have a managed service you'd otherwise build (a database feature, an AI model, a regional service)? |
| **Regions and latency** | Where are your users? South Africa has full regions on all three; West and East Africa rely on nearby regions or edge locations (topic 15.2) |
| **Compliance** | Does a regulator or customer require a provider, a region, or certifications (topic 15.2)? |
| **Support and partners** | Local partners, support response times, account teams that answer |
| **Credits and commercial terms** | Startup programmes give substantial credits; enterprise agreements change prices |
| **Lock-in** | How hard would it be to leave? Kubernetes, Terraform, OpenTelemetry and PostgreSQL (all used in this course) keep you portable; proprietary databases and serverless platforms tie you closer |

**One cloud or two?** Multi-cloud adds cost and complexity: two sets of skills, tools, networks, security models and bills. It's worth it when there's a reason: regulation, a customer requirement, a service only one cloud has, real resilience requirements (topic 13.4), or negotiating leverage at large scale. "Avoiding lock-in" alone is rarely enough; portable tools (as in this course) give most of that benefit while running on one cloud.

## 5. Write the decision down

Use an architecture decision record (topic 4.3):

```markdown
# ADR 0007: Production cloud for ITL Pay

## Context
Customers in South Africa and Nigeria; data must stay in South Africa (POPIA, NDPA transfer rules); a team of six
with AWS experience; expected 2 million transfers a month in year one.

## Options
AWS af-south-1, Azure South Africa North, Google Cloud africa-south1: cost model (compare_costs.py with calculator
prices, attached), services, skills, support.

## Decision
...

## Consequences
What we gain, what we give up, and what would make us revisit it (a new region, a price change, a customer requirement).
```

## Practice

1. Replace `prices.json` with real figures from the three pricing calculators for your chosen regions (note the date and the exact SKUs). Run the model and compare with the illustrative numbers.
2. Query Azure's Retail Prices API for a D2s v5 VM in South Africa North (`$filter=serviceName eq 'Virtual Machines' and armRegionName eq 'southafricanorth' and skuName eq 'D2s v5'`) and compare it with the calculator.
3. Add data transfer between zones to the model (`inter_zone_gb`), with a test, and see how much a chatty three-zone deployment adds.
4. Use the model to answer: at what monthly transfer volume does it pay to commit to a year of capacity on your chosen cloud?
5. Write ADR 0007 for ITL Pay, with your cost model attached, and defend it in the forum against a classmate who chose differently.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [AWS Pricing Calculator—in 10 minutes](https://www.youtube.com/watch?v=GNxDPdTwA90) · Tech With Piotr · 11 min. Building an estimate with the AWS Pricing Calculator.
- [Choosing the Right Cloud Provider | AWS vs Azure vs GCP](https://www.youtube.com/watch?v=bNssnH9N37s) · Cynoteck Technology Solutions · 3 min. Factors for choosing between AWS, Azure and Google Cloud.
- [AWS, Azure, or Google Cloud: Which One is Best for YOUR Needs?](https://www.youtube.com/watch?v=w-2VFTnF0rA) · the IT videos · 4 min. Comparing the three clouds by need, not only price.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Describe cost management in Azure (Pricing and TCO calculators)](https://learn.microsoft.com/training/modules/describe-cost-management-azure/)
- [Microsoft Azure Well-Architected Framework - Cost Optimization](https://learn.microsoft.com/training/modules/azure-well-architected-cost-optimization/)

