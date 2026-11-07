package main

import rego.v1

test_cape_town_is_allowed if {
	count(deny) == 0 with input as {"variable": {"region": [{"default": "af-south-1"}]}}
}

test_us_east_is_denied if {
	count(deny) == 1 with input as {"variable": {"region": [{"default": "us-east-1"}]}}
}

test_literal_location_in_a_resource_is_checked if {
	count(deny) == 1 with input as {"resource": {"azurerm_resource_group": {"rg": [{"location": "eastus"}]}}}
}

test_variable_references_are_left_to_the_variable_rule if {
	count(deny) == 0 with input as {"provider": {"aws": [{"region": "${var.region}"}]}}
}

test_literal_provider_region_outside_is_denied if {
	count(deny) == 1 with input as {"provider": {"google": [{"region": "us-central1"}]}}
}
