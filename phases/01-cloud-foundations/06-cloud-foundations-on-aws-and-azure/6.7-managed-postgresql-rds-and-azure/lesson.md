## What you will be able to do

- Explain what a managed database service does for you, and what remains your job.
- Create a private PostgreSQL database on **Amazon RDS** and on **Azure Database for PostgreSQL – Flexible Server**, in the data subnets from topic 6.4.
- Store the database password in **AWS Secrets Manager** and **Azure Key Vault**, and have the app read it at start-up using its role or managed identity.
- Connect ITL Pay Lite on the VMs from topic 6.5 to the database, with TLS.
- Configure backups, point-in-time restore, high availability across zones, and maintenance windows, and test a restore.
- Choose sizes and settings that keep a learner's bill small.
- Do the same on **Google Cloud**, and compare the three clouds.

## Why this matters at work

The database is where the money is, literally, for a payments system. Running PostgreSQL yourself means patching, backups, replication and failover, all of which are easy to get subtly wrong. Managed databases do that work, and are what most companies use in the cloud. But the important decisions are still yours: is it private? Is the password in a vault or in a config file? Are backups tested? Will it fail over to another zone? Those questions come up in every audit and every design review.

## 1. Managed versus self-managed

| Task | Self-managed (PostgreSQL on a VM) | Managed (RDS / Flexible Server) |
| --- | --- | --- |
| Install and patch PostgreSQL and the OS | You | Provider (in your maintenance window) |
| Backups and point-in-time restore | You script and test them | Automatic; you set retention and **test restores** |
| High availability and failover | You build replication and failover | One setting: a standby in another zone |
| Monitoring | You install it | Metrics and logs built in |
| Schema, queries, indexes, users, data | You | **Still you** |
| Network access and passwords | You | **Still you** |

## 2. Creating a private database

Use the **data subnets** from topic 6.4. The database must have **no public access**.

**AWS RDS:**

```bash
# A subnet group tells RDS which subnets (in which AZs) it may use
aws rds create-db-subnet-group --db-subnet-group-name itlpay-data \
  --db-subnet-group-description "ITL Pay data tier" --subnet-ids "$data_a" "$data_b"

aws rds create-db-instance --db-instance-identifier itlpay-db \
  --engine postgres --engine-version 17 \
  --db-instance-class db.t4g.micro --allocated-storage 20 --storage-type gp3 \
  --db-name itlpay --master-username itlpay_admin --manage-master-user-password \
  --db-subnet-group-name itlpay-data --vpc-security-group-ids "$sg_db" \
  --no-publicly-accessible --storage-encrypted \
  --backup-retention-period 7 --deletion-protection \
  --tags Key=owner,Value=ada Key=purpose,Value=topic-6.7
aws rds wait db-instance-available --db-instance-identifier itlpay-db
aws rds describe-db-instances --db-instance-identifier itlpay-db \
  --query "DBInstances[0].[Endpoint.Address, MasterUserSecret.SecretArn]" --output text
```

- `--manage-master-user-password` makes RDS generate the password and store it in **Secrets Manager**, with rotation. Nobody ever types or sees it.
- `--no-publicly-accessible` and the `sg-db` group (5432 from `sg-app` only) keep it private.
- `--deletion-protection` stops accidental deletion (turn it off before deleting at the end of the lab).

**Azure Database for PostgreSQL – Flexible Server:**

```bash
# A private DNS zone so the server name resolves to its private address inside the VNet
az network private-dns zone create -g rg-itlpay-net -n itlpay.private.postgres.database.azure.com -o none
az network private-dns link vnet create -g rg-itlpay-net -z itlpay.private.postgres.database.azure.com \
  -n link-itlpay -v itlpay-vnet -e false -o none

# The data subnet must be delegated to the service (one-off)
az network vnet subnet update -g rg-itlpay-net --vnet-name itlpay-vnet -n data \
  --delegations Microsoft.DBforPostgreSQL/flexibleServers -o none

az postgres flexible-server create -g rg-itlpay-net -n itlpay-db-ada -l southafricanorth \
  --version 17 --tier Burstable --sku-name Standard_B1ms --storage-size 32 \
  --vnet itlpay-vnet --subnet data --private-dns-zone itlpay.private.postgres.database.azure.com \
  --admin-user itlpay_admin --admin-password "$(openssl rand -base64 24)" \
  --backup-retention 7 --tags owner=ada purpose=topic-6.7
```

