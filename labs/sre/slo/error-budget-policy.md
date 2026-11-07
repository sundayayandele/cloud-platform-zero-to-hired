# ITL Pay: error budget policy

Agreed by: the ITL Pay team, the platform team and the product owner · Reviewed: quarterly

The SLO says how reliable ITL Pay must be; this policy says what we do when it isn't. It's agreed in advance, so no one
has to argue about priorities during a bad month. `labs/sre/slo/error_budget.py` applies it to the current numbers.

| Budget left (30-day window) | Level | What happens |
| --- | --- | --- |
| More than 50% | Normal | Ship as usual. Spare budget can be spent on experiments and planned risky changes (a database upgrade, a chaos experiment). |
| 25–50% | Caution | Reliability work goes first in the next sprint's planning. Every change needs a tested rollback. |
| 0–25% | Freeze | Only fixes and security patches ship. The on-call lead approves every change. |
| Exhausted | Exhausted | Freeze everything except reliability fixes until the budget recovers. A post-mortem for the incidents that spent it. The SLO itself is reviewed. |

Exceptions: security patches always ship; a freeze can be lifted early by the head of engineering, in writing, with the reason.

If one incident spends more than 20% of the budget, it gets a post-mortem with at least one action, whatever the level.
