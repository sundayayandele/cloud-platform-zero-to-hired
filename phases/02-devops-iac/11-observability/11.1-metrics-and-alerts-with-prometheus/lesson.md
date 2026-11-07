## What you will be able to do

- Explain the three signals of observability (metrics, logs, traces) and what each one is for.
- Instrument an application with Prometheus metrics, and choose labels that don't explode the number of time series.
- Run **kube-prometheus-stack** (Prometheus, Alertmanager, Grafana) on Kubernetes, and scrape an app with a **ServiceMonitor**.
- Write PromQL: rates, ratios and percentiles from histograms.
- Define an **SLO** and alert on **error-budget burn rate**, not on every blip, and unit-test alert rules with `promtool`.
- Build a Grafana dashboard as code, and compare the clouds' managed Prometheus and Grafana services.

## Why this matters at work

When a payment fails at 2 a.m., the first questions are "how many?", "since when?" and "is it getting worse?". Metrics answer them in seconds. Good alerting is the difference between an on-call engineer who sleeps and fixes real problems, and one who is woken ten times a night by noise and starts ignoring pages. SRE and platform job adverts almost always name Prometheus and Grafana (or Datadog, which works on the same ideas), and interviews ask about SLOs, golden signals and "how would you know this service is unhealthy?". Banks and fintechs in particular are measured by regulators and customers on availability.

## 1. Metrics, logs and traces

| Signal | What it is | Answers | Lab |
| --- | --- | --- | --- |
| **Metrics** | Numbers over time: request rate, error count, latency, CPU | Is something wrong, how much, since when? Cheap to keep for months | This topic |
| **Logs** | Timestamped events with detail | What exactly happened in this request? | Topic 11.2 |
| **Traces** | The path of one request through every service and database call, with timings | Where did the time go, and which hop failed? | Topic 11.2 |

You alert on **metrics**, then use **traces** and **logs** to find the cause. **Monitoring** is watching for problems you predicted; **observability** is being able to ask new questions about problems you didn't.

What to measure first, for any service, are the four **golden signals**: **latency**, **traffic**, **errors** and **saturation** (how full the service is: CPU, memory, connections, queue depth). The RED method (Rate, Errors, Duration) is the same idea for request-driven services.

## 2. Instrumenting ITL Pay Lite

ITL Pay Lite (version 1.1.0, `labs/itlpay-lite/app/observability.py`) now serves Prometheus metrics at `GET /metrics`:

```text
# HELP http_requests_total HTTP requests handled
# TYPE http_requests_total counter
http_requests_total{method="POST",route="/api/v1/transfers",status="201"} 5.0
http_requests_total{method="POST",route="/api/v1/transfers",status="409"} 1.0
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{le="0.05",method="POST",route="/api/v1/transfers"} 4.0
...
itlpay_transfers_total{result="completed"} 5.0
itlpay_transfers_total{result="insufficient_funds"} 1.0
itlpay_transferred_kobo_total 500.0
```

| Type | Use it for | Example |
| --- | --- | --- |
| **Counter** | Things that only go up; you always look at its **rate** | Requests, errors, transfers |
| **Gauge** | A value that goes up and down | Connections in use, queue length |
| **Histogram** | Distributions, so you can calculate percentiles | Request duration in buckets |

The most important rule is about **labels**. Every combination of label values is a separate time series that Prometheus stores. `route="/api/v1/transfers/{tid}"` (the **template**) gives one series; `path="/api/v1/transfers/TRF-56A7F1410A"` would give one per transfer, millions of series, and a Prometheus that runs out of memory. Never put IDs, emails, amounts or full URLs in labels; that's what logs and traces are for. The app's tests check this (`test_metrics_count_transfers_by_result_and_use_route_templates`).

The business counters (`itlpay_transfers_total` by `result`) matter as much as the technical ones: "transfers completed per minute dropped to zero" is often the first sign of an outage that every health check misses.

## 3. Prometheus on Kubernetes: kube-prometheus-stack

**Prometheus** *pulls* (scrapes) `/metrics` from every target every 15–60 seconds and stores the samples. On Kubernetes, the **Prometheus Operator** lets you describe what to scrape with Kubernetes objects:

```text
kube-prometheus-stack (one Helm chart)
  Prometheus Operator ── watches ServiceMonitor, PodMonitor and PrometheusRule objects
  Prometheus           ── scrapes the targets, evaluates the rules
  Alertmanager         ── groups, silences and routes alerts to people
  Grafana              ── dashboards
  node-exporter, kube-state-metrics ── node and Kubernetes object metrics
```

