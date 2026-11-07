## What you will be able to do

- Define RPO and RTO with the business, and choose a disaster recovery strategy that meets them at a sensible cost.
- Back up managed databases on the three clouds with point-in-time recovery, and copy backups out of the account.
- Back up Kubernetes namespaces and their volumes with Velero, and restore them.
- Protect backups from ransomware with immutable storage in a separate account or cloud.
- Prove recovery with regular, timed restore tests, and write a disaster recovery runbook.
- Recover across regions and across clouds, and know what makes data the hard part.

## Why this matters at work

Backups that have never been restored fail at the worst moment, and every team learns this once. Ransomware now targets backups first; regulators (central banks, the EU's DORA, PCI DSS) ask for tested recovery plans with numbers; and customers ask "how long would you be down if a region failed?". Disaster recovery (DR) is where cloud, Kubernetes and SRE skills meet, and being able to say "I restore our production database every month and it takes 14 minutes" is exactly what hiring managers want to hear.

## 1. RPO, RTO and strategy

- **RPO (recovery point objective):** how much data you can lose, measured in time. RPO 5 minutes means at most the last 5 minutes of transfers.
- **RTO (recovery time objective):** how long you can be down while recovering.

Both come from the business ("what does an hour of no transfers cost?"), not from engineering. Then choose a strategy:

| Strategy | How | RPO | RTO | Cost |
| --- | --- | --- | --- | --- |
| **Backup and restore** | Backups copied to another region or cloud; rebuild from them | Hours (or minutes with PITR) | Hours | Lowest |
| **Pilot light** | Data replicated continuously; the rest of the stack defined in code, created on demand | Minutes | Tens of minutes | Low |
| **Warm standby** | A smaller copy of everything running, scaled up in a disaster | Seconds to minutes | Minutes | Medium |
| **Active-active** | Full capacity in two places, serving traffic | Near zero | Near zero | Highest, and hardest for data |

For ITL Pay with a 99.5% SLO, a **pilot light in a second region** (a database replica, the platform in Git from Modules 7 and 12) is proportionate. Active-active across clouds for a payments database is a major project; don't promise it lightly.

## 2. Managed databases first

On the clouds, ITL Pay's database is managed (topic 6.7), and its backups come with it:

| | AWS RDS for PostgreSQL | Azure Database for PostgreSQL | Google Cloud SQL |
| --- | --- | --- | --- |
| Automatic backups and PITR | Up to 35 days; restore to any second | Up to 35 days | Up to 35 days of logs (configurable) |
| Copy to another region | Cross-region automated backups; cross-region read replicas | Geo-redundant backup storage; read replicas in another region | Cross-region read replicas; backups in a chosen location |
| Copy out of the account | AWS Backup with cross-account copy | Azure Backup vaults (immutable, soft delete) | Backup vaults (Backup and DR service) |
| Logical export | `pg_dump` to S3 | `pg_dump` to Blob Storage | `gcloud sql export` to Cloud Storage |

**Across clouds:** no provider replicates its managed database to another cloud. For a cross-cloud copy, run a scheduled `pg_dump` (or logical replication) into the other cloud's object storage. That gives an RPO of your schedule (hourly, say), which is often enough for "the whole provider is gone".

## 3. Kubernetes: Velero

Your clusters can be rebuilt from Git (Module 12), but some things live only in the cluster: volumes of stateful workloads, and resources created at run time. **Velero** backs up Kubernetes objects and volumes to object storage, and restores them, into the same or another cluster:

```text
Backup "itlpay-…"   → the namespace's objects (Deployments, Services, Secrets, PVCs...) as JSON in the bucket
                    → each volume's files (file system backup with Kopia), or a disk snapshot (CSI) on the clouds
Restore             → recreates the objects, then the volume data before the pod starts
```

The lab (`labs/sre/dr/`) runs Velero 1.18 on kind with an S3-compatible store (SeaweedFS), and the course's CI runs `kind-dr-test.sh` on every push: make a transfer, back up the `itlpay` namespace, **delete the namespace and its database volume**, restore, and fetch the transfer again. The latest run: 135 items backed up, the database volume copied, and ITL Pay back **in 29 seconds** with the transfer intact.

```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: itlpay-1762531200
  namespace: velero
spec:
  includedNamespaces: [itlpay]
  defaultVolumesToFsBackup: true   # copy volume files (kind has no disk snapshots)
  ttl: 72h0m0s
```

Schedules make it routine: `kind: Schedule` with a cron expression and the same spec.

On the clouds, use each provider's Velero plugin (`velero-plugin-for-aws`, `-for-microsoft-azure`, `-for-gcp`) with a bucket in that cloud, the cluster's workload identity (topic 9.5) instead of keys, and **CSI snapshots** of disks (EBS, Azure Disk, Persistent Disk) with Velero's data mover to copy them into the bucket.

## 4. Three things the lab's test taught us

The DR test failed twice before it passed; both failures are common in real teams.

1. **"Completed" didn't mean the data was there.** The first run's backup completed and the restore completed, but the transfer was missing: the database came back empty. kind's storage provisioner creates **hostPath** volumes by default, and Velero's file system backup **skips hostPath volumes**. Velero reported success; the data simply wasn't in it. Fixes: kind now creates `local` volumes (a StorageClass annotation in `kind-smoke-test.sh`), and the test checks the volume type before backing up and that a volume backup **for the database volume** completed. Always verify the *contents* of a backup, not its status.
2. **Restores must follow your security rules.** Velero adds a "restore-wait" helper container to restored pods. The `itlpay` namespace enforces the restricted Pod Security level (topic 9.1), so the helper needs a compliant security context, set in the `fs-restore-action-config` ConfigMap (`restore-helper-config.yaml`); otherwise the restored database pod is refused.
3. **Consistency matters.** Copying a running database's files can catch them mid-write. A **pre-backup hook** (`pre.hook.backup.velero.io/command` on the pod) runs `CHECKPOINT` in PostgreSQL first, so the files are consistent. For a busy production database, prefer the database's own backups (section 2) and use Velero for everything around it.

## 5. Protecting backups from attackers

Ransomware crews look for backups first, and delete or encrypt them with the same stolen credentials. Defences:

| Defence | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Immutable storage (can't be deleted until a date) | S3 Object Lock (compliance mode) | Immutable blob storage (time-based retention, locked) | Bucket Lock (retention policy, locked) |
| A separate place the production credentials can't reach | A backup account in AWS Organizations, AWS Backup vault lock | A separate subscription; Backup vault immutability | A separate project; backup vaults |
| Another cloud entirely | Copy to Azure or Google Cloud storage | Copy to S3 or GCS | Copy to S3 or Azure |

The **3-2-1 rule** still guides it: three copies, on two kinds of storage, one off-site (here: another account or cloud), and one of them immutable.

## 6. Prove it: restore tests and the DR runbook

- **Restore on a schedule** (monthly at least, automatically if you can, as the course's CI does) into a separate environment, and **time it**: that's your real RTO. Record the result in the runbook ("last tested").
- **Check the data**, not just the status: a known record, a row count, an application smoke test (the lab fetches a transfer made before the backup).
- **Write the DR runbook**: who declares a disaster, the order of recovery (identity, network, database, platform, apps, DNS), the commands, where credentials for the recovery account are kept, and how to fail back.
- **Rehearse**: a DR game day (topic 13.3) where the team recovers ITL Pay into another region or cloud from backups alone, with a stopwatch.

## Practice

1. Run `kind-dr-test.sh`. Then break it on purpose by removing the `defaultVolumeType=local` annotation (recreate the cluster): show the backup "succeeds" and the restore comes back without the transfer, and find the evidence in `kubectl -n velero get podvolumebackups`.
2. Add a Velero `Schedule` that backs up `itlpay` every 6 hours and keeps backups for 7 days. Trigger it and restore from it.
3. On one cloud, turn on PITR for ITL Pay's managed database, make transfers, then restore to a point two minutes before a deliberate `DELETE` (in a copy, never in production). Time it and record your RTO and RPO.
4. Create an immutable bucket in a second cloud (Object Lock, immutable blob, or Bucket Lock) and a scheduled `pg_dump` of ITL Pay into it. Show that deleting a backup is refused.
5. Write ITL Pay's DR runbook for "the whole primary region is gone", with a target RTO and RPO, the order of recovery and the evidence from exercises 2–4.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [🔥 The Ultimate Guide to Disaster Recovery: RTO, RPO, & Failover!](https://www.youtube.com/watch?v=OmASCUJEVy8) · ByteMonk · 11 min. Disaster recovery: RTO, RPO and failover strategies.
- [Master Kubernetes Backups with Velero: Step-by-Step Guide](https://www.youtube.com/watch?v=OzoC-wGfBnw) · DevOps & AI Toolkit · 16 min. Kubernetes backups and restores with Velero.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Design a solution for backup and disaster recovery](https://learn.microsoft.com/training/modules/design-solution-for-backup-disaster-recovery/)
- [Describe high availability and disaster recovery strategies](https://learn.microsoft.com/training/modules/describe-high-availability-disaster-recovery-strategies/)

**AWS (AWS Skill Builder):**

- [AWS Elastic Disaster Recovery Getting Started](https://skillbuilder.aws/learn/7WQ5EEXCJE/aws-elastic-disaster-recovery-getting-started/55ETVSR1E5)
- [AWS purpose-built database recovery: business continuity and disaster recovery strategies](https://skillbuilder.aws/learn/GC7UP23JS4/aws-purposebuilt-database-recovery-a-guide-to-business-continuity-and-disaster-recovery-strategies/TYYEXEDYXJ)
- [Amazon S3 Business Continuity and Disaster Recovery](https://skillbuilder.aws/learn/PS5FF6JM8X/amazon-simple-storage-service-amazon-s3-business-continuity-and-disaster-recovery/YVFDT8PZ8W)

