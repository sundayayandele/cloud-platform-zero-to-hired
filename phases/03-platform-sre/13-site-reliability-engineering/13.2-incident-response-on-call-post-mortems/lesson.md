## What you will be able to do

- Run an incident with clear roles: incident commander, operations, communications and scribe.
- Set severity, mitigate before you diagnose, and communicate on a fixed rhythm.
- Design a fair on-call rota, with escalation, handovers and limits that prevent burnout.
- Write a blameless post-mortem with a timeline, contributing factors and actions that get done.
- Use the clouds' incident and status tools, and know when a cloud provider's own outage is the cause.
- Run a tabletop exercise to practise all of this before a real incident.

## Why this matters at work

Every system fails eventually. What separates good teams is what happens next: a calm response with clear roles that restores service in minutes, or a crowd of people in a chat all trying fixes at once while customers wait. Banks and fintechs have regulators to inform and money at stake, so they run incidents formally. Being able to say "I've been incident commander" and show a good post-mortem is one of the strongest signals for SRE and platform roles, and the practices here are the same ones used at large international companies hiring remotely.

## 1. During an incident: roles

The lab's incident guide (`labs/sre/incident/incident-response.md`) defines four roles:

| Role | Does | Doesn't |
| --- | --- | --- |
| **Incident commander (IC)** | Runs the response: priorities, who does what, decisions (roll back, fail over), declares it over | Fix things themselves |
| **Operations lead** | Investigates and changes systems (through the pipeline where possible) | Talk to customers |
| **Communications lead** | Status page, support, management, the regulator where required | Speculate about causes |
| **Scribe** | Writes the timeline as it happens | |

The IC not touching the keyboard feels wrong at first, and is what makes the response work: someone must keep the whole picture, stop two people making conflicting changes, and notice when an hour has passed without progress. This comes from the Incident Command System used by fire services, adapted by Google, PagerDuty and others.

## 2. Severity and the first 15 minutes

| Severity | Examples | Response |
| --- | --- | --- |
| **SEV1** | Transfers failing for many customers; data lost; a breach | Page now, 24/7; IC within 5 minutes; updates every 30 minutes |
| **SEV2** | One feature broken; errors for some customers; the budget burning fast | Page in working hours; updates hourly |
| **SEV3** | Degraded with no customer effect yet | A ticket |

When unsure, choose the higher severity.

The first 15 minutes:

