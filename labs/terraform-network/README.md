# Terraform network lab (Module 7)

ITL Pay's three-tier network (topic 6.4) as Terraform, on both clouds, with **matching module interfaces**: the same
inputs (`name`, `cidr`, `nat_gateway`, `tags`) and the same main outputs (`network_id`, `public_subnet_ids`,
`app_subnet_ids`, `data_subnet_ids`, `security_group_ids`).

```text
modules/aws-network     VPC, public/app/data subnets in two AZs, IGW, optional NAT gateway, route tables, security groups
modules/azure-network   VNet, public/app/data + AzureBastionSubnet + appgw subnets, optional NAT gateway, NSGs + ASGs
envs/dev-aws            uses modules/aws-network in af-south-1
envs/dev-azure          uses modules/azure-network in South Africa North
```

```bash
cd envs/dev-aws
terraform init
terraform plan -var owner=ada -out=tfplan
terraform apply tfplan
terraform destroy -var owner=ada          # always, at the end of the session
```

On Azure, also pass `-var subscription_id=$(az account show --query id -o tsv)`.

`nat_gateway` is off in the dev environments because NAT gateways bill every hour; switch it on only when the app tier
needs outbound access. Checked with `terraform fmt -check` and `terraform validate` (Terraform 1.11, AWS provider 6.x,
azurerm 4.x).
