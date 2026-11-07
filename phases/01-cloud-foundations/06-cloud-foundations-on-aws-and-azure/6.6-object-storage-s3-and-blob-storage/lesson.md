## What you will be able to do

- Explain object storage (buckets/containers, objects, keys) and when to use it instead of disks or databases.
- Create private, encrypted, versioned storage on **AWS S3** and **Azure Blob Storage**, and upload, list and download objects.
- Control access with identities (IAM, RBAC) instead of public access or account keys, and share single files safely with **pre-signed URLs** and **SAS tokens**.
- Choose storage classes and tiers, and set lifecycle rules that move or delete old data automatically.
- Protect data against deletion and ransomware with versioning, soft delete and immutability.
- Reach storage privately from your network (gateway endpoint, private endpoint).
- Do the same on **Google Cloud**, and compare the three clouds.

## Why this matters at work

Object storage holds most of the world's cloud data: backups, logs, statements, documents, images, data for analytics, Terraform state. It's also where the most famous cloud breaches happened: buckets accidentally left public, exposing millions of records. A bank's auditors will ask how statements are encrypted, who can read them, how long they're kept and whether they can be deleted. Every cloud engineer must be able to answer.

## 1. Object storage in plain words

- A **bucket** (AWS) or **container** (Azure, inside a **storage account**) holds **objects**.
- An **object** is a file plus metadata, found by its **key** (its full name, e.g. `statements/2026/11/ACC-1001.pdf`). The slashes look like folders but are just part of the name.
- You read and write whole objects over HTTPS APIs; you don't mount it like a disk (for that, see EBS/managed disks, or file services like EFS and Azure Files).
- It's practically unlimited, very durable (data is stored in several copies or zones), and cheap per GB.

| Use object storage for | Not for |
| --- | --- |
| Backups, logs, exports, documents, images, static websites, data lakes | A database's live data files (use a managed database) |
| Sharing files between services | Files many processes edit in place (use a file share) |

| | AWS | Azure |
| --- | --- | --- |
| Top level | Bucket (globally unique name, in a region) | **Storage account** (globally unique name) → **container** |
| Address | `https://<bucket>.s3.<region>.amazonaws.com/<key>` | `https://<account>.blob.core.windows.net/<container>/<blob>` |
| Redundancy | Standard keeps copies across ≥3 AZs | You choose: LRS (one data centre), ZRS (zones), GRS (to a paired region) |

## 2. Private by default, and keep it that way

**AWS:** new buckets have **Block Public Access** on, **ACLs disabled** (bucket owner enforced) and **default encryption** (SSE-S3). Keep all of them. Turn Block Public Access on at the **account** level too, so no bucket can be made public by mistake.

**Azure:** set **`--allow-blob-public-access false`** on the storage account, require **TLS 1.2** or later, and prefer **Entra ID authorisation** over account keys (you can disable **shared key** access entirely with `--allow-shared-key-access false`, once your tools use Entra ID).

```bash
# AWS
aws s3api create-bucket --bucket itlpay-statements-ada-1234 --region af-south-1 \
  --create-bucket-configuration LocationConstraint=af-south-1
aws s3api put-bucket-versioning --bucket itlpay-statements-ada-1234 --versioning-configuration Status=Enabled
aws s3 cp statement.pdf s3://itlpay-statements-ada-1234/statements/2026/11/ACC-1001.pdf
aws s3 ls s3://itlpay-statements-ada-1234/statements/ --recursive

# Azure
az storage account create -g rg-itlpay -n itlpaystmtada1234 -l southafricanorth --sku Standard_ZRS \
  --allow-blob-public-access false --min-tls-version TLS1_2 --kind StorageV2
az storage container create --account-name itlpaystmtada1234 -n statements --auth-mode login
az storage blob upload --account-name itlpaystmtada1234 -c statements -n 2026/11/ACC-1001.pdf \
  -f statement.pdf --auth-mode login
az storage blob list --account-name itlpaystmtada1234 -c statements --auth-mode login -o table
```

`--auth-mode login` uses your Entra ID identity, which needs a **data role** such as *Storage Blob Data Contributor* on the account (topic 6.2), even if you're Owner. That surprises everyone once.

Encryption: both clouds encrypt all data at rest by default with keys they manage. Regulated workloads often require **customer-managed keys** (AWS KMS keys; Azure Key Vault keys), so the company controls and can revoke the key, and every use is logged.

## 3. Access: identities, not keys

| Need | AWS | Azure |
| --- | --- | --- |
| An app reads one bucket/container | IAM role with a policy on that bucket (topic 6.2) | Managed identity with *Storage Blob Data Reader* on that account or container |
| Another account / subscription needs access | Bucket policy naming the other account's role | RBAC assignment for the other tenant's identity, or a private endpoint |
| Give a customer one file for 15 minutes | **Pre-signed URL** | **SAS token**, ideally a **user delegation SAS** (signed with Entra ID, not the account key) |
| Avoid | Public buckets; IAM user access keys in apps | Account keys in apps; account-wide, long-lived SAS tokens |

