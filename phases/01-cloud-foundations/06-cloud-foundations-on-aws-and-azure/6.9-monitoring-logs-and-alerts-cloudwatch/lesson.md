## What you will be able to do

- Explain metrics, logs and alerts, and the difference between monitoring the **platform** and monitoring the **service**.
- Find built-in metrics for VMs, load balancers and databases in **CloudWatch** and **Azure Monitor**.
- Send application and system logs from the VMs to **CloudWatch Logs** and a **Log Analytics workspace**, and search them with **Logs Insights** and **KQL**.
- Create alarms/alerts that notify you by email: 5xx errors, unhealthy targets, high CPU, low database storage, and the bill.
- Build a small dashboard for ITL Pay on each cloud.
- Write alert runbooks and avoid alert fatigue.

## Why this matters at work

You can't run what you can't see. Monitoring tells you something is wrong **before** customers call, and logs tell you **why**. Every on-call rota, every SRE interview and every incident review depends on them. In Phase 3 you'll go much further (Prometheus, Grafana, OpenTelemetry, reliability targets); this topic covers the built-in tools of both clouds, which every cloud job uses from day one.

## 1. Metrics, logs and alerts

- **Metrics** are numbers over time: CPU %, requests per minute, 5xx count, free storage. Cheap to store, good for graphs and alerts.
- **Logs** are records of events: "transfer TRF-123 from ACC-1001 failed: insufficient funds". Detailed, good for finding causes.
- **Alerts** watch metrics (or log queries) and notify someone when a condition holds for long enough.
- **Traces** follow one request across services (Phase 3).

Watch two levels:

| Level | Examples | Answers |
| --- | --- | --- |
| **Service (what users feel)** | Load balancer 5xx rate, latency, healthy targets, successful transfers | "Are customers affected?" |
| **Platform (causes)** | VM CPU and memory, disk space, database connections and storage, NAT gateway errors | "Why?" |

Alert mostly on the **service** level. A server at 90% CPU that serves users fine isn't an emergency; 5% of transfers failing is.

## 2. Where things are

| | AWS | Azure |
| --- | --- | --- |
| Metrics | **CloudWatch metrics** (namespaces such as `AWS/EC2`, `AWS/ApplicationELB`, `AWS/RDS`) | **Azure Monitor metrics** (per resource) |
| Logs store | **CloudWatch Logs** (log groups and streams) | **Log Analytics workspace** |
| Query language | **CloudWatch Logs Insights** | **KQL** (Kusto Query Language) |
| Agent on VMs | **CloudWatch agent** | **Azure Monitor Agent** with a **data collection rule (DCR)** |
| Alerts | **CloudWatch alarms** → **SNS** topic (email, SMS, chat) | **Alert rules** → **action group** (email, SMS, webhook) |
| Dashboards | CloudWatch dashboards | Azure dashboards, **Workbooks** |
| Audit of management actions | CloudTrail (topic 6.2) | Activity Log (topic 6.2) |
| Cost alerts | AWS Budgets (topic 6.1) | Cost Management budgets (topic 6.1) |

Some useful metrics are **not** collected by default: VM **memory** and **disk space** need the agent on both clouds.

## 3. Logs from the VMs

ITL Pay Lite writes its logs to standard output, so Docker and the journal hold them on the VM (topic 1.4). Ship them to the cloud so they survive the VM and can be searched across servers.

**AWS:** install the CloudWatch agent (cloud-init can do it), give the instance role the **`CloudWatchAgentServerPolicy`** managed policy, and configure which files to send. The simplest route for a container's logs is Docker's **`awslogs` log driver**, which sends a container's output straight to a log group:

```bash
docker run ... --log-driver awslogs --log-opt awslogs-region=af-south-1 \
  --log-opt awslogs-group=/itlpay/app --log-opt awslogs-create-group=true ...
```

(The instance role needs `logs:CreateLogStream` and `logs:PutLogEvents` on that log group, and `logs:CreateLogGroup` if it creates the group.)

**Azure:** create a **Log Analytics workspace**, then a **data collection rule** that collects syslog and the VM's performance counters, and associate it with the VMs; this installs the **Azure Monitor Agent**. The portal's **Monitor → Data collection rules → Create** does it in a few screens. Container output can be collected from syslog (`--log-driver syslog`) or the journal.

Search them:

```text
# CloudWatch Logs Insights, log group /itlpay/app
fields @timestamp, @message
| filter @message like /Transfer|ERROR|unreachable/
| sort @timestamp desc
| limit 50

# KQL, Log Analytics (syslog from the VMs)
Syslog
| where TimeGenerated > ago(1h)
| where SyslogMessage has_any ("Transfer", "ERROR", "unreachable")
| project TimeGenerated, Computer, SyslogMessage
| order by TimeGenerated desc
```

Set **log retention** (for example 30 days for app logs, longer for audit logs if policy requires): CloudWatch log groups keep logs forever by default, which slowly becomes a real cost.

## 4. Alerts that matter for ITL Pay

| Alert | AWS metric | Azure metric | Why |
| --- | --- | --- | --- |
| Users are getting errors | `HTTPCode_Target_5XX_Count` and `HTTPCode_ELB_5XX_Count` on the ALB | Application Gateway `Failed Requests` / response status `5xx` | Customers affected |
| No healthy servers, or only one left | `HealthyHostCount` < 2 on the target group | Application Gateway `Healthy Host Count` < 2 | About to be (or already) down |
| Database storage running out | RDS `FreeStorageSpace` < 2 GB | Flexible Server `storage_percent` > 85% | A full database stops writes |
| Database CPU saturated | RDS `CPUUtilization` > 85% for 15 min | `cpu_percent` > 85% for 15 min | Slow transfers |
| VM disk almost full | Agent metric `disk_used_percent` > 85% | VM insights `% Used Space` / `Logical Disk` counter | Logs fill disks (topic 1.4) |
| Spending | AWS Budgets | Cost Management budget | Topic 6.1 |

