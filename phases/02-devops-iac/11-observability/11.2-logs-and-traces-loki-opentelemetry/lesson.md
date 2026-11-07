## What you will be able to do

- Write **structured (JSON) logs** with consistent fields, and keep secrets and personal data out of them.
- Explain how logs are collected on Kubernetes, and query them with **Loki** (LogQL) and the clouds' log services.
- Explain **distributed tracing**: traces, spans, context propagation and sampling.
- Instrument an app with **OpenTelemetry** and send traces through an **OpenTelemetry Collector**.
- Go from an alert to the metric, the trace and the log line of one failing request, using the **trace ID**.
- Compare CloudWatch, Azure Monitor and Google Cloud Observability for logs and traces, including retention and cost.

## Why this matters at work

An alert tells you *that* transfers are failing; finding *why* means reading what happened in those requests. In a system with a gateway, an API, a database and two partner banks, a slow request could be stuck in any of them, and the logs of each live in a different place. Engineers who can jump from a graph to the exact trace and log line of one failed payment resolve incidents in minutes instead of hours. OpenTelemetry is now the industry standard for instrumentation, supported by every cloud and vendor, and appears in a growing share of SRE and platform job adverts. Log handling also has legal weight: Nigeria's NDPA, Kenya's and South Africa's data protection laws, and PCI DSS all limit what you may log and how long you keep it.

## 1. Structured logs

A text log line is easy for people and hard for machines:

```text
2026-11-07 12:24:33 INFO Transfer TRF-56A7F1410A: ACC-1001 -> ACC-2002, 100 kobo
```

