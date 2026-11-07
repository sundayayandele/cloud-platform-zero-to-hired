# Post-mortem: <title>

Status: draft / reviewed · Severity: SEV1/2/3 · Date: YYYY-MM-DD · Authors: · IC:

**Blameless:** this document asks how the system and our processes allowed this to happen, not who made a mistake.
People acted reasonably with what they knew at the time.

## Summary

Two or three sentences: what happened, how long, who was affected.

## Impact

| | |
| --- | --- |
| Customers affected | e.g. about 1,200 transfers failed |
| Duration | detected → mitigated → resolved |
| Error budget spent | e.g. 34% of the 30-day budget (`labs/sre/slo/error_budget.py`) |
| Money or data | e.g. no money lost; 12 transfers retried |

## Timeline (UTC, from the incident channel and the scribe's notes)

| Time | Event |
| --- | --- |
| 14:02 | Deploy of version 1.4.0 to production completes |
| 14:05 | `ITLPayErrorBudgetBurn` pages the on-call engineer |
| ... | |

## Detection

How did we find out (alert, customer, chance)? How long did it take? Would we have found out without luck?

## Root causes and contributing factors

Ask "why?" until you reach things we can change: a missing test, a missing alert, a confusing runbook, a risky default.
Usually there are several.

## What went well · What went badly · Where we got lucky

## Actions

| Action | Type (prevent / detect / mitigate) | Owner | Due | Ticket |
| --- | --- | --- | --- | --- |
| | | | | |