This uses **private access (VNet integration)**: the server gets an address in the delegated data subnet, and has no public endpoint at all. (The alternative is public access with a **private endpoint**, as for storage in topic 6.6.) A delegated subnet can only hold Flexible Servers, which is why the design gave the data tier its own subnet.

The admin password above is generated and never shown. Store it in Key Vault straight away (section 3). Better still, turn on **Microsoft Entra ID authentication** for the server, so apps sign in with their managed identity and there's no password at all; you'll do that in Phase 2.

## 3. Passwords in a vault, read by the app's identity

The app needs the connection details. They must not be in the image (topic 5.2), the user data (topic 6.5) or Git (topic 4.1).

**AWS:** the RDS-managed secret holds `username` and `password`. Allow the app role to read **that one secret**:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "arn:aws:secretsmanager:af-south-1:123456789012:secret:rds!db-xxxx"
  }]
}
```

**Azure:** create a Key Vault using **RBAC authorisation**, put the password in it, and give the VM's managed identity *Key Vault Secrets User* on the vault:

```bash
az keyvault create -g rg-itlpay-net -n kv-itlpay-ada -l southafricanorth --enable-rbac-authorization true -o none
az keyvault secret set --vault-name kv-itlpay-ada -n db-password --value "<the password>" -o none
az role assignment create --assignee-object-id "$(az vm show -g rg-itlpay-net -n itlpay-app-1 --query identity.principalId -o tsv)" \
  --assignee-principal-type ServicePrincipal --role "Key Vault Secrets User" \
  --scope "$(az keyvault show -n kv-itlpay-ada --query id -o tsv)"
```

(Better: generate the password straight into the vault, so it never appears in your terminal or history.)

Then a small start-up script on each VM fetches the secret with the VM's identity and starts the container. Replace the `ExecStart` from topic 6.5 with a script like this:

```bash
#!/usr/bin/env bash
# /usr/local/bin/itlpay-start.sh: fetch the DB password with the VM's identity, then start ITL Pay Lite
set -euo pipefail
if [[ "${CLOUD:?set CLOUD=aws or azure}" == aws ]]; then
  secret=$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_ARN" --query SecretString --output text)
  user=$(jq -r .username <<<"$secret"); pass=$(jq -r .password <<<"$secret")
else
  az login --identity --output none
  user=itlpay_admin; pass=$(az keyvault secret show --vault-name "$KEY_VAULT" -n db-password --query value -o tsv)
fi
enc_pass=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$pass")
exec docker run --rm --name itlpay -p 8080:8080 -e APP_ENV="${APP_ENV:-lab}" \
  -e DATABASE_URL="postgresql://${user}:${enc_pass}@${DB_HOST}:5432/itlpay?sslmode=require" \
  ghcr.io/YOUR-USERNAME/itlpay-lite:1.0.0
```

The script needs `jq` and the cloud's CLI on the VM: add `jq` to the cloud-init `packages:` list, and install the AWS CLI or Azure CLI in `runcmd:` with the vendor's installer (topic 6.3). Run the script from the `itlpay` systemd unit's `ExecStart=`, with `CLOUD`, `DB_HOST` and `DB_SECRET_ARN` or `KEY_VAULT` set by `Environment=` lines (these are names, not secrets).

Points to notice:

- The password is URL-encoded, because generated passwords contain characters such as `/` and `@` that break connection URLs.
- `sslmode=require` makes the connection use TLS (topic 2.4). Both services support enforcing TLS on the server side too (RDS parameter `rds.force_ssl`, on by default for PostgreSQL 15 and later; Flexible Server's `require_secure_transport`, on by default).
- The password is in the container's environment, which anyone with `docker inspect` on the VM can read. That's acceptable for this lab; Phase 2 moves to identity-based database login and secret mounts.

## 4. Backups and restore

Both services take **automatic daily backups** plus transaction logs, so you can restore to **any second** within the retention period (point-in-time restore). A restore creates a **new** server; you then point the app at it.

```bash
# AWS: restore to a new instance as of 10 minutes ago
aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier itlpay-db \
  --target-db-instance-identifier itlpay-db-restore --restore-time "$(date -u -d '-10 min' +%Y-%m-%dT%H:%M:%SZ)" \
  --db-subnet-group-name itlpay-data --vpc-security-group-ids "$sg_db" --no-publicly-accessible

