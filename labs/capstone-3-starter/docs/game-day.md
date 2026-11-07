# Game day: <name>

**Date:** · **Environment:** (dev on which cloud) · **People:** (who ran it, who watched, who was on call)

## Plan (write before you start)

| | |
| --- | --- |
| Hypothesis | "When <failure>, <service> keeps <SLI> within <target>, and <alert> fires within <time>." |
| Steady state | The SLIs and their values before the experiment (link the dashboard) |
| Failure injected | What, how (Chaos Mesh manifest, command), for how long |
| Blast radius | What could be affected; how you'll limit it |
| Abort condition | When you stop early, and how (the command that ends the experiment) |
| Rollback | How you get back to steady state if the system doesn't recover |

## What happened

| Time (UTC) | Event |
| --- | --- |
| | Experiment started |
| | First alert |
| | Diagnosed |
| | Recovered |

- Did the hypothesis hold? What did the SLIs do? (graphs)
- Did the right alert fire, at the right time, linking the right runbook?
- How long did detection and recovery take? For a restore: your measured RTO and RPO.

## What we'll change

| Action | Owner | Due | Done |
| --- | --- | --- | --- |
| | | | |
