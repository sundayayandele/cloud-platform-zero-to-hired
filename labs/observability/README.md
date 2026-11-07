# Observability lab (Module 11)

ITL Pay Lite 1.1.0 exposes Prometheus metrics at `/metrics`, writes JSON logs (`LOG_FORMAT=json`) with trace IDs, and
sends OpenTelemetry traces when `OTEL_EXPORTER_OTLP_ENDPOINT` is set (`labs/itlpay-lite/app/observability.py`).

| Path | Topic | What it is |
| --- | --- | --- |
| `kube-prometheus-stack-values.yaml` | 11.1 | Prometheus, Alertmanager and Grafana for a learning cluster |
| `../kubernetes/chart/itlpay/rules/itlpay.rules.yml` | 11.1 | Recording rules, and alerts on pods down, error-budget burn and latency (in the chart, as a PrometheusRule) |
| `itlpay.rules.test.yml` | 11.1 | `promtool` unit tests for those alerts |
| `dashboards/itlpay-dashboard.yaml` | 11.1 | The ITL Pay Grafana dashboard, as a ConfigMap |
| `otel-collector-values.yaml` | 11.2 | An OpenTelemetry Collector that receives traces and prints them |
| `kind-observability-test.sh` | 11.1, 11.2 | Installs it all on kind and checks metrics, alerts, the dashboard and traces end to end |

```bash
cd labs/kubernetes && ./kind-smoke-test.sh
cd ../observability
promtool test rules itlpay.rules.test.yml     # SUCCESS
./kind-observability-test.sh                   # ends with OBSERVABILITY TEST OK
```

The course's CI runs both on every push. Delete the stack afterwards with `helm uninstall monitoring otel-collector -n monitoring`.