# Azure
az postgres flexible-server restore -g rg-itlpay-net -n itlpay-db-restore --source-server itlpay-db-ada \
  --restore-time "$(date -u -d '-10 min' +%Y-%m-%dT%H:%M:%SZ)"
```

**A backup you've never restored is a hope, not a backup.** Test restores regularly, measure how long they take (your **RTO**, recovery time objective) and how much data you'd lose (your **RPO**, recovery point objective), and write the procedure into a runbook (topic 4.3).

For extra protection, copy backups to another region or account (RDS cross-region automated backups or AWS Backup; Flexible Server geo-redundant backup), so a disaster or a compromised admin can't destroy every copy.

## 5. High availability and maintenance

- **AWS:** **Multi-AZ** keeps a synchronous standby in another AZ and fails over automatically (typically within a minute or two); the DNS name stays the same. `--multi-az` at creation, or modify later.
- **Azure:** **zone-redundant high availability** places a standby in another zone (`--high-availability ZoneRedundant`; not available on the Burstable tier).

Both double the cost, so labs don't use them, but production must. Apps must **reconnect** after a failover: test it (both services can force a failover) and check the app recovers. ITL Pay Lite opens a new connection per request, so it recovers on its own.

**Maintenance windows:** the provider applies patches in a window you choose (for example Sunday 02:00–03:00 Lagos time); minor version upgrades may restart the server. Pick a quiet time and watch the first one.

## 6. Keeping the lab cheap

- The smallest burstable sizes (`db.t4g.micro`, `Standard_B1ms`), 20–32 GB storage, single zone, 7-day backups.
- **Stop** the database when not in use: RDS instances can be stopped for up to 7 days (then they start again automatically); Flexible Servers can be stopped for up to 7 days too. Storage and backups still cost money while stopped.
- **Delete** after the lab: turn off deletion protection first (RDS), choose whether to keep a final snapshot, and on Azure delete the server (or the resource group). Check for leftover snapshots.

## Google Cloud: Cloud SQL for PostgreSQL

Cloud SQL runs in Google's own network, connected to your VPC by the **private services access** peering you set up in topic 6.4. Give it a **private IP only**.

```bash
gcloud services enable sqladmin.googleapis.com secretmanager.googleapis.com
gcloud sql instances create itlpay-db --database-version=POSTGRES_17 --edition=ENTERPRISE \
  --tier=db-custom-1-3840 --region=africa-south1 \
  --network=itlpay-vpc --no-assign-ip --ssl-mode=ENCRYPTED_ONLY \
  --backup-start-time=01:00 --enable-point-in-time-recovery --retained-backups-count=7 \
  --deletion-protection --user-labels=owner=ada,purpose=topic-6-7
gcloud sql databases create itlpay --instance=itlpay-db

# The app user's password goes straight into Secret Manager, never on screen
openssl rand -base64 24 | tr -d '\n' | gcloud secrets create db-password --replication-policy=automatic --data-file=-
gcloud sql users create itlpay --instance=itlpay-db --password="$(gcloud secrets versions access latest --secret=db-password)"
gcloud secrets add-iam-policy-binding db-password \
  --member="serviceAccount:itlpay-app@$(gcloud config get-value project).iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
gcloud sql instances describe itlpay-db --format="value(ipAddresses[0].ipAddress)"      # the private IP for DB_HOST
```

- `--no-assign-ip` with `--network`: a private IP only, no public endpoint.
- `--ssl-mode=ENCRYPTED_ONLY` refuses unencrypted connections.
- The VM's start-up script gets the password the same way as on the other clouds, with its own identity: add a third branch to `itlpay-start.sh`:

```bash
elif [[ "$CLOUD" == gcp ]]; then
  user=itlpay; pass=$(gcloud secrets versions access latest --secret=db-password)
