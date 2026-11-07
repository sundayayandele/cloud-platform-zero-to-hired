## What you will be able to do

- Explain why long-lived cloud keys in a CI system are dangerous, and how OIDC federation replaces them.
- Read a GitHub Actions OIDC token's claims (`sub`, `aud`, `repository`, `ref`, `environment`) and use them to restrict who can sign in.
- Set up keyless login from GitHub Actions to **AWS** (an IAM OIDC provider and a role), **Azure** (an Entra ID app with federated credentials) and **Google Cloud** (Workload Identity Federation).
- Give the pipeline separate, least-privilege identities for planning and applying.
- Use the official login actions in a workflow, and debug "not authorized" errors.
- Explain what to check in a security review of a pipeline's cloud access.

## Why this matters at work

For years, the usual way to let a pipeline deploy was to create a cloud user, generate an access key, and paste it into the CI system's secrets. Those keys never expire, are copied into many places, and leak: through logs, through compromised dependencies, through a stolen laptop with a `.env` file. Attackers scan public repositories and CI logs for them. **Workload identity federation** removes the keys entirely: the cloud trusts GitHub to say which workflow is asking, and hands out credentials that last minutes. All three clouds support it, banks and auditors increasingly require it, and it's one of the first things a security reviewer checks in your pipelines.

## 1. How OIDC federation works

```text
GitHub Actions job                          Cloud (AWS / Azure / Google Cloud)
  1. asks GitHub for an OIDC token  ──►  token says: "repo ada-obi/itlpay, workflow terraform.yml,
     (needs permissions: id-token: write)            branch main, environment dev-aws", signed by GitHub
  2. sends the token to the cloud   ──►  3. checks the signature and the claims against its trust policy
  5. uses short-lived credentials   ◄──  4. issues credentials for one role or identity, valid ~1 hour
```

Nothing secret is stored in GitHub. If the token leaks, it's useless within minutes, and only works for that exact repository and branch.

The important **claims** in the token:

| Claim | Example | Use it to restrict to... |
| --- | --- | --- |
| `iss` | `https://token.actions.githubusercontent.com` | GitHub (all clouds check this) |
| `aud` | `sts.amazonaws.com`, `api://AzureADTokenExchange`, or your Google provider's URL | The intended cloud |
| `sub` | `repo:ada-obi/itlpay:ref:refs/heads/main`, `repo:ada-obi/itlpay:environment:dev-aws` or `repo:ada-obi/itlpay:pull_request` (or the immutable form below) | One repository **and** one branch, environment or event |
| `repository_id`, `repository_owner_id`, `ref`, `environment`, `job_workflow_ref` | `821093847`, `5544123`, ... | Finer conditions (Google Cloud attribute conditions, AWS condition keys) |

The **`sub` claim is your main control.** Trusting `repo:ada-obi/*` would let any repository in that account, including a new one an attacker creates in a compromised account, sign in. Trust exactly the repository and branch or environment you mean.

**Two subject formats.** Names can be renamed, transferred or reused: if you delete `ada-obi/itlpay` and someone later creates an account or repository with the same name, a name-based trust would accept their tokens. So GitHub added an **immutable subject** that also carries the numeric owner and repository IDs, which are never reused:

```text
name-based (older repositories):   repo:ada-obi/itlpay:environment:dev-aws
immutable (new repositories):      repo:ada-obi@5544123/itlpay@821093847:environment:dev-aws
```

Since 15 July 2026, GitHub uses the immutable format automatically for repositories that are **created, renamed or transferred**; older repositories keep the name-based format until their owner opts in (repository or organisation OIDC settings). The repository you create for this module will almost certainly emit the immutable format, so the examples below use it. Get the IDs with:

```bash
gh api repos/ada-obi/itlpay --jq '.owner.id, .id'     # owner ID, then repository ID
```

Whatever the format, **check the exact `sub` your workflow emits** (section 7) and trust that string.

In the workflow, the job needs:

```yaml
permissions:
  id-token: write      # allows the job to request an OIDC token
  contents: read
```

