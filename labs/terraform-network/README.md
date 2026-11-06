# Terraform network lab (Module 7)

ITL Pay's three-tier network (topic 6.4) as Terraform, on all three clouds, with **matching module interfaces**: the same
inputs (`name`, `cidr`, `nat_gateway`, `tags`) and the same main outputs (`network_id`, `public_subnet_ids`,
`app_subnet_ids`, `data_subnet_ids`, `security_group_ids`).

```text
modules/aws-network     VPC, public/app/data subnets in two AZs, IGW, optional NAT gateway, route tables, security groups
modules/azure-network   VNet, public/app/data + AzureBastionSubnet + appgw subnets, optional NAT gateway, NSGs + ASGs
modules/gcp-network     Global VPC, regional public/app/data subnets with flow logs, optional Cloud NAT, firewall rules by network tag, private services access for Cloud SQL
envs/dev-aws            uses modules/aws-network in af-south-1
envs/dev-azure          uses modules/azure-network in South Africa North
envs/dev-gcp            uses modules/gcp-network in africa-south1 (Johannesburg)
```

```bash
cd envs/dev-aws
terraform init
terraform plan -var owner=ada -out=tfplan
terraform apply tfplan
terraform destroy -var owner=ada          # always, at the end of the session
```

On Azure, also pass `-var subscription_id=$(az account show --query id -o tsv)`. On Google Cloud, run `gcloud auth application-default login` first and pass `-var project_id=$(gcloud config get-value project)`.

`nat_gateway` is off in the dev environments because NAT gateways and Cloud NAT bill every hour; switch it on only when the app tier
needs outbound access. Checked with `terraform fmt -check` and `terraform validate` (Terraform 1.11, AWS provider 6.x,
azurerm 4.x, google 7.x), and checked by tflint and checkov.
