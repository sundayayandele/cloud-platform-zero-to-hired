# The same output names as modules/aws-network, so environments can use either cloud the same way.

output "network_id" {
  description = "The VNet ID"
  value       = azurerm_virtual_network.this.id
}

output "public_subnet_ids" {
  description = "The public subnet (Azure subnets span zones, so there is one)"
  value       = [azurerm_subnet.public.id]
}

output "app_subnet_ids" {
  description = "The app subnet"
  value       = [azurerm_subnet.app.id]
}

output "data_subnet_ids" {
  description = "The data subnet (delegated to PostgreSQL Flexible Server)"
  value       = [azurerm_subnet.data.id]
}

output "security_group_ids" {
  description = "The app tier's application security group and the NSGs on the app and data subnets"
  value = {
    app      = azurerm_application_security_group.app.id
    nsg_app  = azurerm_network_security_group.app.id
    nsg_data = azurerm_network_security_group.data.id
  }
}

output "appgw_subnet_id" {
  description = "Subnet for the Application Gateway (topic 6.8)"
  value       = azurerm_subnet.appgw.id
}

output "bastion_subnet_id" {
  description = "AzureBastionSubnet (topic 6.5)"
  value       = azurerm_subnet.bastion.id
}
