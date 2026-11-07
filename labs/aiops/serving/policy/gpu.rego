# Topic 17.2: rules for GPU workloads, checked before they reach a cluster:
#   conftest test -p policy vllm.yaml        conftest verify -p policy   (the tests in gpu_test.rego)
# GPUs are the most expensive nodes you'll run, so the rules protect both reliability and the bill.
package main

import rego.v1

workload_kinds := {"Deployment", "StatefulSet", "Job", "DaemonSet"}

pod_spec := input.spec.template.spec if input.kind in workload_kinds

pod_spec := input.spec if input.kind == "Pod"

containers contains c if some c in pod_spec.containers

gpus(c) := object.get(c, ["resources", "limits", "nvidia.com/gpu"], null)

gpu_request(c) := object.get(c, ["resources", "requests", "nvidia.com/gpu"], null)

uses_gpu if {
	some c in containers
	gpus(c) != null
}

uses_gpu if {
	some c in containers
	gpu_request(c) != null
}

tolerates_gpu if {
	some t in pod_spec.tolerations
	t.key == "nvidia.com/gpu"
}

name := sprintf("%s/%s", [input.kind, input.metadata.name])

deny contains msg if {
	some c in containers
	gpu_request(c) != null
	gpus(c) == null
	msg := sprintf("%s: container %s requests a GPU without a GPU limit; set limits.nvidia.com/gpu", [name, c.name])
}

deny contains msg if {
	uses_gpu
	not tolerates_gpu
	msg := sprintf("%s uses a GPU but doesn't tolerate the nvidia.com/gpu taint, so it can't schedule on GPU nodes", [name])
}

deny contains msg if {
	uses_gpu
	object.get(pod_spec, ["nodeSelector", "platform.itlearning.tech/pool"], "") != "gpu"
	msg := sprintf("%s uses a GPU but has no nodeSelector platform.itlearning.tech/pool: gpu", [name])
}

deny contains msg if {
	not uses_gpu
	tolerates_gpu
	msg := sprintf("%s tolerates the GPU taint without using a GPU: it would take expensive GPU nodes", [name])
}

deny contains msg if {
	some c in containers
	gpus(c) != null
	not object.get(c, ["resources", "limits", "memory"], null)
	msg := sprintf("%s: container %s has no memory limit", [name, c.name])
}

deny contains msg if {
	uses_gpu
	some c in containers
	not c.readinessProbe
	msg := sprintf("%s: container %s has no readinessProbe; a model takes minutes to load", [name, c.name])
}

deny contains msg if {
	some c in containers
	not contains(c.image, ":")
	msg := sprintf("%s: container %s image has no tag", [name, c.name])
}

deny contains msg if {
	some c in containers
	endswith(c.image, ":latest")
	msg := sprintf("%s: container %s uses :latest", [name, c.name])
}

deny contains msg if {
	some c in containers
	some e in c.env
	regex.match(`(?i)(KEY|TOKEN|SECRET|PASSWORD)`, e.name)
	e.value
	msg := sprintf("%s: env %s holds a literal secret; use valueFrom.secretKeyRef or workload identity", [name, e.name])
}
