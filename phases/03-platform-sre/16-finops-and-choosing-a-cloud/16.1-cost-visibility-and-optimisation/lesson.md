## What you will be able to do

- Explain FinOps: shared responsibility for cloud cost between engineering, finance and product.
- Make costs visible: tags and labels, cost allocation, budgets and anomaly alerts on AWS, Azure and Google Cloud.
- Allocate Kubernetes costs to teams and services with OpenCost.
- Optimise in the right order: remove waste, rightsize, schedule, then buy discounts (spot, commitments).
- Read unit economics: cost per transfer, per customer, per team.

## Why this matters at work

Cloud bills surprise every company eventually: a forgotten cluster, a chatty log pipeline, data leaving a region, a load balancer per service. In African markets, where revenue is often in naira, cedis or shillings and the bill is in dollars, cost is a survival issue, not a detail. FinOps practitioners, and engineers who can explain and cut their own costs, are in demand everywhere, and "how would you reduce this bill by 30%?" is a common interview question for platform and SRE roles. You've already met cost in passing (budgets in topic 6.1, Kubernetes requests in 9.3, log volume in 11.2); this topic makes it a practice.

## 1. FinOps in one page

The FinOps Foundation describes a loop with three phases:

| Phase | Questions | Tools |
| --- | --- | --- |
| **Inform** | What do we spend, on what, and who owns it? | Tags, cost allocation, dashboards, OpenCost |
| **Optimise** | Where is waste, and what's the cheapest way to deliver the same service? | Rightsizing, scheduling, spot, commitments, architecture changes |
| **Operate** | How do we keep it that way? | Budgets, anomaly alerts, policies, unit-cost targets, reviews |

The key idea: **engineers decide most of the bill** (instance sizes, replicas, log levels, architecture), so they need to see costs as quickly as they see errors.

## 2. Inform: make costs visible

**Tags and labels are the foundation.** Without them, a bill is a list of services, not of teams or products. Module 7's modules tag everything (`owner`, `project`, `environment`), Kyverno requires a team label on Deployments (topic 14.3), and Conftest checks Terraform for tags (topic 14.3).

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Cost explorer | Cost Explorer; Cost and Usage Report (CUR 2.0) into S3/Athena | Cost Management + Billing; exports to Storage | Cloud Billing reports; **billing export to BigQuery** |
| Allocation | Cost allocation tags (activate them!); cost categories | Tags (and tag inheritance); cost allocation rules | Labels; projects as the main unit |
| Budgets and alerts | AWS Budgets (with actions) | Budgets with action groups | Budgets with Pub/Sub notifications |
| Anomaly detection | Cost Anomaly Detection | Cost anomaly alerts | Cost anomaly detection |
| Recommendations | Compute Optimizer, Trusted Advisor | Azure Advisor | Recommender |

The **FOCUS** specification (FinOps Open Cost and Usage Specification) gives all three clouds' billing exports a common format, which makes multi-cloud cost reports far easier. AWS, Azure and Google Cloud all offer FOCUS exports.

## 3. Kubernetes costs: OpenCost

A cloud bill shows the nodes, not which team's pods used them. **OpenCost** (a CNCF project) splits node, storage and network costs across namespaces, workloads and labels, using Prometheus data and the cloud's prices.

```bash
cd labs/finops/opencost
helm upgrade --install prometheus prometheus-community/prometheus --version 29.38.0 -n prometheus-system --create-namespace -f prometheus-values.yaml
helm upgrade --install opencost opencost/opencost --version 2.5.33 -n opencost --create-namespace -f opencost-values.yaml
kubectl -n opencost port-forward svc/opencost 9003
curl 'localhost:9003/allocation/compute?window=1d&aggregate=namespace&accumulate=true'
curl 'localhost:9003/allocation/compute?window=7d&aggregate=label:platform_itlearning_tech_team'   # by the team label
```

The course's CI runs `kind-opencost-test.sh`: it installs both on kind with illustrative unit prices (kind has no cloud bill), waits for data, and reports each namespace's CPU, RAM and total cost and ITL Pay's **efficiency**: how much of what it requested it actually used.

**Efficiency is where Kubernetes waste hides.** You pay for requests (topic 9.3), not usage. A service requesting 1 CPU and using 0.1 is 90% waste, multiplied by every replica, in every environment.

## 4. Optimise, in this order

