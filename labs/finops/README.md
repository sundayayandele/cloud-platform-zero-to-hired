# FinOps lab (Module 16)

| Path | Topic | What it is |
| --- | --- | --- |
| `opencost/` | 16.1 | Prometheus and OpenCost on Kubernetes with illustrative prices, and `kind-opencost-test.sh`: what each namespace costs, and how efficiently ITL Pay uses what it requests |
| `compare/` | 16.2 | `compare_costs.py`: ITL Pay's monthly cost on AWS, Azure and Google Cloud before and after optimisation, its tests, and `prices.json` (illustrative: replace with your region's real prices) |

```bash
cd compare && python3 compare_costs.py --hours 0.36 && pytest -q
cd ../opencost && ../../kubernetes/kind-smoke-test.sh && ./kind-opencost-test.sh   # needs kind, kubectl and helm
```

The course's CI runs both on every push.
