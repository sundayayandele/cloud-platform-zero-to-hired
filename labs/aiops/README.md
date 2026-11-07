# AI for operations lab (Module 17)

| Path | Topic | What it is |
| --- | --- | --- |
| `triage/` | 17.1 | `triage.py`: an incident-triage assistant using the Claude API, with redaction, a read-only kubectl allowlist, human approval for every change, an audit log and a turn limit; `test_triage.py` tests all of it offline with a fake model |
| `serving/` | 17.2 | `vllm.yaml`: an open model served with vLLM on a GPU node pool; `policy/gpu.rego`: rules for GPU workloads, with tests |

```bash
cd triage && pip install -r requirements.txt pytest && pytest -q        # offline, no API key needed
export ANTHROPIC_API_KEY=...                                            # your own key, for a real run against kind
python3 triage.py --alert "ITLPayHighErrorRate: 5xx ratio 4% for 10m in namespace itlpay"

cd ../serving && conftest verify -p policy && conftest test -p policy vllm.yaml
```

The course's CI runs the triage tests, the policy tests and kubeconform on every push. Serving the model needs a
GPU node pool, which costs money by the hour: create it, test, and delete it the same day (topic 17.2).
