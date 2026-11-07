# Incident response for ITL Pay

## Severity

| Severity | Examples | Response |
| --- | --- | --- |
| **SEV1** | Transfers failing for many customers; data lost or wrong; a security breach | Page now, 24/7. Incident commander named within 5 minutes. Updates every 30 minutes. Post-mortem required |
| **SEV2** | One feature broken, or errors for some customers; the error budget burning fast | Page in working hours, otherwise next morning unless it grows. Updates every hour. Post-mortem required |
| **SEV3** | A degraded component with no customer effect yet (one zone down, a replica lagging) | A ticket, handled in working hours |

When unsure, choose the higher severity: it's easy to lower it later.

## Roles

| Role | Does | Doesn't |
| --- | --- | --- |
| **Incident commander (IC)** | Runs the response: sets priorities, assigns work, decides (roll back, fail over), declares it over | Fix things themselves |
| **Operations lead** | Investigates and changes the systems, through the pipeline where possible | Talk to customers |
| **Communications lead** | Status page, updates to support, management and, for a bank, the regulator if required | Speculate on causes |
| **Scribe** | Writes the timeline as it happens (time, what was seen, what was done, by whom) | |

In a small team one person may hold two roles, but never IC and operations lead together in a SEV1.

## The first 15 minutes

1. Acknowledge the page. Open an incident channel (`#inc-YYYYMMDD-short-name`) and an incident document from the post-mortem template.
2. Name the IC, and say so in the channel.
3. **Mitigate before you diagnose**: roll back the last change, fail over, scale out, or switch off a feature. Fixing the root cause can wait.
4. Set the severity and send the first update: what's affected, since when, what we're doing, when the next update is.
5. Keep the timeline as you go.

## Ending it

The IC declares the incident resolved when customers are no longer affected, then schedules the post-mortem meeting
within 5 working days. Actions from it get owners and dates.
