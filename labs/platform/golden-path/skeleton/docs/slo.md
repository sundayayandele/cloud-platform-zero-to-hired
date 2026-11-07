# ${{ values.name }}: service level objectives

| SLI | SLO | Error budget (30 days) |
| --- | --- | --- |
| Requests that don't fail with 5xx | 99.5% | 0.5% |
| Requests answered within 500 ms | 99% | 1% |

Review these with your product owner before going to production (topic 13.1), and add the alert rules from the
platform's template (`ITLPayErrorBudgetBurn` in the ITL Pay chart is the model).
