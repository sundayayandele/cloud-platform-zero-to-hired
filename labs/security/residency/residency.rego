# Topic 15.2: data residency as code. ITL Pay's customer data may only live in the agreed regions: South Africa
# (the closest in-Africa regions of all three clouds) and, for disaster recovery, one EU region with an adequacy basis.
#   conftest test --parser hcl2 -p labs/security/residency labs/terraform-network/envs/*/main.tf
#   conftest verify -p labs/security/residency
package main

import rego.v1

allowed := {
	"af-south-1", "eu-west-1", # AWS: Cape Town, Ireland
	"southafricanorth", "westeurope", # Azure: Johannesburg, Netherlands
	"africa-south1", "europe-west1", # Google Cloud: Johannesburg, Belgium
}

# A region or location variable whose default is somewhere else
deny contains msg if {
	some name in {"region", "location"}
	some v in input.variable[name]
	not v.default in allowed
	msg := sprintf("variable %q defaults to %q, outside the agreed regions %v (topic 15.2)", [name, v.default, sort(allowed)])
}

# A region or location written directly into a provider or resource
deny contains msg if {
	some kind in {"provider", "resource"}
	some type, entries in input[kind]
	some block in blocks_of(entries)
	some attribute in {"region", "location"}
	value := block[attribute]
	is_string(value)
	not startswith(value, "${")
	not value in allowed
	msg := sprintf("%s %s sets %s = %q, outside the agreed regions (topic 15.2)", [kind, type, attribute, value])
}

# providers are a list of blocks; resources are a map of names to lists of blocks
blocks_of(entries) := entries if is_array(entries)

blocks_of(entries) := [b | some _, list in entries; some b in list] if is_object(entries)
