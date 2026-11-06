# A three-tier network on Azure: the same design as modules/aws-network, the Azure way (topic 6.4).
# Azure subnets span the region's zones, so there is one subnet per tier; zones are chosen per resource.

locals {
  public  = cidrsubnet(var.cidr, 7, 0)  # /23 for a /16: 10.30.0.0/23
  bastion = cidrsubnet(var.cidr, 10, 8) # /26: 10.30.2.0/26 (AzureBastionSubnet needs at least /26)
  appgw   = cidrsubnet(var.cidr, 8, 4)  # /24: 10.30.4.0/24 (Application Gateway needs its own subnet)
  app     = cidrsubnet(var.cidr, 4, 1)  # /20: 10.30.16.0/20
  data    = cidrsubnet(var.cidr, 7, 24) # /23: 10.30.48.0/23
  tags    = merge(var.tags, { module = "azure-network" })
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "public" {
  name                            = "public"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [local.public]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "bastion" {
  # checkov:skip=CKV2_AZURE_31: Azure Bastion needs a specific set of NSG rules; add them only with Bastion (topic 6.5)
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.bastion]
}

resource "azurerm_subnet" "appgw" {
  # checkov:skip=CKV2_AZURE_31: Application Gateway v2 needs GatewayManager rules on its subnet's NSG; add them with the gateway (topic 6.8)
  name                 = "appgw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.appgw]
}

resource "azurerm_subnet" "app" {
  name                            = "app"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [local.app]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "data" {
  name                            = "data"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [local.data]
  default_outbound_access_enabled = false
  delegation {
    name = "postgres"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Private outbound for the app tier, made explicit
resource "azurerm_public_ip" "nat" {
  count               = var.nat_gateway ? 1 : 0
  name                = "${var.name}-nat-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "this" {
  count               = var.nat_gateway ? 1 : 0
  name                = "${var.name}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count                = var.nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "app" {
  count          = var.nat_gateway ? 1 : 0
  subnet_id      = azurerm_subnet.app.id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}

# "Members of this group" for security rules, like AWS security group references
resource "azurerm_application_security_group" "app" {
  name                = "${var.name}-asg-app"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_network_security_group" "app" {
  name                = "${var.name}-nsg-app"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                                       = "allow-appgw-8080"
    priority                                   = 100
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "8080"
    source_address_prefix                      = local.appgw
    destination_application_security_group_ids = [azurerm_application_security_group.app.id]
  }
}

resource "azurerm_network_security_group" "data" {
  name                = "${var.name}-nsg-data"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                                  = "allow-app-5432"
    priority                              = 100
    direction                             = "Inbound"
    access                                = "Allow"
    protocol                              = "Tcp"
    source_port_range                     = "*"
    destination_port_range                = "5432"
    source_application_security_group_ids = [azurerm_application_security_group.app.id]
    destination_address_prefix            = local.data
  }

  # The default AllowVnetInBound rule would let every subnet in: deny the rest of the VNet explicitly
  security_rule {
    name                       = "deny-rest-of-vnet"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-internet-out"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# Public subnet: HTTPS from the internet only
resource "azurerm_network_security_group" "public" {
  name                = "${var.name}-nsg-public"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "allow-https"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = local.public
  }
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.public.id
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.data.id
}