```bash
cd labs/observability
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 92.11.0 \
  -n monitoring --create-namespace -f kube-prometheus-stack-values.yaml --wait
kubectl apply -f dashboards/itlpay-dashboard.yaml

helm upgrade itlpay ../kubernetes/chart/itlpay -n itlpay -f ../kubernetes/values/kind.yaml \
  --set metrics.serviceMonitor.enabled=true --set metrics.prometheusRule.enabled=true
kubectl -n monitoring port-forward svc/prometheus-operated 9090      # http://localhost:9090 → Status → Targets
```

The chart's **ServiceMonitor** says "scrape port `http`, path `/metrics`, on the pods behind the itlpay Service", and sets the `job` label to `itlpay`. Its **PrometheusRule** carries the alert rules, so the alerts are versioned and deployed with the application. `kind-observability-test.sh` runs all of this on kind in the course's CI and checks Prometheus sees both pods and counts the transfers.

## 4. PromQL in five patterns

| Question | PromQL |
| --- | --- |
| Requests per second, by route | `sum by (route) (rate(http_requests_total{job="itlpay"}[5m]))` |
| Share of requests failing (5xx) | `sum(rate(http_requests_total{job="itlpay",status=~"5.."}[5m])) / sum(rate(http_requests_total{job="itlpay"}[5m]))` |
| 95th percentile latency | `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job="itlpay"}[5m])))` |
| Are all pods being scraped? | `up{job="itlpay"}` (1 = scraped, 0 = failed) |
| Pods near their memory limit | `container_memory_working_set_bytes{namespace="itlpay"} / on (pod, container) kube_pod_container_resource_limits{resource="memory"}` |

- `rate(counter[5m])` turns an ever-growing counter into "per second, averaged over 5 minutes", and copes with restarts that reset the counter.
- **Average latency hides pain.** If 95 requests take 50 ms and 5 take 5 s, the average looks fine while one customer in twenty waits five seconds. Use percentiles (p95, p99) from histograms.
- **Recording rules** precompute expensive queries under a name (`itlpay:http_errors:ratio_rate5m`), so dashboards and alerts are fast and consistent. The convention is `level:metric:operations`.

## 5. SLOs, error budgets and alerts that matter

An **SLI** (indicator) is a measurement: "share of requests that don't return 5xx". An **SLO** (objective) is the target: "99.5% over 30 days". The **error budget** is what's left: 0.5% of requests, about 3.6 hours of total outage a month. It turns arguments into a rule: while budget remains, ship features; when it's spent, fix reliability first.

Alerting on "error rate above 1% for 1 minute" pages people for blips. Alerting on **burn rate** pages them only when the budget is really at risk:

```yaml
# labs/kubernetes/chart/itlpay/rules/itlpay.rules.yml
- alert: ITLPayErrorBudgetBurn
  expr: itlpay:http_errors:ratio_rate1h > (14.4 * 0.005) and itlpay:http_errors:ratio_rate5m > (14.4 * 0.005)
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "ITL Pay is failing {{ $value | humanizePercentage }} of requests"
    runbook_url: "https://github.com/OWNER/itlpay/blob/main/docs/runbooks/itlpay-errors.md"
```

A burn rate of 14.4 spends a 30-day budget in about two days. Checking both the last **hour** (it's real, not a blip) and the last **5 minutes** (it's still happening, so the alert clears soon after a fix) is the multi-window pattern from Google's SRE workbook. Teams add a slower pair (for example 6× over 6 hours) as a ticket rather than a page.

Rules for good alerts:

- **Page on symptoms users feel** (errors, latency, nothing working), not on causes (CPU at 80%): the cause may not hurt anyone.
- **Every page has a runbook** (`runbook_url`) saying what to check first (topic 4.3).
- **Severity decides the route**: `critical` pages a person (PagerDuty, Opsgenie, a phone call); `warning` goes to a chat channel. That's Alertmanager's job, with grouping (one page for a hundred failing pods) and silences during maintenance.
- **Test alerts like code.** `labs/observability/itlpay.rules.test.yml` feeds made-up series to `promtool` and asserts which alerts fire: 10% errors must page, 1% must not, and a pod down for 1 minute is still only pending. The course's CI runs it on every push.