Create one on each cloud:

```bash
# AWS: email topic, then an alarm on healthy hosts
topic=$(aws sns create-topic --name itlpay-alerts --query TopicArn --output text)
aws sns subscribe --topic-arn "$topic" --protocol email --notification-endpoint you@example.com   # confirm the email
aws cloudwatch put-metric-alarm --alarm-name itlpay-healthy-hosts-low \
  --namespace AWS/ApplicationELB --metric-name HealthyHostCount --statistic Minimum \
  --dimensions Name=TargetGroup,Value="${tg##*:}" Name=LoadBalancer,Value="${alb#*loadbalancer/}" \
  --period 60 --evaluation-periods 3 --threshold 2 --comparison-operator LessThanThreshold \
  --treat-missing-data breaching --alarm-actions "$topic" --ok-actions "$topic" \
  --alarm-description "Fewer than 2 healthy ITL Pay targets. Runbook: docs/runbooks/api-503.md"

# Azure: action group, then a metric alert on the Application Gateway
az monitor action-group create -g rg-itlpay-net -n ag-itlpay --short-name itlpay \
  --action email ops you@example.com -o none
az monitor metrics alert create -g rg-itlpay-net -n itlpay-healthy-hosts-low \
  --scopes "$(az network application-gateway show -g rg-itlpay-net -n itlpay-agw --query id -o tsv)" \
  --condition "min HealthyHostCount < 2" --window-size 5m --evaluation-frequency 1m \
  --action ag-itlpay --severity 1 \
  --description "Fewer than 2 healthy ITL Pay backends. Runbook: docs/runbooks/api-503.md" -o none
```

(The `${tg##*:}` and `${alb#*loadbalancer/}` expansions trim the ARNs to the forms CloudWatch dimensions expect, `targetgroup/...` and `app/...`; check them with `echo` before using them.)

Notice the **description links to a runbook** (topic 4.3). Every alert that can wake someone must say what to do.

## 5. Good alerting habits

- **Alert on symptoms users feel**, with enough duration to ignore blips (3–5 minutes), and send cause-level metrics to dashboards instead.
- **Every alert must be actionable** and have a runbook. If nobody would do anything, it isn't an alert, it's a graph.
- **Severity**: page someone only for customer impact; send the rest to email or a channel for working hours.
- **Test alerts**: break something on purpose (section 6) and check the notification arrives, and that the "resolved" notification follows.
- **Review noisy alerts** weekly: fix the cause or the threshold. Alert fatigue makes people ignore the one that matters.

## 6. A dashboard and a test

Build a small dashboard on each cloud with: requests and 5xx count (load balancer), healthy hosts, response time, database CPU and free storage, VM CPU. Then run the failure test from topic 6.8 (stop one app server, then both) and watch the dashboard, the alerts and your email. Note how long each alert took to fire and to clear. This is a miniature "game day", which Phase 3 makes routine.

## Practice

1. Ship ITL Pay Lite's logs to CloudWatch Logs and to Log Analytics. Make five transfers (including one with insufficient funds) and find them with Logs Insights and KQL.
2. Create the healthy-hosts alert on both clouds with email notifications, and test it by stopping the app on both servers. Record the time to alert and to recovery.
3. Add one database alert on each cloud (free storage or CPU).
4. Build the dashboard in section 6 on both clouds and take a screenshot for your capstone repository.
5. Write the runbook `docs/runbooks/api-503.md` that your alerts link to, covering both clouds (start from the example in topic 4.3).

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [Basics of Amazon CloudWatch and CloudWatch Metrics | AWS Tutorials for Beginners](https://www.youtube.com/watch?v=Yxl7e88cTAQ) · Tiny Technical Tutorials · 11 min. Amazon CloudWatch and its metrics.
- [What is Azure Monitor?](https://www.youtube.com/watch?v=eSutaPE80PM) · Microsoft Azure · 5 min. What Azure Monitor is, from Microsoft.
- [How to get started with Azure Monitor Log Analytics](https://www.youtube.com/watch?v=-aMecR2Nrfc) · Microsoft Azure · 5 min. Getting started with Log Analytics, from Microsoft.

## Further learning (free)

Free, self-paced courses from the two clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn and a free AWS Builder ID for AWS Skill Builder to track your progress.

**Azure (Microsoft Learn):**

- [Monitor your Azure virtual machines with Azure Monitor](https://learn.microsoft.com/training/modules/monitor-azure-vm-using-diagnostic-data/)
- [Write your first query with Kusto Query Language](https://learn.microsoft.com/training/modules/write-first-query-kusto-query-language/)
- [Guided project: Monitor Azure with Service Health and Activity Log alerts](https://learn.microsoft.com/training/modules/guided-project-monitor-service-health-activity-alerts/)

**AWS (AWS Skill Builder):**

- [Amazon CloudWatch Getting Started](https://skillbuilder.aws/learn/HS1HSVQRHK/amazon-cloudwatch-getting-started/9Y34KP2H1T)
- [Introduction to Amazon CloudWatch Logs](https://skillbuilder.aws/learn/H5K7BTCH6K/introduction-to-amazon-cloudwatch-logs/WMQKV8ZS4V)
- [Amazon EC2 Observability, Monitoring, and Troubleshooting](https://skillbuilder.aws/learn/NVQMVRTS5H/amazon-ec2-observability-monitoring-and-troubleshooting/RC947H252R)