1. **Remove waste**: unattached disks, idle load balancers, old snapshots, forgotten test clusters, dev environments running at night, `DEBUG` logs in production (topic 11.2). The cheapest resource is the one you delete.
2. **Rightsize**: set requests from real usage (OpenCost efficiency, or the Vertical Pod Autoscaler in recommendation mode), choose smaller or newer instance types (ARM-based Graviton, Cobalt and Axion instances are usually cheaper for the same work).
3. **Schedule**: non-production environments only need to run in working hours. Weekdays from 08:00 to 20:00 is about a third of the month; scale node pools to zero and stop databases the rest of the time.
4. **Use spot capacity** for interruption-tolerant work: stateless replicas behind a Service, CI runners, batch jobs. Spot or preemptible VMs are much cheaper, but can be taken back at short notice: keep enough on-demand capacity for the SLO (topic 13.1), and spread across instance types and zones.
5. **Commit** to the steady base you're sure of: Savings Plans or Reserved Instances (AWS), reservations or savings plans (Azure), committed use discounts (Google Cloud). Commit after rightsizing, never before, and only for always-on capacity (a schedule and a commitment on the same capacity waste the commitment).
6. **Change the architecture** when the fixed costs dominate: one shared Gateway instead of a load balancer per service, private endpoints instead of NAT for cloud APIs, data kept in-region to avoid transfer charges, managed serverless for spiky workloads.

Topic 16.2 puts numbers on these levers for ITL Pay on all three clouds.

## 5. Operate: unit economics and guardrails

A total bill going up isn't bad if the business grew faster. Track **unit costs**:

- cost per 1,000 transfers;
- cost per active customer;
- cost per team or product, from tags and OpenCost.

Then keep them healthy:

- **Budgets with alerts** per account and team, at 50%, 80% and 100% (topic 6.1), and **anomaly alerts** routed like other alerts (topic 11.1);
- **Policies** that prevent expensive mistakes: no untagged resources, allowed instance families, maximum sizes in dev (topic 14.3);
- **A monthly cost review** next to the SLO review (topic 13.1): top changes, top waste, unit costs, actions with owners.

## Practice

1. Run `kind-opencost-test.sh`. Then double ITL Pay's CPU request and run it again: what changed in cost and efficiency?
2. Query OpenCost by the team label from topic 14.3 for a 1-hour window, and write a one-paragraph cost report for the payments team.
3. On one cloud, turn on billing export (CUR 2.0 to S3, an export to Storage, or BigQuery export), activate your cost allocation tags, and find your course spending by `project` tag.
4. Write a scale-to-zero schedule for your dev environment: a CronJob or pipeline that scales node pools to zero and stops the database at 20:00 and starts them at 08:00 on weekdays. Estimate the saving with `labs/finops/compare/compare_costs.py --hours 0.36`.
5. Pick your Capstone 2 environment's largest cost, and propose the change from section 4 that cuts it most, with the trade-off it brings.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [What is FinOps? The Operating Model & Cultural Practice to Maximize the Value of Technology](https://www.youtube.com/watch?v=Y-c_xw9bHFw) · FinOps Foundation · 2 min. The FinOps Foundation on what FinOps is.
- [See How OpenCost Tracks Your Kubernetes Costs and Cloud Billing](https://www.youtube.com/watch?v=lCP4Ci9Kcdg) · IBM Kubecost · 3 min. How OpenCost allocates Kubernetes costs to namespaces and workloads.
- [AWS Savings Plans Explained: Cost Optimization for EC2 and Compute Workloads](https://www.youtube.com/watch?v=9BZVvZcyc1k) · Harness · 4 min. How AWS Savings Plans work, and when to commit.
- [Analyse your Azure spending and Costs - Cost Management and Billing | Cost Savings](https://www.youtube.com/watch?v=jsATrgs0trk) · Cloud With Aarya · 9 min. Analysing Azure spending with Cost Management.
- [Understand your Google Cloud Costs: Billing, Cost Management and Budgets](https://www.youtube.com/watch?v=4R9XvHfxUKI) · mkdev · 6 min. Google Cloud billing reports, cost management and budgets.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Adopt FinOps on Azure](https://learn.microsoft.com/training/modules/adopt-finops-on-azure/)
- [Introduction to analyzing costs and creating budgets with Microsoft Cost Management](https://learn.microsoft.com/training/modules/analyze-costs-create-budgets-azure-cost-management/)
- [Save money with Azure Reserved Instances](https://learn.microsoft.com/training/modules/save-money-with-azure-reserved-instances/)

**AWS (AWS Skill Builder):**

- [Cloud Financial Management: FinOps fundamentals & strategies (Part 1)](https://skillbuilder.aws/learn/YZYAV9M2UB/cloud-financial-management-finops-fundamentals--strategies-part-1/JG1XFPZQG1)
- [Cloud Financial Management: FinOps Fundamentals & Strategies (Part 2)](https://skillbuilder.aws/learn/RE6C7ZPAHN/cloud-financial-management-finops-fundamentals--strategies-part-2/X59U3HSU75)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Optimizing Your Google Cloud Costs](https://www.skills.google/course_templates/56)

