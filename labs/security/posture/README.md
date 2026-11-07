# Security posture (topic 15.1)

## Scan your own configuration (run by the course's CI)

```bash
trivy config --severity HIGH,CRITICAL --exit-code 1 labs/kubernetes/manifests
trivy config --severity HIGH,CRITICAL --exit-code 1 labs/kubernetes/chart/itlpay
trivy config --severity HIGH,CRITICAL --exit-code 1 labs/gitops/kustomize/base
```

Trivy is pinned to 0.76.1, an immutable GitHub release, and CI checks the download against the release's checksums
before running it: Trivy's own release channels were compromised in March 2026 (topic 8.2).

## Turn on each cloud's posture service (one account, subscription or project)

| Cloud | Turn it on | What you get |
| --- | --- | --- |
| AWS | `aws securityhub enable-security-hub --enable-default-standards --region af-south-1` and `aws guardduty create-detector --enable --region af-south-1` | Security Hub CSPM: findings against AWS Foundational Security Best Practices and CIS; GuardDuty: threat detection from CloudTrail, VPC flow logs and DNS |
| Azure | `az security pricing create --name CloudPosture --tier Standard` (or the free Foundational CSPM, on by default) | Microsoft Defender for Cloud: secure score, recommendations, the Microsoft cloud security benchmark; Defender plans add threat protection per resource type |
| Google Cloud | In the console: Security → Security Command Center → Activate (Standard tier at project level) | Security Command Center: misconfigurations (Security Health Analytics), vulnerabilities and threats in one list |

Check prices first: the basic tiers are free or cheap, the threat-protection plans are charged per resource.