```

(Make the existing `else` branch `elif [[ "$CLOUD" == azure ]]; then`.) Google also offers **IAM database authentication** and the **Cloud SQL Auth Proxy**, which remove the password altogether; you'll use them in Phase 2.

**Backups and restore:** daily backups plus point-in-time recovery; a restore creates a **new instance** with `gcloud sql instances clone itlpay-db itlpay-db-restore --point-in-time='2026-11-06T13:04:00Z'`. **High availability:** `--availability-type=REGIONAL` keeps a standby in another zone (double the cost; not for labs). **Maintenance windows:** `gcloud sql instances patch itlpay-db --maintenance-window-day=SUN --maintenance-window-hour=1`.

**Keeping it cheap:** use the smallest tier, stop it when not in use (`gcloud sql instances patch itlpay-db --activation-policy=NEVER`; storage is still billed), and delete it after the lab (turn off deletion protection first with `--no-deletion-protection`).

## Practice

1. Create the database on both clouds, privately, with the password in Secrets Manager / Key Vault.
2. Update the VMs from topic 6.5 to fetch the secret with their identity and connect. Show `curl localhost:8080/health` now returns `{"status":"UP","db":"up"}` on both, and make a transfer.
3. Prove the databases aren't reachable from the internet, and that from a VM in the **public** subnet `nc -vz <db-host> 5432` fails while from the app VM it succeeds.
4. Make a few transfers, note the time, make more, then do a point-in-time restore to the earlier time on one cloud. Connect to the restored server and show only the earlier transfers exist. Time the restore and write a short runbook.
5. Stop or delete both databases and check the bill next day.
6. **Google Cloud:** create the Cloud SQL instance with a private IP, store the password in Secret Manager, connect ITL Pay Lite from the Compute Engine VM, and do a point-in-time clone.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [How to Set Up a Postgres Database on Amazon RDS](https://www.youtube.com/watch?v=XF1ZADfH0EQ) · Database Star · 10 min. Setting up PostgreSQL on Amazon RDS.
- [Create Azure Database for PostgreSQL Flexible Server | Using Azure Portal](https://www.youtube.com/watch?v=AeQi195rg_4) · Cloud Knowledge · 9 min. Creating an Azure Database for PostgreSQL Flexible Server.
- [AZ-900 Episode 27 | Azure Key Vault | Secret, Key and Certificate Management](https://www.youtube.com/watch?v=AA3yYg9Zq9w) · Adam Marczak - Azure for Everyone · 9 min. Azure Key Vault: secrets, keys and certificates (AZ-900).
- [How to connect a CloudSQL instance with ONLY Private IP?](https://www.youtube.com/watch?v=IbK7trf1DHU) · Learn GCP with Mahesh · 6 min. Connecting to a Cloud SQL instance that has only a private IP.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Configure and migrate to Azure Database for PostgreSQL (learning path)](https://learn.microsoft.com/training/paths/microsoft-learn-azure-database-for-postgresql/)
- [Manage keys and secrets in Azure Key Vault](https://learn.microsoft.com/training/modules/manage-keys-secrets-key-vault/)

**AWS (AWS Skill Builder):**

- [Fundamentals of Amazon RDS for PostgreSQL](https://skillbuilder.aws/learn/AK479CRG5K/fundamentals-of-amazon-rds-for-postgresql/FB4ZR9N2DU)
- [Amazon RDS for PostgreSQL - Troubleshooting](https://skillbuilder.aws/learn/GN8V5D3YQA/amazon-relational-database-service-amazon-rds-for-postgresql--troubleshooting/6PYYKHYNUW)
- [AWS Secrets Manager Getting Started](https://skillbuilder.aws/learn/26F7XCFDUX/aws-secrets-manager-getting-started/U1CPGYWQTK)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Essential Google Cloud Infrastructure: Core Services](https://www.skills.google/course_templates/49)

