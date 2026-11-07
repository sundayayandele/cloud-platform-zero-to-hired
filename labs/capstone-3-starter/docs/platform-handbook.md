# Platform handbook

For a team putting a service on the platform. Keep each section short, with commands that work.

## 1. What the platform gives you
Environments, clouds, what's managed for you (deployments, TLS, metrics, logs, traces, backups), and what you own.

## 2. Create a service
The golden path: how to run the template, what it creates (repository, pipeline, chart, Argo CD application,
dashboard, alerts), and how long it takes.

## 3. Get infrastructure
How to claim a database (or bucket, or queue): the claim file, where to commit it, how long it takes, where the
connection details appear.

## 4. Ship a change
From commit to production: tests, the image, the pull request that promotes to production, the canary and what aborts it.

## 5. See how you're doing
Your dashboards, SLOs and error budget, alerts and who gets paged, logs and traces, and your team's costs in OpenCost.

## 6. What the guardrails refuse, and why
Each policy (no `:latest`, limits, team labels, signed images, allowed regions...), the message you'll see, and how to fix it.
How to ask for an exception.

## 7. When things go wrong
How to raise an incident, the severity levels, the runbooks, and the postmortem process.

## 8. Getting help
Where to ask, office hours, and how to suggest a change to the platform (a pull request to the platform repository).
