# A three-tier network on AWS: public, app and data subnets in each zone (the design from topic 6.4).
# Subnet sizes come from the VPC range: public /24s, app /20s, data /24s, the same layout on Azure.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  zones = slice(data.aws_availability_zones.available.names, 0, var.zone_count)
  # cidrsubnet(range, extra bits, number): for a /16, 8 extra bits gives /24s and 4 gives /20s
  public = [for i, z in local.zones : cidrsubnet(var.cidr, 8, i)]
  app    = [for i, z in local.zones : cidrsubnet(var.cidr, 4, i + 1)]
  data   = [for i, z in local.zones : cidrsubnet(var.cidr, 8, 48 + i)]
  tags   = merge(var.tags, { module = "aws-network" })
}

resource "aws_vpc" "this" {
  # checkov:skip=CKV2_AWS_11: flow logs are left to the caller (topic 7.4 exercise: add them as an option)
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "${var.name}-vpc" })
}

# The VPC's default security group allows traffic between its members; take every rule away so nothing uses it by accident
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-default-unused" })
}

resource "aws_subnet" "public" {
  count             = var.zone_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.public[count.index]
  availability_zone = local.zones[count.index]
  tags              = merge(local.tags, { Name = "${var.name}-public-${count.index}", tier = "public" })
}

resource "aws_subnet" "app" {
  count             = var.zone_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.app[count.index]
  availability_zone = local.zones[count.index]
  tags              = merge(local.tags, { Name = "${var.name}-app-${count.index}", tier = "app" })
}

resource "aws_subnet" "data" {
  count             = var.zone_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.data[count.index]
  availability_zone = local.zones[count.index]
  tags              = merge(local.tags, { Name = "${var.name}-data-${count.index}", tier = "data" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(local.tags, { Name = "${var.name}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count          = var.zone_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  # checkov:skip=CKV2_AWS_19: this address belongs to the NAT gateway, not an instance
  count  = var.nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.name}-nat-ip" })
}

resource "aws_nat_gateway" "this" {
  count         = var.nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(local.tags, { Name = "${var.name}-nat" })
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id
  dynamic "route" {
    for_each = var.nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[0].id
    }
  }
  tags = merge(local.tags, { Name = "${var.name}-rt-app" })
}

resource "aws_route_table_association" "app" {
  count          = var.zone_count
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

# The data subnets keep the VPC's main route table (local route only): no internet at all.

resource "aws_security_group" "lb" {
  # checkov:skip=CKV2_AWS_5: attached by the caller (load balancer, instances, database) using the module's outputs
  name        = "${var.name}-sg-lb"
  description = "Load balancer: HTTPS from the internet"
  vpc_id      = aws_vpc.this.id
  tags        = local.tags
}

resource "aws_security_group" "app" {
  # checkov:skip=CKV2_AWS_5: attached by the caller (load balancer, instances, database) using the module's outputs
  name        = "${var.name}-sg-app"
  description = "App servers: 8080 from the load balancer"
  vpc_id      = aws_vpc.this.id
  tags        = local.tags
}

resource "aws_security_group" "db" {
  # checkov:skip=CKV2_AWS_5: attached by the caller (load balancer, instances, database) using the module's outputs
  name        = "${var.name}-sg-db"
  description = "Database: 5432 from the app servers"
  vpc_id      = aws_vpc.this.id
  tags        = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "lb_https" {
  security_group_id = aws_security_group.lb.id
  description       = "HTTPS from anywhere"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "lb_to_app" {
  security_group_id            = aws_security_group.lb.id
  description                  = "To the app servers"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_lb" {
  security_group_id            = aws_security_group.app.id
  description                  = "8080 from the load balancer"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.lb.id
}

resource "aws_vpc_security_group_egress_rule" "app_out" {
  security_group_id = aws_security_group.app.id
  description       = "Outbound: updates, registry, AWS APIs (through the NAT gateway) and the database"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "5432 from the app servers"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}