```bash
aws s3 presign s3://itlpay-statements-ada-1234/statements/2026/11/ACC-1001.pdf --expires-in 900

az storage blob generate-sas --account-name itlpaystmtada1234 -c statements -n 2026/11/ACC-1001.pdf \
  --permissions r --expiry "$(date -u -d '+15 minutes' '+%Y-%m-%dT%H:%MZ')" \
  --auth-mode login --as-user --full-uri
```

Anyone with the URL can use it until it expires, so keep expiry short, share it only over HTTPS, and never log it.

From the VMs in topic 6.5, using their identities:

```bash
# On the EC2 instance (after attaching an S3 read policy for this bucket to itlpay-app-role)
aws s3 cp s3://itlpay-statements-ada-1234/statements/2026/11/ACC-1001.pdf /tmp/

# On the Azure VM (after granting its managed identity Storage Blob Data Reader)
az login --identity
az storage blob download --account-name itlpaystmtada1234 -c statements -n 2026/11/ACC-1001.pdf \
  -f /tmp/s.pdf --auth-mode login
```

## 4. Storage classes, tiers and lifecycle rules

Data that's rarely read can be stored more cheaply, at the cost of retrieval fees and delays.

| Use | AWS S3 class | Azure blob tier |
| --- | --- | --- |
| Read often | Standard | Hot |
| Read occasionally (monthly) | Standard-IA | Cool |
| Rarely, but needed fast | Glacier Instant Retrieval | Cold |
| Archive (hours to restore) | Glacier Flexible Retrieval, Deep Archive | Archive |
| Unknown pattern | Intelligent-Tiering (moves objects automatically) | (Lifecycle rules based on last access) |

**Lifecycle rules** apply this automatically. A typical rule for statements: move to a cheaper tier after 90 days, to archive after one year, and delete after seven years (or whatever the retention policy says).

```bash
# AWS: lifecycle.json
# {"Rules":[{"ID":"statements","Filter":{"Prefix":"statements/"},"Status":"Enabled",
#   "Transitions":[{"Days":90,"StorageClass":"STANDARD_IA"},{"Days":365,"StorageClass":"GLACIER"}],
#   "Expiration":{"Days":2555},"NoncurrentVersionExpiration":{"NoncurrentDays":30}}]}
aws s3api put-bucket-lifecycle-configuration --bucket itlpay-statements-ada-1234 \
  --lifecycle-configuration file://lifecycle.json

# Azure: lifecycle management policy (policy.json with a similar rule using tierToCool, tierToArchive, delete)
az storage account management-policy create --account-name itlpaystmtada1234 -g rg-itlpay --policy @policy.json
```

Lifecycle rules for **logs** (delete after 30–90 days) are one of the easiest cost savings in any account.

## 5. Protection against deletion and ransomware

| Protection | AWS | Azure |
| --- | --- | --- |
| Keep old versions when objects are overwritten or deleted | **Versioning** | **Blob versioning** |
| Recover deleted items for a period | (Versioning: delete markers) | **Soft delete** for blobs and containers |
| Nobody, not even an admin, can delete or change for N days | **Object Lock** (compliance mode) | **Immutable storage** (time-based retention policy, locked) |
| Copy to another region | **Replication** (CRR) | **Object replication**, or GRS redundancy |
| Backups as a service | AWS Backup | Azure Backup (for blobs) |

Ransomware attackers who get admin access try to delete backups first. Immutable copies, in a separate account or subscription with different admins, are what make backups survive that. Regulators increasingly expect it.

## 6. Private access from your network

- **AWS:** add a **gateway VPC endpoint** for S3 to the app route table (topic 6.4). It's free, keeps traffic off the internet and the NAT gateway, and a bucket policy can then **require** that requests come through it (`aws:SourceVpce`).
- **Azure:** add a **private endpoint** for the storage account's `blob` service in the app subnet, with the **private DNS zone** `privatelink.blob.core.windows.net` linked to the VNet, then turn off public network access on the account (`--public-network-access Disabled`). From the VM, `getent hosts itlpaystmtada1234.blob.core.windows.net` should now return a `10.30.x.x` address.

## Google Cloud Storage

| | Google Cloud |
| --- | --- |
| Top level | **Bucket** (globally unique name) in a **location**: a region (`africa-south1`), a dual-region or a multi-region |
| Address | `https://storage.googleapis.com/<bucket>/<object>`, or `gs://<bucket>/<object>` in tools |
| Private by default | **Public access prevention** on the bucket (and as an Organization Policy), with **uniform bucket-level access** so only IAM controls access |
| An app reads one bucket | The VM's **service account** with `roles/storage.objectViewer` on that bucket |
| Share one file for 15 minutes | A **signed URL** (`gcloud storage sign-url`, signed by a service account you may impersonate) |
| Classes | Standard, Nearline (accessed less than once a month), Coldline (once a quarter), Archive (once a year); **Autoclass** moves objects automatically |
| Lifecycle rules | **Object Lifecycle Management** (`--lifecycle-file`) |
| Protection | **Object Versioning**, **soft delete** (deleted objects kept for a set period; on by default), **retention policies** with **Bucket Lock** (immutable) |
| Private access from your network | **Private Google Access** on the subnet (topic 6.4); VPC Service Controls for stricter perimeters |