## 2. AWS: an OIDC provider and a role

Create the identity provider once per AWS account (the console's IAM → Identity providers does the same):

```bash
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

Then a role the pipeline may assume, with a **trust policy** limited to your repository and environment:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:ada-obi@5544123/itlpay@821093847:environment:dev-aws"
      }
    }
  }]
}
```

```bash
aws iam create-role --role-name itlpay-gha-apply-dev --assume-role-policy-document file://trust.json
aws iam attach-role-policy --role-name itlpay-gha-apply-dev --policy-arn <a narrow policy for the dev resources>
```

In the workflow:

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ vars.AWS_APPLY_ROLE_ARN }}
    aws-region: af-south-1
```

## 3. Azure: an Entra ID app with federated credentials

```bash
az ad app create --display-name itlpay-gha-dev
appid=$(az ad app list --display-name itlpay-gha-dev --query "[0].appId" -o tsv)
az ad sp create --id "$appid"

# Trust exactly one repository and environment
az ad app federated-credential create --id "$appid" --parameters '{
  "name": "itlpay-dev-azure",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:ada-obi@5544123/itlpay@821093847:environment:dev-azure",
  "audiences": ["api://AzureADTokenExchange"]
}'

# Least privilege: Contributor on the dev resource group only (not the subscription)
az role assignment create --assignee "$appid" --role Contributor \
  --scope "$(az group show -n rg-itlpay-dev-net --query id -o tsv)"
```

(A **user-assigned managed identity** with a federated credential works the same way and avoids creating an app registration. Entra ID also offers **flexible** federated credentials, which match an expression over several claims, such as the `sub` pattern and `repository_id`, when one credential must cover many branches.)

In the workflow, `azure/login` uses the app's IDs, which aren't secrets:

```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ vars.AZURE_CLIENT_ID }}
    tenant-id: ${{ vars.AZURE_TENANT_ID }}
    subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

Terraform's azurerm provider and backend use OIDC when `ARM_USE_OIDC=true` is set (with `ARM_CLIENT_ID`, `ARM_TENANT_ID` and `ARM_SUBSCRIPTION_ID`, which `azure/login` doesn't set for Terraform, so pass them as environment variables in the Terraform steps).

## 4. Google Cloud: Workload Identity Federation

```bash
project=$(gcloud config get-value project)
number=$(gcloud projects describe "$project" --format="value(projectNumber)")
gcloud iam workload-identity-pools create github --location=global --display-name="GitHub Actions"
gcloud iam workload-identity-pools providers create-oidc itlpay --location=global --workload-identity-pool=github \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.environment=assertion.environment" \
  --attribute-condition="assertion.repository_id == '821093847' && assertion.repository_owner_id == '5544123'"

# A service account for the pipeline, which only that repository (and environment) may impersonate
gcloud iam service-accounts create itlpay-gha-apply-dev
gcloud iam service-accounts add-iam-policy-binding "itlpay-gha-apply-dev@$project.iam.gserviceaccount.com" \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$number/locations/global/workloadIdentityPools/github/attribute.environment/dev-gcp"
```

The **attribute condition** rejects tokens from any other repository before anything else is checked: always set one. It uses the numeric `repository_id` and `repository_owner_id` claims rather than names, for the same reason as the immutable subject: IDs are never reused. Then grant the service account only the roles it needs on the dev project.

In the workflow:

```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}   # projects/NUMBER/locations/global/workloadIdentityPools/github/providers/itlpay
    service_account: ${{ vars.GCP_APPLY_SERVICE_ACCOUNT }}
```

It sets Application Default Credentials, so `gcloud` and Terraform's google provider just work.

