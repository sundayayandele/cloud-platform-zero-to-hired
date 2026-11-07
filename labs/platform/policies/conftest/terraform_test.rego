package main

import rego.v1

test_aws_ssh_from_anywhere_is_denied if {
	count(deny) == 1 with input as {"resource": {"aws_vpc_security_group_ingress_rule": {"ssh": [
		{"cidr_ipv4": "0.0.0.0/0", "from_port": 22, "to_port": 22},
	]}}}
}

test_aws_https_from_anywhere_is_allowed if {
	count(deny) == 0 with input as {"resource": {"aws_vpc_security_group_ingress_rule": {"https": [
		{"cidr_ipv4": "0.0.0.0/0", "from_port": 443, "to_port": 443},
	]}}}
}

test_aws_port_range_covering_ssh_is_denied if {
	count(deny) == 1 with input as {"resource": {"aws_vpc_security_group_ingress_rule": {"wide": [
		{"cidr_ipv4": "0.0.0.0/0", "from_port": 0, "to_port": 1024},
	]}}}
}

test_azure_rdp_from_internet_is_denied if {
	count(deny) == 1 with input as {"resource": {"azurerm_network_security_group": {"app": [{"tags": {}, "security_rule": [
		{"name": "rdp", "access": "Allow", "direction": "Inbound", "source_address_prefix": "Internet", "destination_port_range": "3389"},
	]}]}}}
}

test_gcp_ssh_from_iap_only_is_allowed if {
	count(deny) == 0 with input as {"resource": {"google_compute_firewall": {"iap_ssh": [
		{"source_ranges": ["35.235.240.0/20"], "allow": [{"protocol": "tcp", "ports": ["22"]}]},
	]}}}
}

test_gcp_ssh_from_anywhere_is_denied if {
	count(deny) == 1 with input as {"resource": {"google_compute_firewall": {"ssh": [
		{"source_ranges": ["0.0.0.0/0"], "allow": [{"protocol": "tcp", "ports": ["22"]}]},
	]}}}
}

test_untagged_vpc_is_denied if {
	count(deny) == 1 with input as {"resource": {"aws_vpc": {"this": [{"cidr_block": "10.20.0.0/16"}]}}}
}