```bash
gcloud storage buckets create gs://itlpay-statements-ada-1234 --location=africa-south1 \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update gs://itlpay-statements-ada-1234 --versioning
gcloud storage cp statement.pdf gs://itlpay-statements-ada-1234/statements/2026/11/ACC-1001.pdf
gcloud storage ls -r gs://itlpay-statements-ada-1234/statements/

# Let the app servers' service account read it
gcloud storage buckets add-iam-policy-binding gs://itlpay-statements-ada-1234 \
  --member="serviceAccount:itlpay-app@$(gcloud config get-value project).iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

# Lifecycle: cheaper class after 90 days, Archive after a year, delete after 7 years
cat > lifecycle.json <<'EOF'
{"rule": [
  {"action": {"type": "SetStorageClass", "storageClass": "NEARLINE"}, "condition": {"age": 90, "matchesPrefix": ["statements/"]}},
  {"action": {"type": "SetStorageClass", "storageClass": "ARCHIVE"}, "condition": {"age": 365, "matchesPrefix": ["statements/"]}},
  {"action": {"type": "Delete"}, "condition": {"age": 2555, "matchesPrefix": ["statements/"]}}
]}
EOF
gcloud storage buckets update gs://itlpay-statements-ada-1234 --lifecycle-file=lifecycle.json
```

From the topic 6.5 VM (no keys): `gcloud storage cp gs://itlpay-statements-ada-1234/statements/2026/11/ACC-1001.pdf /tmp/`.

## Practice

1. Create a private, versioned bucket on AWS and a private storage account (ZRS) with a container on Azure. Upload, list and download a test file with the CLIs.
2. Try to read the file anonymously with `curl` on each cloud's URL and show it's refused. Then create a 5-minute pre-signed URL and a user delegation SAS, show both work with `curl`, and show they stop working after expiry.
3. Give your topic 6.5 VMs read access (IAM policy; *Storage Blob Data Reader*) and download the file from each VM with no keys.
4. Add a lifecycle rule on each: move `logs/` to a cooler tier after 30 days and delete after 90. Check it in the consoles.
5. Turn on S3 versioning and Azure blob soft delete; delete the file and restore it on both.
6. (Optional) Add the S3 gateway endpoint and an Azure private endpoint, and show from the VMs that the storage name resolves privately on Azure.
7. **Google Cloud:** create the private, versioned bucket, add the lifecycle rule, give the VM's service account read access, and download the file from the VM. Delete an object and restore it from soft delete or a non-current version.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Amazon/AWS S3 (Simple Storage Service) Basics | S3 Tutorial, Creating a Bucket | AWS for Beginners](https://www.youtube.com/watch?v=mDRoyPFJvlU) · Tiny Technical Tutorials · 10 min. Amazon S3 basics: buckets and objects.
- [AZ-900 Episode 11 | Azure Storage Services | Blob, Queue, Table, Files, Disk and Storage Tiers](https://www.youtube.com/watch?v=_Qlkvd4ZQuo) · Adam Marczak - Azure for Everyone · 19 min. Azure storage services and access tiers (AZ-900).
- [Bucket options in Cloud Storage](https://www.youtube.com/watch?v=8DMOJ6Lgm7s) · Google Cloud Tech · 4 min. Cloud Storage bucket options, from Google.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Describe Azure storage services](https://learn.microsoft.com/training/modules/describe-azure-storage-services/)
- [Secure your Azure Storage account](https://learn.microsoft.com/training/modules/secure-azure-storage-account/)
- [AZ-104: Implement and manage storage in Azure (learning path)](https://learn.microsoft.com/training/paths/az-104-manage-storage/)

**AWS (AWS Skill Builder):**

- [Amazon S3 Getting Started](https://skillbuilder.aws/learn/H99Y6PR2F7/amazon-s3-getting-started/TCVDGQFEJR)
- [Securing and Protecting Your Data in Amazon S3](https://skillbuilder.aws/learn/EQ3KGNCAC8/securing-and-protecting-your-data-in-amazon-simple-storage-service-amazon-s3/S7VEVDJ5D9)
- [Amazon S3 Cost Optimization](https://skillbuilder.aws/learn/VURSUWRSKA/amazon-simple-storage-service-amazon-s3-cost-optimization/6ZZF9NUFTH)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Essential Google Cloud Infrastructure: Core Services](https://www.skills.google/course_templates/49)