## 5. Side by side

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Trust GitHub | IAM OIDC identity provider | Federated credential on an app registration or managed identity | Workload identity pool and OIDC provider |
| Who the pipeline becomes | An IAM role | A service principal / managed identity | A service account (or the federated principal directly) |
| Restrict to repo and branch/environment | `sub` (and `aud`) conditions in the role's trust policy | The federated credential's `subject` (exact match) | Attribute condition, and the principal set in the IAM binding |
| Workflow step | `aws-actions/configure-aws-credentials` | `azure/login` | `google-github-actions/auth` |
| Values stored in GitHub | Role ARN (a variable) | Client, tenant and subscription IDs (variables) | Provider name and service account (variables) |

## 6. Plan and apply identities

Use **two identities per environment**:

- a **plan** identity with **read-only** access (it can see everything Terraform needs to compare, and change nothing), trusted for **pull requests** and `main` (subjects ending `:pull_request` and `:ref:refs/heads/main`), because the plan and nightly drift jobs also run on `main`;
- an **apply** identity with write access, trusted **only** for the protected environment (subject ending `:environment:dev-aws`), which requires an approval (topic 8.4).

That way, a pull request (even a malicious one from a contributor) can never change the cloud: the worst it can do is read. The lab's `terraform.yml` uses `*_PLAN_*` and `*_APPLY_*` variables for exactly this.

## 7. Debugging "not authorized"

| Error | Usual cause |
| --- | --- |
| AWS: `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The `sub` in the trust policy doesn't match (name-based vs immutable format, wrong branch or environment, `pull_request` vs `ref:`); `aud` wrong; missing `id-token: write` |
| Azure: `AADSTS70021: No matching federated identity record found` | The federated credential's `subject` doesn't exactly match the token's `sub` |
| Google Cloud: `The given credential is rejected by the attribute condition` or `Permission 'iam.serviceAccounts.getAccessToken' denied` | Attribute condition doesn't match, or the `workloadIdentityUser` binding names a different principal set |
| Any: `Unable to get ACTIONS_ID_TOKEN_REQUEST_URL` | The job lacks `permissions: id-token: write` |

To see the exact claims, temporarily add a step that prints the token's `sub` (not the whole token) with the `actions/github-script` `core.getIDToken()` method and a JWT decode, then remove it.

## Practice

1. Set up keyless login to **all three** clouds for your repository from topic 8.1, each trusted only for one environment (`dev-aws`, `dev-azure`, `dev-gcp`).
2. Add a workflow with one job per cloud that runs a harmless read: `aws sts get-caller-identity`, `az account show`, `gcloud auth list`. Run it and save the output in your learning log.
3. Prove the restriction works: run the same job from another branch (without the environment) and read the error on each cloud.
4. Create the read-only plan identities for pull requests, and check that a plan works while an apply fails with "access denied".
5. Delete any cloud access keys you created in earlier topics for scripts or pipelines (AWS access keys, Azure client secrets, Google service account keys), and confirm in each console that none are left.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Securely deploy to AWS with GitHub Actions and OIDC](https://www.youtube.com/watch?v=Io5UFJlEJKc) · GitHub · 17 min. GitHub's own walk-through of keyless deployment to AWS with OIDC.
- [Connect to Azure from a GitHub Action with OpenID Connect (OIDC)](https://www.youtube.com/watch?v=IKuw9T6vZYU) · Jon Gallant · 8 min. Connecting a GitHub workflow to Azure with OIDC.
- [How to use Github Actions with Google's Workload Identity Federation](https://www.youtube.com/watch?v=ZgVhU5qvK1M) · Google Cloud Tech · 12 min. Google Cloud Tech on Workload Identity Federation for GitHub Actions.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Build and deploy applications to Azure by using GitHub Actions (includes signing in to Azure from a workflow)](https://learn.microsoft.com/training/modules/github-actions-cd/)

**AWS (AWS Skill Builder):**

- [Deep Dive with Security: AWS Identity and Access Management (IAM)](https://skillbuilder.aws/learn/525X5QYY33/deep-dive-with-security-aws-identity-and-access-management-iam/EJR97RFJZ3)

**Terraform (HashiCorp's free tutorials):**

- [Authenticate providers with dynamic credentials](https://developer.hashicorp.com/terraform/tutorials/cloud/dynamic-credentials)

