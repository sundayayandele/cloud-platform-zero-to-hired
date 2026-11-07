package main

import rego.v1

gpu_container := {
	"name": "vllm", "image": "vllm/vllm-openai:v0.32.0",
	"resources": {"requests": {"nvidia.com/gpu": "1"}, "limits": {"nvidia.com/gpu": "1", "memory": "16Gi"}},
	"readinessProbe": {"httpGet": {"path": "/health", "port": 8000}},
}

deployment(spec) := {"kind": "Deployment", "metadata": {"name": "vllm"}, "spec": {"template": {"spec": spec}}}

good_spec := {
	"nodeSelector": {"platform.itlearning.tech/pool": "gpu"},
	"tolerations": [{"key": "nvidia.com/gpu", "operator": "Exists", "effect": "NoSchedule"}],
	"containers": [gpu_container],
}

test_good_gpu_deployment_passes if {
	count(deny) == 0 with input as deployment(good_spec)
}

test_missing_toleration_is_denied if {
	count(deny) == 1 with input as deployment(object.remove(good_spec, ["tolerations"]))
}

test_missing_node_selector_is_denied if {
	count(deny) == 1 with input as deployment(object.remove(good_spec, ["nodeSelector"]))
}

test_gpu_request_without_limit_is_denied if {
	c := object.union(object.remove(gpu_container, ["resources"]), {"resources": {"requests": {"nvidia.com/gpu": "1"}, "limits": {"memory": "1Gi"}}})
	some msg in deny with input as deployment(object.union(good_spec, {"containers": [c]}))
	contains(msg, "without a GPU limit")
}

test_no_readiness_probe_is_denied if {
	c := object.remove(gpu_container, ["readinessProbe"])
	count(deny) == 1 with input as deployment(object.union(good_spec, {"containers": [c]}))
}

test_cpu_workload_tolerating_gpu_taint_is_denied if {
	c := {"name": "web", "image": "nginx:1.29", "resources": {"limits": {"memory": "1Gi"}}}
	spec := {"tolerations": good_spec.tolerations, "containers": [c]}
	count(deny) == 1 with input as deployment(spec)
}

test_cpu_workload_without_gpu_rules_passes if {
	c := {"name": "web", "image": "nginx:1.29"}
	count(deny) == 0 with input as deployment({"containers": [c]})
}

test_latest_image_is_denied if {
	c := object.union(gpu_container, {"image": "vllm/vllm-openai:latest"})
	count(deny) == 1 with input as deployment(object.union(good_spec, {"containers": [c]}))
}

test_literal_api_key_is_denied if {
	c := object.union(gpu_container, {"env": [{"name": "HF_TOKEN", "value": "hf_abc"}]})
	count(deny) == 1 with input as deployment(object.union(good_spec, {"containers": [c]}))
}

test_api_key_from_secret_passes if {
	c := object.union(gpu_container, {"env": [{"name": "HF_TOKEN", "valueFrom": {"secretKeyRef": {"name": "hf", "key": "token"}}}]})
	count(deny) == 0 with input as deployment(object.union(good_spec, {"containers": [c]}))
}
