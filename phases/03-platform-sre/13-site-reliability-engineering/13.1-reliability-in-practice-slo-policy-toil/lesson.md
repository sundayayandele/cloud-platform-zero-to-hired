## What you will be able to do

- Explain what site reliability engineering (SRE) is, and how it differs from traditional operations.
- Choose SLIs and SLOs for a service with its users and the business, and write them down.
- Turn an error budget into an agreed **error budget policy** that decides between features and reliability.
- Calculate budget used, burn rate and time to exhaustion, and run a monthly SLO review.
- Find and measure **toil**, and decide what to automate first.
- Plan capacity from load tests and growth, and know the limits each cloud imposes.

## Why this matters at work

"Is the system reliable enough?" is a question every engineering team argues about, usually with feelings: product wants features, operations wants stability. SRE, the approach Google published and most large tech companies and many banks now follow, turns it into numbers everyone agreed on beforehand: an SLO, an error budget, and a policy for what happens when the budget runs out. SRE job adverts ask for exactly this ("define and own SLOs", "reduce toil", "capacity planning"), and they're among the better-paid roles open to engineers working remotely for international companies.

## 1. What SRE is

SRE is "what happens when you ask a software engineer to design an operations function" (Google's SRE book). In practice:

- **Reliability is a feature with a target**, not "as high as possible". 100% is the wrong target: it's impossibly expensive, and users can't tell 99.99% from 100% through their own phone network.
- **Operations work is engineering work**: automate, measure, and fix causes instead of repeating fixes.
- **Shared ownership**: developers and SREs agree the targets and share the consequences.

You've built the tools already: SLO alerts (topic 11.1), runbooks (topic 4.3), safe releases (topic 12.2). This module adds the **practices** that make them work in a team.

## 2. Choosing SLIs and SLOs

Start from the user's journey, not from the dashboards you happen to have:

| User journey | SLI (good events / all events) | Measured where |
| --- | --- | --- |
| Make a transfer | Transfer requests that don't return 5xx | ITL Pay's metrics (the server's view) |
| Make a transfer quickly | Transfers answered within 500 ms | The latency histogram |
| See my balance | Account reads that succeed | Metrics, or a synthetic probe from outside (the user's view) |

The lab's SLO document (`labs/sre/slo/itlpay-slo.md`) sets ITL Pay at **99.5% availability, 99% of transfers within 500 ms, 99.9% correctness**, each over a rolling 30 days, and records **why** those numbers: one database primary can't honestly promise more, and every extra nine costs real money.

| SLO | Error budget in 30 days |
| --- | --- |
| 99% | 7.2 hours |
| 99.5% | 3.6 hours |
| 99.9% | 43 minutes |
| 99.99% | 4.3 minutes |

Tips that save arguments later:

- **Measure close to the user** where you can (at the load balancer, or with a synthetic probe from another cloud), because server metrics miss failures the server never saw.
- **Keep the list short**: two to four SLIs per service. If everything is an SLO, nothing is.
- **SLOs are not SLAs.** An SLA is a contract with penalties, and must be looser than the internal SLO so you're warned before you owe customers money.

## 3. The error budget policy

An error budget is only useful if everyone agreed in advance what happens when it's spent. The lab's policy (`labs/sre/slo/error-budget-policy.md`):

| Budget left | Level | What happens |
| --- | --- | --- |
| More than 50% | Normal | Ship as usual; spend spare budget on experiments and risky changes |
| 25–50% | Caution | Reliability work first in the next sprint; every change needs a tested rollback |
| 0–25% | Freeze | Only fixes and security patches |
| Exhausted | Exhausted | Freeze except reliability fixes; post-mortem; review the SLO itself |

It's signed by the product owner as well as engineering. That's the point: when the budget runs out, the decision to slow features down is already made.

The lab's `error_budget.py` applies it to real numbers:

```bash
cd labs/sre/slo
python3 error_budget.py --slo 99.5 --total 1200000 --bad 4100 --elapsed-days 12
# Burn rate 0.68x (1.0x spends exactly the budget by the end of the window)
# Budget used 27.3%, remaining 72.7%
# Runs out: not this window, at this rate
# Policy: NORMAL: Ship as usual. ...
python3 error_budget.py --slo 99.5 --prometheus http://localhost:9090 --elapsed-days 12    # from ITL Pay's own counters
```

- **Burn rate** is how fast you're spending: 1.0 spends exactly the budget by the end of the window; the 14.4 in the alert from topic 11.1 spends a month's budget in about two days.
- The tool's tests (`test_error_budget.py`, run by the course's CI) include the boundary case "exactly half left", which floating-point arithmetic gets wrong unless you're careful.

## 4. The monthly SLO review

Once a month, the team and the product owner look at:

1. Each SLO: met or not, budget used, burn over the month (a graph from the dashboard in topic 11.1).
2. The incidents that spent the budget, and whether their post-mortem actions are done (topic 13.2).
3. Whether the SLOs are still right: did users complain while the SLO was met (too loose, or the wrong SLI), or was the budget never touched while the team moved slowly (too tight)?
4. Toil (section 5) and capacity (section 6).

Thirty minutes, with a written record. It's the meeting that keeps SLOs from becoming wallpaper.

## 5. Toil

**Toil** is operational work that is manual, repetitive, automatable, reactive, without lasting value, and that grows with the service. Restarting the same pod every Monday is toil; writing the runbook that ends it isn't.

Google's guideline: SREs spend **at most 50%** of their time on toil; the rest goes to engineering that removes it. To get there:

1. **Measure it.** For two weeks, everyone logs interruptions and repetitive tasks with time spent (a shared sheet is enough).
2. **Rank by total time** (frequency × duration), and by risk (manual steps in production cause incidents).
3. **Remove the top items**: automate (a script, an operator, a pipeline step), make the system fix itself (probes, autoscaling, self-healing GitOps from topic 12.1), or stop doing it (does anyone read that report?).

Examples from this course: rotating secrets by hand (fixed by External Secrets, topic 10.2), checking for drift (the nightly job, topic 8.4), granting access tickets (self-service, Module 14).

## 6. Capacity planning

Reliability fails quietly when demand outgrows capacity. Plan from data:

1. **Load test** the service to find where it breaks: `k6` or `hey` against a staging environment, increasing load until latency or errors break the SLO. That point (requests per second per pod, connections per database) is your **capacity per unit**.
2. **Forecast demand**: current peak (for ITL Pay, the end-of-month salary day), plus growth, plus a safety margin.
3. **Provision with headroom**: enough that losing one zone (a third of a three-zone cluster) still serves peak load: the "N+1" rule.
4. **Know the limits that aren't yours**:

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Account limits that stop scaling | Service Quotas (vCPUs per instance family, load balancers, IPs) | Subscription quotas (vCPUs per region and VM family) | Project quotas (CPUs per region, IP addresses) |
| Where to see them | Service Quotas console, with CloudWatch alarms on usage | Usage + quotas in the portal | IAM & Admin → Quotas, with alerts |
| A common surprise | New accounts have low vCPU limits | Free and student subscriptions are capped | Africa regions may have tighter default quotas |

Ask for quota increases **before** the peak: they can take days.

## Practice

1. Write an SLO document for a service of your own (or Capstone 2's ITL Pay), with at least two SLIs measured close to the user, the reasons for the targets, and the alerts.
2. Run `error_budget.py` against your Prometheus from Module 11 after generating some errors (stop the database for a minute). At what level does the policy put you?
3. Change the policy so a single incident that spends more than 20% of the budget always needs a post-mortem, and add a test for your change.
4. Log your own toil for a week of the course (setting up clusters, fixing environments). Pick the top item and remove it with automation; record the time saved.
5. Load test ITL Pay on kind with `hey -z 60s -c 20` against `/health` and a transfer endpoint. Find the requests per second per pod before p95 latency passes 500 ms, and size a deployment for 10× that load with one zone lost.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [SLAs, SLOs, and SLIs EXPLAINED in 7 Minutes (2025)](https://www.youtube.com/watch?v=pouVbehfnqQ) · Better Stack · 7 min. SLAs, SLOs and SLIs, and how they differ.
- [Error Budgets Explained: Balancing Reliability and Feature Velocity](https://www.youtube.com/watch?v=LkuunG_GBfs) · Harness · 4 min. Error budgets: balancing reliability and new features.
- [DevOps Terms: What is Toil?](https://www.youtube.com/watch?v=v7XPp6pUsSw) · DevOps Journey · 4 min. What toil is, in four minutes.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Introduction to Site Reliability Engineering (SRE)](https://learn.microsoft.com/training/modules/intro-to-site-reliability-engineering/)
- [Azure Well-Architected Framework: Reliability](https://learn.microsoft.com/training/modules/azure-well-architected-reliability/)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Developing a Google SRE Culture](https://www.skills.google/course_templates/95)

