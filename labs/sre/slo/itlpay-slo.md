# ITL Pay: service level objectives

Owner: the ITL Pay team · Reviewed: monthly, at the SLO review · Window: 30 days, rolling

| SLI (what we measure) | How (Prometheus, topic 11.1) | SLO (target) | Error budget |
| --- | --- | --- | --- |
| **Availability**: share of API requests that don't fail with 5xx | `http_requests_total{job="itlpay"}`, status `5..` vs all | 99.5% | 0.5% of requests (about 3.6 hours of total outage) |
| **Latency**: share of transfer requests answered within 500 ms | `http_request_duration_seconds_bucket{route="/api/v1/transfers",le="0.5"}` vs all | 99% | 1% of transfers slower than 500 ms |
| **Correctness**: share of transfers that complete or are refused for a business reason | `itlpay_transfers_total` by `result` | 99.9% | 0.1% |

## Why these numbers

- Customers notice failed and slow transfers, not CPU or pod restarts; every SLI is something a customer feels.
- 99.5%, not 99.99%: the API runs on one database primary (topic 13.4), and each extra 9 would cost a second region,
  a replica that can take over and an on-call rota we don't have yet. We'll raise it when the business needs it.
- `/health` and `/metrics` are excluded: they're for machines.

## Alerts (labs/kubernetes/chart/itlpay/rules/itlpay.rules.yml)

| Alert | Fires when | Who |
| --- | --- | --- |
| `ITLPayErrorBudgetBurn` | Burn rate above 14.4× over 1 hour and 5 minutes | Pages the on-call engineer |
| `ITLPaySlowRequests` | p95 latency above 500 ms for 10 minutes | Ticket for the team |
| `ITLPayDown` | No pod scraped for 2 minutes | Pages the on-call engineer |

When the budget runs low, the [error budget policy](error-budget-policy.md) decides what changes. Check the numbers with:

```bash
python3 labs/sre/slo/error_budget.py --slo 99.5 --prometheus http://localhost:9090 --elapsed-days 12
```
