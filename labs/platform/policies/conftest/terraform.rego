# Topic 14.3: policy as code for Terraform, checked before anything reaches a plan or the cloud:
#   conftest test --parser hcl2 -p labs/platform/policies/conftest labs/terraform-network/modules/*/main.tf
#   conftest verify -p labs/platform/policies/conftest        (the unit tests in terraform_test.rego)
# Conftest turns each .tf file into JSON; every block becomes a list, so rules iterate with "some ... in".
package main

import rego.v1

admin_ports := {22, 3389}

open_to_internet(cidr) if cidr in {"0.0.0.0/0", "::/0", "*", "Internet"}

covers_admin_port(from, to) if {
	some port in admin_ports
	to_number(from) <= port
	port <= to_number(to)
}

# AWS: no SSH or RDP from anywhere
deny contains msg if {
	some name, rules in input.resource.aws_vpc_security_group_ingress_rule
	some r in rules
	open_to_internet(r.cidr_ipv4)
	covers_admin_port(r.from_port, r.to_port)
	msg := sprintf("aws_vpc_security_group_ingress_rule.%s opens SSH/RDP to the internet: use Session Manager (topic 6.5)", [name])
}

# Azure: no SSH or RDP from anywhere in a network security group
deny contains msg if {
	some name, groups in input.resource.azurerm_network_security_group
	some g in groups
	some rule in g.security_rule
	rule.access == "Allow"
	rule.direction == "Inbound"
	open_to_internet(rule.source_address_prefix)
	some port in admin_ports
	rule.destination_port_range == sprintf("%d", [port])
	msg := sprintf("azurerm_network_security_group.%s rule %s opens port %d to the internet: use Bastion (topic 6.5)", [name, rule.name, port])
}

# Google Cloud: no SSH or RDP from anywhere (IAP's range 35.235.240.0/20 is fine)
deny contains msg if {
	some name, firewalls in input.resource.google_compute_firewall
	some f in firewalls
	some cidr in f.source_ranges
	open_to_internet(cidr)
	some allow in f.allow
	some p in allow.ports
	to_number(p) in admin_ports
	msg := sprintf("google_compute_firewall.%s opens port %s to the internet: use IAP (topic 6.5)", [name, p])
}

# Tags for ownership and cost (Module 16) on the resources that cost money or matter for security
taggable := {"aws_vpc", "aws_subnet", "aws_security_group", "aws_nat_gateway", "aws_eip", "azurerm_virtual_network",
	"azurerm_network_security_group", "azurerm_nat_gateway", "azurerm_public_ip"}

deny contains msg if {
	some type in taggable
	some name, blocks in input.resource[type]
	some b in blocks
	not b.tags
	msg := sprintf("%s.%s has no tags: add the module's tags (owner, project, environment)", [type, name])
}