1. Acknowledge the page; open an incident channel and document.
2. Name the IC.
3. **Mitigate before you diagnose.** Roll back the last change (`git revert`, topic 12.1; or the rollout's abort, topic 12.2), fail over, scale out, or switch off the feature. The root cause can wait; customers can't.
4. Set the severity and send the first update: what's affected, since when, what we're doing, when the next update comes.
5. Keep the timeline.

Most incidents follow a change, so "what changed recently?" (deployments, config, infrastructure, the cloud provider) is the first question. GitOps and the pipeline's history from Modules 8 and 12 answer it in seconds.

## 3. Communication

- **A fixed rhythm**, even with nothing new: "Still investigating; next update at 15:30." Silence makes people interrupt the responders.
- **Facts, impact and next steps**, no guesses about causes.
- **Separate channels**: responders in the incident channel; stakeholders get the communications lead's updates.
- **A status page** for customers (Atlassian Statuspage, Better Stack, or a simple page you control, hosted somewhere other than the system that's down).
- **Regulated businesses**: banks and payment providers may have to notify their regulator within a fixed time for significant incidents (in Nigeria, the Central Bank's rules for payment service providers; in the EU, DORA). Know your rules before you need them; the communications lead owns this.

## 4. When the cloud is the cause

Sometimes it's not you. Check the providers' health dashboards for your regions, which show events affecting your own resources:

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Your account's events | AWS Health Dashboard (and Health events in EventBridge) | Azure Service Health (with alerts) | Personalized Service Health |
| Public status | health.aws.amazon.com | azure.status.microsoft | status.cloud.google.com |

Wire the account-level events into your alerting (EventBridge rules, Service Health alerts, Personalized Service Health notifications) so a regional problem reaches the on-call engineer as fast as your own alerts. Even when the provider is at fault, the incident is still yours: mitigate (fail over to another zone, region or cloud) and communicate.

## 5. On-call

| Practice | Why |
| --- | --- |
| A rota of at least 5–6 people, one week each | One week in six is sustainable; one in two burns people out |
| A primary and a secondary, and escalation to a lead | Pages that aren't acknowledged in 5–15 minutes go to the next person |
| A handover at each change: open incidents, risky changes, noisy alerts | Nothing falls between shifts |
| Pages only for things that need a human now | Every page should be actionable; others become tickets (topic 11.1's "page on symptoms") |
| Count pages per shift, and act when it's above about two a day | Alert fatigue makes people miss the real page |
| Pay or time off for on-call | It's work, and a fair rota keeps good people |

Tools: PagerDuty, Opsgenie (being folded into Atlassian's other products, so check its status before choosing it), Grafana OnCall and incident.io; Alertmanager routes to any of them (topic 11.1).

## 6. Blameless post-mortems

After every SEV1 and SEV2 (and any incident that spent more than 20% of the error budget, under the lab's policy), write a post-mortem with the lab's template (`labs/sre/incident/postmortem-template.md`): summary, impact, timeline, detection, contributing factors, what went well and badly, and **actions with owners and dates**.

**Blameless** means asking how the system allowed the failure, not who caused it. "The engineer ran the wrong command" leads nowhere; "the command had no confirmation, ran against production by default, and the runbook was out of date" leads to three fixes. People who fear blame hide information, and the next incident is worse.

Ask "why?" until you reach things you can change, and expect several contributing factors, not one root cause:

```text
Transfers failed for 40 minutes after release 1.4.0.
  Why? The new version's database query timed out under salary-day load.
  Why wasn't it caught? The canary analysis (topic 12.2) ran 30 seconds on quiet staging traffic.
  Why so short? The analysis template was copied from an example and never tuned.
  Why did detection take 9 minutes? The burn-rate alert's 1-hour window (topic 11.1) needed time to fill.
Actions: a load test in the pipeline; analysis on production canaries for 10 minutes; a faster 5-minute page for total failure.
```

Review post-mortems together, share them widely (other teams learn from them), and **track the actions**: an action list nobody finishes is how the same incident happens twice.

## 7. Practise: tabletop exercises

A **tabletop** is an incident on paper: the facilitator describes symptoms, the team responds out loud with roles and runbooks, and the facilitator reveals what happens next. One hour, no systems at risk, and it finds missing runbooks, unclear roles and broken contact lists before a real incident does. Topic 13.3 goes further and breaks real systems on purpose.

## Practice

1. Run a 45-minute tabletop with two or three classmates in the forum: "Transfers fail for 20% of customers after a release on GKE." Rotate the IC role. Use the lab's incident guide.
2. Write the post-mortem for your tabletop with the template, including a timeline and at least three actions of different types (prevent, detect, mitigate).
3. Set up an AWS Health, Azure Service Health or Personalized Service Health notification for your account's regions, and route it to the same place as your alerts.
4. Design an on-call rota for a team of five covering ITL Pay 24/7: shifts, escalation times, handover, and how pages are counted and reviewed.
5. Read two public post-mortems from large cloud providers (search their status history for a regional outage). List what they did well and one thing you'd ask them.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Introduction to the Incident Command System (ICS)](https://www.youtube.com/watch?v=P-dPBso2xPM) · Justice Institute of British Columbia (JIBC) · 9 min. The Incident Command System that SRE incident roles come from.
- [How to run a Post-Mortem meeting, step-by-step](https://www.youtube.com/watch?v=9JYVOUKNQ3A) · Bran van der Meer · 8 min. How to run a post-mortem meeting, step by step.
- [Blameless Postmortem Culture In Software Engineering](https://www.youtube.com/watch?v=Fv0nwb1Qn6A) · Clément Mihailescu · 9 min. Why post-mortems should be blameless.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Improve your reliability with modern operations practices: incident response](https://learn.microsoft.com/training/modules/improve-reliability-incidents/)
- [Improve your reliability with modern operations practices: monitoring](https://learn.microsoft.com/training/modules/improve-reliability-monitoring/)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Developing a Google SRE Culture](https://www.skills.google/course_templates/95)
- [Observability in Google Cloud](https://www.skills.google/course_templates/864)