```bash
promtool check rules ../kubernetes/chart/itlpay/rules/itlpay.rules.yml
promtool test rules itlpay.rules.test.yml        # SUCCESS
```

## 6. Grafana dashboards as code

The lab's dashboard (`dashboards/itlpay-dashboard.yaml`) is a ConfigMap with the dashboard JSON; Grafana's sidecar loads every ConfigMap labelled `grafana_dashboard: "1"`. It shows the RED signals and the business counter: requests by route, error ratio against the budget, p95 latency, and transfers by result.

```bash
kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80     # http://localhost:3000, user admin
```

Edit dashboards in the UI to explore, then export the JSON back to Git: a dashboard that exists only in one Grafana is lost when that Grafana is.

## 7. The clouds' managed options

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Managed Prometheus (PromQL, no servers to run) | Amazon Managed Service for Prometheus | Azure Monitor managed service for Prometheus | Google Cloud Managed Service for Prometheus (on by default in new GKE clusters) |
| Managed Grafana | Amazon Managed Grafana | Azure Managed Grafana | (Cloud Monitoring dashboards; or Grafana with the Cloud Monitoring data source) |
| The cloud's own metrics and alerts | CloudWatch metrics and alarms (topic 6.9) | Azure Monitor metrics and alerts | Cloud Monitoring and alerting policies |

The instrumentation, the PromQL and the alert rules you wrote here work on all three managed Prometheus services, which is one reason Prometheus became the standard: you can move between clouds and tools without rewriting your metrics.

## Practice

1. Install the stack and ITL Pay's ServiceMonitor on kind (section 3). In the Prometheus UI, find the `itlpay` targets, then run each query in section 4 after making a few transfers.
2. Open the Grafana dashboard and explain each panel in your own words in your learning log.
3. Make the error alert fire for real: stop the database (`kubectl -n itlpay scale statefulset/postgres --replicas=0`), drive traffic at `/health` and the API for 10 minutes, and watch the alert go from inactive to pending to firing in Prometheus (Alerts tab) and arrive in Alertmanager. Start the database again and watch it resolve.
4. Add a `promtool` test for `ITLPaySlowRequests` that must **not** fire when only `/health` is slow. Run it.
5. Add a gauge to the app, `itlpay_db_pool_in_use`, or a counter of database errors, and a panel for it. Then explain whether it should page anyone, and why.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [How Prometheus Monitoring works | Prometheus Architecture explained](https://www.youtube.com/watch?v=h4Sl21AKiDg) · TechWorld with Nana · 22 min. How Prometheus works: scraping, storage, targets and alerts.
- [Understanding Prometheus Metric Types | Meaning and Usage (Gauge, Counter, Summary, Histogram)](https://www.youtube.com/watch?v=fhx0ehppMGM) · Prometheus Monitoring with Julius | PromLabs · 11 min. Counters, gauges and histograms, and when to use each.
- [Understanding Counter Rates and Increases in PromQL | Reset Handling, Extrapolation, Edge Cases](https://www.youtube.com/watch?v=7uy_yovtyqw) · Prometheus Monitoring with Julius | PromLabs · 11 min. rate() and increase() on counters, and counter resets.
- [Introduction to Service monitors for beginners | Kubernetes monitoring](https://www.youtube.com/watch?v=_NtRkBipepg) · That DevOps Guy · 20 min. ServiceMonitors with the Prometheus Operator.
- [Creating Grafana Dashboards for Prometheus | Grafana Setup & Simple Dashboard (Chart, Gauge, Table)](https://www.youtube.com/watch?v=EGgtJUjky8w) · Prometheus Monitoring with Julius | PromLabs · 14 min. Building Grafana dashboards on Prometheus data.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Guided project: deploy and configure Azure Monitor](https://learn.microsoft.com/training/modules/guided-project-deploy-configure-azure-monitor/)
- [Monitor and troubleshoot applications on Azure Kubernetes Service](https://learn.microsoft.com/training/modules/monitor-apps-azure-kubernetes-service/)

**AWS (AWS Skill Builder):**

- [Amazon CloudWatch Getting Started](https://skillbuilder.aws/learn/HS1HSVQRHK/amazon-cloudwatch-getting-started/9Y34KP2H1T)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Monitor Environments with Google Cloud Managed Service for Prometheus](https://www.skills.google/course_templates/761)
- [Monitoring in Google Cloud](https://www.skills.google/course_templates/747)
- [Developing a Google SRE Culture (SLOs and error budgets)](https://www.skills.google/course_templates/95)