ITL Pay Lite 1.1.0 writes one JSON object per line when `LOG_FORMAT=json` (the chart's default):

```json
{"time": "2026-11-07T12:24:33+0000", "level": "INFO", "logger": "itlpay",
 "message": "Transfer TRF-56A7F1410A: ACC-1001 -> ACC-2002, 100 kobo",
 "service": "itlpay-lite", "env": "dev",
 "trace_id": "28dcf37392c0b5d5ffd3d05bf8d31233", "span_id": "d69a6edc7e3df71f"}
```

Every log system can filter on `level`, `service` or `env` without fragile text matching, and the `trace_id` links the line to its trace (section 4).

What **not** to log:

| Never | Why |
| --- | --- |
| Passwords, tokens, API keys, full `DATABASE_URL`s | Anyone with log access gets them, and logs are copied everywhere |
| Card numbers (PAN), CVVs, PINs | PCI DSS forbids it outright |
| Full names with account balances, BVN/NIN numbers, phone numbers | Personal data under data protection law: log an ID, not the person |
| Request bodies by default | They contain all of the above |

Log **levels** have meaning: `ERROR` means someone may need to act, `WARNING` is unusual but handled (the app logs refused transfers at `WARNING`), `INFO` is normal business events, `DEBUG` is off in production. On Kubernetes, apps log to **standard output**, never to files: the platform collects stdout.

## 2. Collecting and querying logs

```text
pod stdout ─► the node's container log files ─► a collector on every node (a DaemonSet:
              Grafana Alloy, Fluent Bit, the OpenTelemetry Collector, or the cloud's agent)
            ─► a log store (Loki, CloudWatch Logs, Azure Monitor Logs, Cloud Logging) ─► queries, alerts, retention
```

**Loki** (Grafana's log store) indexes only **labels** (namespace, app, pod), not the text, which makes it much cheaper than full-text search engines, and its query language **LogQL** looks like PromQL:

```text
{namespace="itlpay", app="itlpay"} | json | level="WARNING"                     the refused transfers
{namespace="itlpay"} | json | trace_id="28dcf37392c0b5d5ffd3d05bf8d31233"        every line of one request
sum by (level) (count_over_time({namespace="itlpay"} | json [5m]))              log volume by level, as a metric
```

The same labels rule from topic 11.1 applies: labels are for low-cardinality things (namespace, app); IDs stay in the log text and are found with filters.

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Log store | CloudWatch Logs (log groups) | Azure Monitor Logs (Log Analytics workspaces) | Cloud Logging (log buckets) |
| From Kubernetes | Container Insights / the CloudWatch Observability add-on on EKS, or Fluent Bit | Container insights on AKS | Built into GKE: container stdout is collected by default |
| Query language | CloudWatch Logs Insights | KQL (Kusto) | Logging query language, or Log Analytics with SQL |
| Example: refused transfers | `fields @timestamp, message \| filter level = "WARNING"` | `ContainerLogV2 \| where LogMessage.level == "WARNING"` | `jsonPayload.level="WARNING"` |

**Cost and retention** decide most log designs. Clouds charge mainly per GB **ingested**, so a chatty `DEBUG` log in production can cost more than the servers. Set a retention period on every log group, workspace or bucket (for example 30 days hot, then archive to object storage if regulation requires years), and drop noisy lines (health checks) at the collector.

## 3. Distributed tracing

A **trace** is the story of one request; each step is a **span** with a start, a duration, attributes and a parent:

```text
trace 28dcf373...                                    0 ms                        42 ms
  POST /api/v1/transfers   (FastAPI server span)     |████████████████████████████|
    transfer.db            (span in the app's code)     |█████████████████████|
      (in a larger system: the fraud check, the partner bank's API, the message queue...)
```

- **Context propagation**: when one service calls another, it passes the trace ID in the `traceparent` HTTP header (the W3C Trace Context standard), so the next service's spans join the same trace.
- **Sampling**: storing every trace of a busy service is expensive. **Head sampling** keeps, say, 10% of traces decided at the start; **tail sampling** (in the Collector) decides after the trace ends, so it can keep every slow or failed trace and a few normal ones.

## 4. OpenTelemetry and the Collector

**OpenTelemetry (OTel)** is the open standard for producing metrics, logs and traces: APIs and SDKs for every major language, automatic instrumentation for common frameworks, and the **OTLP** protocol to send the data anywhere. Instrument once; choose or change the back end later.

ITL Pay Lite turns tracing on when `OTEL_EXPORTER_OTLP_ENDPOINT` is set (`app/observability.py`):

```python
provider = TracerProvider(resource=Resource.create({"service.name": "itlpay-lite", "deployment.environment.name": "dev"}))
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))   # reads the OTEL_EXPORTER_OTLP_* variables
trace.set_tracer_provider(provider)
FastAPIInstrumentor.instrument_app(app, excluded_urls="health,metrics") # a span for every request, automatically

# and one span by hand, around the database transaction; a refused transfer is a normal outcome, not an error,
# so it's recorded as an attribute and the span keeps an OK status:
with tracer.start_as_current_span("transfer.db", attributes={"itlpay.transfer.id": tid, "itlpay.amount_kobo": amount},
                                  record_exception=False, set_status_on_exception=False) as span:
    ...
    span.set_attribute("itlpay.result", "insufficient_funds")   # or "completed", "unknown_account"
```

The app sends to an **OpenTelemetry Collector**, not straight to a vendor:

```text
apps ─OTLP─► Collector: receivers (otlp) → processors (batch, memory_limiter, tail sampling, drop PII) → exporters
                                                                    ├─► Tempo or Jaeger
                                                                    ├─► AWS X-Ray, Azure Monitor, Cloud Trace
                                                                    └─► debug (the lab: prints spans to its log)
```

The Collector keeps credentials and vendor choices out of the apps, batches and retries, and can scrub data before it leaves the cluster.

```bash
cd labs/observability
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector --version 0.177.0 \
  -n monitoring -f otel-collector-values.yaml --wait
helm upgrade itlpay ../kubernetes/chart/itlpay -n itlpay -f ../kubernetes/values/kind.yaml \
  --set env.OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.monitoring:4318
# make a transfer, then:
kubectl -n monitoring logs deploy/otel-collector | grep -A3 "Name           : transfer.db"
```

The course's CI does exactly this on kind, then takes a `trace_id` from the app's JSON log line for a transfer and checks the Collector received that same trace: the link between logs and traces works end to end.

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Tracing service | AWS X-Ray (and CloudWatch Application Signals) | Application Insights (Azure Monitor) | Cloud Trace |
| OpenTelemetry distribution | AWS Distro for OpenTelemetry (ADOT) | Azure Monitor OpenTelemetry Distro | OpenTelemetry Collector with the Google Cloud exporter |
| Self-hosted, cloud-neutral | Grafana Tempo or Jaeger, queried from Grafana | | |

## 5. From alert to cause: one incident

1. **Alert** (topic 11.1): `ITLPayErrorBudgetBurn` pages: 9% of requests are failing.
2. **Metrics**: the dashboard shows the errors are all on `POST /api/v1/transfers`, starting at 14:02, right after a deploy.
3. **Traces**: filter traces for `service.name=itlpay-lite` with an error status since 14:02. The failing ones all spend 3 s in `transfer.db`, then fail.
4. **Logs**: search for one failing trace's `trace_id`: `ERROR ... connection pool exhausted`.
5. **Fix and follow-up**: roll back (topic 9.1), confirm the error ratio falls and the alert resolves, then write a blameless post-incident review with a timeline from these three sources, and an action (a connection-pool metric and alert).

Practise that path until it's routine: it's what an on-call shift is.

## Practice

1. Deploy ITL Pay with `LOG_FORMAT=json` and tracing on, and the Collector (section 4). Make a few transfers and one refused transfer; find a refused transfer's `trace_id` in the app logs and its spans in the Collector's log.
2. Install Loki and Grafana Alloy on kind (follow Grafana's Helm quick start in its monolithic mode), add Loki as a Grafana data source, and run the three LogQL queries in section 2.
3. Add a child span around the balance check inside `transfer.db`, with the number of rows locked as an attribute, and find it in the Collector's output nested under `transfer.db`.
4. On one cloud, send the app's logs to the cloud's log service (or deploy on the managed cluster from topic 9.5, where it's mostly automatic), run the query from the table in section 2, and **set a retention period**.
5. Write the post-incident review for the incident in section 5 as if it were real, using the course's runbook template from topic 4.3.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [12 Logging BEST Practices in 12 minutes](https://www.youtube.com/watch?v=I2mWnh66Bkg) · Better Stack · 12 min. Twelve logging practices, including structured logs.
- [Getting started with Grafana Loki  - under 4 minutes](https://www.youtube.com/watch?v=qE6hEHNH9dE) · Grafana · 4 min. Grafana Loki in under four minutes.
- [Distributed Tracing Explained: Understanding Microservice Observability](https://www.youtube.com/watch?v=fldLP22QUKg) · The Coding Gopher · 5 min. What distributed tracing is and why microservices need it.
- [What is OTel? | OTel for Beginners - The JavaScript Journey](https://www.youtube.com/watch?v=iEEIabOha8U) · OpenTelemetry · 9 min. OpenTelemetry for beginners, from the project itself.
- [OpenTelemetry Collector: EVERYTHING you need to know [to get started]](https://www.youtube.com/watch?v=_CJrFW_yjRo) · Adam Gardner · 10 min. The OpenTelemetry Collector: receivers, processors and exporters.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Instrument an app with OpenTelemetry](https://learn.microsoft.com/training/modules/instrument-app-opentelemetry/)
- [Write your first query with Kusto Query Language](https://learn.microsoft.com/training/modules/write-first-query-kusto-query-language/)
- [Create and configure a Log Analytics workspace](https://learn.microsoft.com/training/modules/create-configure-log-analytics-workspace/)

**AWS (AWS Skill Builder):**

- [Introduction to Amazon CloudWatch Logs](https://skillbuilder.aws/learn/H5K7BTCH6K/introduction-to-amazon-cloudwatch-logs/WMQKV8ZS4V)
- [AWS X-Ray Getting Started](https://skillbuilder.aws/learn/UD8KP8QN46/aws-xray-getting-started/2JNHS9K8EH)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Logging and Monitoring in Google Cloud](https://www.skills.google/course_templates/99)
- [Observability in Google Cloud](https://www.skills.google/course_templates/864)

