# Values per environment

One file per GitHub environment, named after it: `dev-aws.yaml`, `dev-azure.yaml`, `dev-gcp.yaml`, `prod-<cloud>.yaml`.
Start from `labs/kubernetes/values/eks.yaml`, `aks.yaml` and `gke.yaml` (topic 9.5) and add, per environment: the
HTTPRoute host name, `env.APP_ENV`, `env.OTEL_EXPORTER_OTLP_ENDPOINT`, `metrics.serviceMonitor.enabled: true`,
`metrics.prometheusRule.enabled: true`, and, for production, more replicas and a stricter PodDisruptionBudget.

The image is **not** set here: the pipeline passes the digest it built and verified. Secrets are never here: the
Secret `itlpay-db` comes from External Secrets (topic 10.2).

Copy the chart into `deploy/chart/itlpay/` (from `labs/kubernetes/chart/itlpay/`).
