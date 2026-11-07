## What you will be able to do

- Explain what counts as a secret, how secrets leak, and what a secret store adds over environment variables and files.
- Store, version and read secrets in **AWS Secrets Manager**, **Azure Key Vault** and **Google Secret Manager**.
- Give each workload read access to **only its own secrets**, with the keyless identities from topics 8.3 and 9.5.
- Sync cloud secrets into Kubernetes with **External Secrets Operator**, and know the Secrets Store CSI driver alternative.
- Rotate a database password without downtime.
- Catch secrets before they reach Git with secret scanning and push protection.

## Why this matters at work

Leaked credentials are one of the most common ways attackers get in: keys committed to public repositories, passwords in CI logs, `.env` files in container images, a Slack message with a production password. Every security review and audit (PCI DSS for card payments, SOC 2, the Central Bank of Nigeria's and other regulators' IT standards) asks where secrets live, who can read them, and how often they rotate. "How do you manage secrets in Kubernetes?" is a near-certain interview question for platform roles, and "base64 in a Secret manifest in Git" is the answer that ends the interview.

## 1. Secrets and how they leak

A **secret** is anything that grants access: database passwords, API keys, signing keys, TLS private keys, webhook tokens, OAuth client secrets. (Keyless identities, from topics 8.3 and 9.5, are better still: no secret exists to leak. Use them wherever the other side supports it, and keep a secret store for what's left: database passwords, third-party API keys, certificates.)

| Leak | Prevention |
| --- | --- |
| Committed to Git (it stays in history even after you delete it) | Secret scanning with push protection; never write secrets to files in the repository |
| Printed in CI or Ansible logs | Masking, `no_log`, never `echo` or `set -x` around secrets |
| Baked into a container image | Pass at run time; scan images (Trivy finds secrets too, topic 8.2) |
| Shared by chat or email | A secret store with access by identity; share the secret's *name*, not its value |
| Never rotated, so an old leak stays useful | Rotation on a schedule, and immediately after any suspected leak |

## 2. What a secret store gives you

Compared with an environment variable on a VM or a Kubernetes Secret:

- **Access by identity, per secret:** the ITL Pay API can read `itlpay-dev-database` and nothing else.
- **Encryption with keys you control** (AWS KMS, Azure Key Vault keys, Cloud KMS), and an **audit log** of every read (CloudTrail, Azure Monitor, Cloud Audit Logs).
- **Versions:** the old and new password both exist during a rotation.
- **Rotation** support, and **one place** to change a value for every consumer.

## 3. The three stores

The lab stores one secret per environment: `itlpay-dev-database`, JSON with `username`, `password`, `host`, `port` and `dbname`. One secret serves the Kubernetes deployment (External Secrets, section 5) and the VMs (the Ansible lookup in topic 10.1).

```bash
pw=$(openssl rand -hex 24)        # set this as the database user's password too (topic 6.7)
json=$(jq -cn --arg pw "$pw" --arg host "<your database host>" \
  '{username: "itlpay", password: $pw, host: $host, port: "5432", dbname: "itlpay"}')
```

The value goes straight from the variable to the store, never to a file or your shell history.

**AWS Secrets Manager:**

```bash
aws secretsmanager create-secret --region af-south-1 --name itlpay-dev-database --secret-string "$json" \
  --tags Key=project,Value=itlpay
aws secretsmanager get-secret-value --region af-south-1 --secret-id itlpay-dev-database --query VersionId
```

(For RDS itself, `--manage-master-user-password` makes RDS create and rotate the master password in Secrets Manager for you. **Parameter Store** `SecureString` parameters are a cheaper option for simple values, without built-in rotation.)

**Azure Key Vault** (with Azure RBAC for permissions, the recommended model; soft delete is always on, and purge protection stops anyone, including an attacker, from deleting the vault for good):

```bash
az keyvault create -g rg-itlpay-dev -n kv-itlpay-dev -l southafricanorth \
  --enable-rbac-authorization true --enable-purge-protection true
az keyvault secret set --vault-name kv-itlpay-dev -n itlpay-dev-database --value "$json" --output none
```

(Key Vault also stores **keys** for encryption and signing, and **certificates** with automatic renewal.)

**Google Secret Manager** (with the data kept in South Africa):

```bash
gcloud secrets create itlpay-dev-database --replication-policy=user-managed --locations=africa-south1 \
  --labels=project=itlpay
printf '%s' "$json" | gcloud secrets versions add itlpay-dev-database --data-file=-
```

| | AWS Secrets Manager | Azure Key Vault | Google Secret Manager |
| --- | --- | --- | --- |
| Unit | Secret (versions labelled AWSCURRENT, AWSPREVIOUS) | Vault, containing secrets (each with versions), keys, certificates | Secret, with numbered versions |
| Permissions | IAM policies (and resource policies on the secret) | Azure RBAC roles on the vault or one secret (Key Vault Secrets User) | IAM on the project or one secret (Secret Manager Secret Accessor) |
| Encryption | KMS (AWS-managed or your own key) | Microsoft-managed or HSM-backed | Google-managed or your Cloud KMS key |
| Rotation | Built-in schedules with a Lambda function (managed for RDS) | Event Grid events near expiry, plus your function | Rotation schedules that publish to Pub/Sub, plus your function |
| Price model | Per secret per month, plus per API call | Per operation (and per key for HSM) | Per active version per month, plus per access |

Check the current prices before you create many secrets: they're small per secret, but reading a secret on every request instead of at start-up can add up.

## 4. Least privilege: one workload, its own secrets

Give **read** access to **one** secret, to **one** identity:

```bash
# AWS: the role the ESO controller assumes for itlpay (labs/secrets/stores/aws.yaml)
aws iam put-role-policy --role-name itlpay-dev-secrets-read --policy-name read-itlpay-database --policy-document '{
  "Version": "2012-10-17",
  "Statement": [{ "Effect": "Allow", "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
                  "Resource": "arn:aws:secretsmanager:af-south-1:<account>:secret:itlpay-dev-database-*" }]}'
# (Secrets Manager adds six random characters to the ARN, hence the -*)

# Azure: the managed identity from topic 9.5, on this one secret
az role assignment create --role "Key Vault Secrets User" --assignee "<id-itlpay client ID>" \
  --scope "$(az keyvault show -n kv-itlpay-dev --query id -o tsv)/secrets/itlpay-dev-database"

# Google Cloud: the Kubernetes service account's principal from topic 9.5, on this one secret
gcloud secrets add-iam-policy-binding itlpay-dev-database --role roles/secretmanager.secretAccessor \
  --member "principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/itlpay/sa/itlpay"
```

Writers are a different, smaller group: the pipeline or the rotation function, never the app.

## 5. Into Kubernetes: External Secrets Operator

**External Secrets Operator (ESO)** is a controller that reads from a secret store and writes ordinary Kubernetes Secrets, and keeps them up to date. Apps and Helm charts don't change: the lab's chart still reads `itlpay-db` (topic 9.4).

```text
cloud secret store  ◄── ESO controller (signs in with the cluster's workload identity, topic 9.5)
                             │  SecretStore "cloud": which store, how to sign in
                             │  ExternalSecret "itlpay-db": which secret, how to shape it
                             ▼
                      Kubernetes Secret itlpay-db  ──►  envFrom in the ITL Pay pods
```

```bash
helm upgrade --install external-secrets external-secrets/external-secrets --version 2.13.0 \
  -n external-secrets --create-namespace --wait
kubectl apply -f labs/secrets/stores/aws.yaml        # or azure.yaml, gcp.yaml
kubectl apply -f labs/secrets/externalsecret.yaml
kubectl -n itlpay get externalsecret itlpay-db       # STATUS SecretSynced, READY True
```

The ExternalSecret turns the JSON into the one key the app needs:

```yaml
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: SecretStore, name: cloud }
  target:
    name: itlpay-db
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        DATABASE_URL: "postgresql://{{ .username }}:{{ .password | urlquery }}@{{ .host }}:{{ .port }}/{{ .dbname }}"
  dataFrom:
    - extract: { key: itlpay-dev-database }
```

Every store in `labs/secrets/stores/` is named `cloud`, so the same ExternalSecret works on EKS, AKS, GKE and kind. The course's CI installs ESO on kind with its **fake** provider (fixed values, for tests only), checks that ESO creates `itlpay-db` with the right value and owns it, then restarts the API and runs `helm test`.

How each store signs in:

| | EKS | AKS | GKE |
| --- | --- | --- | --- |
| ESO's identity | The controller's own EKS Pod Identity, which then assumes a per-application role (`role:` in the store) | The app's service account `itlpay`, with Microsoft Entra Workload ID (`authType: WorkloadIdentity`) | The app's service account `itlpay`, with Workload Identity Federation for GKE |
| Why it matters | A namespace can only reach the secrets its role allows | Each namespace's store uses that namespace's identity | Same |

A **ClusterSecretStore** is one store for the whole cluster, managed by the platform team. It's convenient, but any namespace that can create an ExternalSecret can then read whatever the store's identity can. Prefer per-namespace stores and identities, as the lab does, unless the platform team restricts which namespaces may use it.

**The alternative, the Secrets Store CSI driver**, mounts secrets as **files** in the pod directly from the store, with providers for AWS, Azure and Google Cloud. It avoids copying secrets into etcd, but apps must read files, and syncing to environment variables needs a Kubernetes Secret anyway. ESO is more common for apps like ITL Pay that read environment variables.

## 6. Rotating a password without downtime

1. **Create the new password** in the database (a second user, or the same user with a new password if the database allows a transition).
2. **Write a new version** of the secret; the old version still exists.
3. **Consumers pick it up:** ESO refreshes within `refreshInterval`, but pods only read environment variables at start, so **restart them** (`kubectl rollout restart`, or a tool such as Reloader that restarts pods when their Secret changes). Re-run Ansible for the VMs.
4. **Check** every consumer uses the new password (database connection logs, `/health`), then **remove the old one**.

AWS automates this for RDS with managed rotation; on Azure and Google Cloud, a scheduled event triggers your function. Practise it before you need it: the day a password leaks is the wrong day to learn.

## 7. Stop secrets reaching Git

- **GitHub secret scanning and push protection** (free for public repositories, a paid add-on for private ones in organisations): GitHub blocks a push that contains a recognised key, such as an AWS access key or a GCP service-account key.
- **gitleaks** or **trufflehog** in CI and as a pre-commit hook, for patterns GitHub doesn't know.
- If a secret is pushed: **rotate it first** (assume it's already copied), then remove it from history if needed. Deleting the commit alone doesn't help.

## Practice

1. On one cloud, create `itlpay-dev-database` as in section 3 for your managed database from topic 9.5. Read it back with the CLI, then check the audit log shows your read.
2. Grant read access to the workload identity only (section 4). Prove a different identity (your own user without the role, or another service account) is refused.
3. Install ESO on your cluster, apply the store and the ExternalSecret, and check `itlpay-db` was created and the API's `/health` reports the database as up.
4. Rotate the password (section 6) with no failed requests: run a loop of `curl` against `/health` during the rotation and record any errors.
5. Turn on secret scanning and push protection for your portfolio repository, then try to push a fake AWS key (the documented example `AKIAIOSFODNN7EXAMPLE` isn't real). What happens?

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Back to Basics: Secrets Management](https://www.youtube.com/watch?v=NwEg5yKv_QE) · Amazon Web Services · 5 min. AWS on secrets management basics.
- [Azure Key Vault Tutorial | Secure secrets, keys and certificates easily](https://www.youtube.com/watch?v=PgujSug1ZbI) · Adam Marczak - Azure for Everyone · 19 min. A Key Vault tutorial: secrets, keys and certificates in practice.
- [Manage your Cloud Run secrets securely with Secret Manager](https://www.youtube.com/watch?v=JIE89dneaGo) · Google Cloud Tech · 7 min. Google Cloud Tech on Secret Manager.
- [Manage Kubernetes Secrets With External Secrets Operator (ESO)](https://www.youtube.com/watch?v=SyRZe5YVCVk) · DevOps & AI Toolkit · 12 min. Managing Kubernetes Secrets with External Secrets Operator.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Manage application secrets with Azure Key Vault](https://learn.microsoft.com/training/modules/manage-app-secrets-key-vault/)
- [Configure and secure Azure Key Vault](https://learn.microsoft.com/training/modules/configure-secure-key-vault/)
- [Manage keys and secrets in Azure Key Vault](https://learn.microsoft.com/training/modules/manage-keys-secrets-key-vault/)

**AWS (AWS Skill Builder):**

- [AWS Secrets Manager Getting Started](https://skillbuilder.aws/learn/26F7XCFDUX/aws-secrets-manager-getting-started/U1CPGYWQTK)
- [AWS CloudTrail Getting Started (the audit log of every secret read)](https://skillbuilder.aws/learn/6E2F4RVDA2/aws-cloudtrail-getting-started/N24M82M8YF)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Manage Security in Google Cloud](https://www.skills.google/course_templates/21)
- [Security & Identity Fundamentals](https://www.skills.google/course_templates/770)

