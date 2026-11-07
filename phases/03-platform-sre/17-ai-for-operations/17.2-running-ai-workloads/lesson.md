## What you will be able to do

- Run GPU workloads on Kubernetes: GPU node pools, drivers and device plugins, taints and tolerations, on EKS, AKS and GKE.
- Serve an open model with vLLM, and know what makes model serving different: size, start-up time, GPU memory and cost.
- Operate the managed model services (Amazon Bedrock, Azure OpenAI in Microsoft Foundry, Vertex AI): quotas, throughput, regions, private networking, identity, logging and cost.
- Choose between a managed model API and self-hosting, and defend the choice.
- Enforce rules for GPU workloads with policy as code.

## Why this matters at work

Product teams now ship features built on large language models, and someone has to run them: get GPU capacity, keep the models up, stop the bill from exploding, and keep customer data where it must stay. That's increasingly the platform team's job, and "MLOps" or "AI platform engineer" roles ask for exactly the Kubernetes, cloud and FinOps skills you already have, applied to GPUs and model APIs.

## 1. GPUs on Kubernetes

Pods ask for GPUs like CPU and memory, as an **extended resource** provided by a device plugin:

```yaml
resources:
  limits:
    nvidia.com/gpu: "1"          # whole GPUs; GPUs aren't overcommitted
```

| | EKS | AKS | GKE |
| --- | --- | --- | --- |
| GPU nodes | A managed node group (or Karpenter NodePool) with GPU instance types and the EKS-optimised accelerated AMI | A GPU node pool (`az aks nodepool add` with a GPU VM size) | A node pool with an accelerator type (`--accelerator type=...,gpu-driver-version=default`) |
| Drivers and device plugin | NVIDIA device plugin, or the NVIDIA GPU Operator | AKS installs the driver by default, or use the GPU Operator | GKE installs the driver when you ask for it |
| Keeping other pods off | Add a taint such as `nvidia.com/gpu:NoSchedule` | Add a taint when you create the pool | GKE taints GPU nodes `nvidia.com/gpu=present:NoSchedule` |

Scale GPU pools **from zero**: GPU nodes are the most expensive you'll run, so let the cluster autoscaler (or Karpenter, or GKE's node auto-provisioning) add them only when a GPU pod is waiting. Check your quota first: new accounts often have a GPU quota of zero, and GPUs are scarce in some regions, including African ones, so you may need a nearby region.

**Policy for GPU workloads.** `labs/aiops/serving/policy/gpu.rego` (Conftest, topic 14.3) checks, before anything is applied, that a GPU workload has a GPU limit, tolerates the GPU taint, selects the GPU pool, has a memory limit and a readiness probe, uses a pinned image, and keeps tokens in Secrets. It also refuses CPU workloads that tolerate the GPU taint, because they'd fill expensive nodes. The course's CI runs its tests and checks the vLLM manifest against it.

## 2. Serving a model: vLLM

`labs/aiops/serving/vllm.yaml` serves an open model (Qwen2.5 1.5B Instruct, small enough for one GPU) with **vLLM**, which exposes an OpenAI-compatible API inside the cluster. What's different from ITL Pay:

| | A web API | A model server |
| --- | --- | --- |
| Image and data size | Megabytes | Gigabytes of image, plus model weights (gigabytes to hundreds of gigabytes) |
| Start-up | Seconds | Minutes: download weights, load them into GPU memory. Use a `startupProbe`, cache weights on a volume |
| Bottleneck | CPU, database | GPU memory: the weights plus the KV cache for every request in flight |
| Scaling signal | CPU, requests per second | Requests waiting, tokens per second, time to first token |
| Rollout | Rolling update | Often `Recreate` (one GPU each), or a second pool for canaries (topic 12.2) |
| Cost | Cents per hour | Dollars per GPU-hour, every hour it runs |

Watch it like any service (Module 11): vLLM exposes Prometheus metrics, including requests running and waiting, and token throughput. Useful SLOs (topic 13.1) are **time to first token** and **tokens per second** at a percentile, and the error rate.

For more than one model, look at **KServe** (open-source model serving on Kubernetes) and autoscaling on queue length with **KEDA**.

## 3. The managed model services

Most teams start with a model API rather than GPUs. From an operations view:

| | Amazon Bedrock | Azure OpenAI in Microsoft Foundry | Google Cloud Vertex AI |
| --- | --- | --- | --- |
| Models | Many providers' models, including Anthropic's Claude, Amazon Nova, Meta Llama | OpenAI models, and other providers' models in Foundry, including Claude | Gemini, and partner models in Model Garden, including Claude |
| Capacity | On-demand quotas per model and region; provisioned throughput | Tokens-per-minute quotas per deployment; provisioned throughput units | Quotas per model and region; provisioned throughput |
| Private access | VPC interface endpoint (PrivateLink) | Private endpoint | Private Service Connect |
| Identity | IAM roles and policies | Microsoft Entra ID and Azure RBAC (avoid API keys) | IAM service accounts and workload identity |
| Logging | Model invocation logging, CloudTrail | Diagnostic settings, Azure Monitor | Cloud Logging, Cloud Audit Logs |
| Guardrails | Bedrock Guardrails | Content filters | Safety settings, Model Armor |

What operations teams own, whichever you use:

1. **Quotas and rate limits**: model APIs throttle (HTTP 429). Retry with backoff, queue requests, request quota increases early, and spread across regions or models where your data rules allow.
2. **Regions and data residency** (topic 15.2): check which models are available in which regions, and whether a "global" or "cross-region" option sends data to other countries. For South African or Nigerian personal data that matters.
3. **Identity, not keys**: workload identity (topic 9.5) instead of API keys in environment variables.
4. **Cost**: you pay per token, for input and output, at prices that differ by model by a factor of ten or more. Track cost per request and per feature (topic 16.1), set budgets, cache repeated prompts, and use the smallest model that passes your evaluation.
5. **Observability**: log requests' token counts, latency, errors and model version (not the prompts' personal data), and alert on error rate and throttling.

## 4. Managed API or self-host?

| Choose a managed API when | Self-host on GPUs when |
| --- | --- |
| You want the strongest models, which are often only available as APIs | An open model passes your evaluation |
| Usage is spiky or still small | Usage is high and steady enough to keep GPUs busy |
| You don't want to run GPUs | You must keep data on infrastructure you control, or run where no API region exists |
| | You need a fine-tuned model or very low latency at the edge |

Compare them with a cost model like topic 16.2's: tokens per month × price, against GPU-hours × price at your expected use. GPUs that sit idle half the day make self-hosting expensive.

## Practice

1. Run `conftest verify -p policy` and `conftest test -p policy vllm.yaml` in `labs/aiops/serving`. Break the manifest three ways (remove the toleration, use `:latest`, put a token in `env`) and read each denial.
2. On one cloud, check your GPU quota for one region in Africa and one in Europe, and list which GPU types are available. Request an increase if you'll do exercise 3.
3. (Costs money: delete everything the same day.) Create a GPU node pool that scales from zero, apply `vllm.yaml`, and measure time to first token and tokens per second with a short script. Then scale to zero and record what the hour cost.
4. Call a model on one managed service from a pod using workload identity (no API key), through a private endpoint. Turn on invocation logging and find your request.
5. For an "AI assistant for ITL Pay customers" feature, estimate monthly cost with a managed API and with self-hosting at 10,000 and 1,000,000 conversations a month, and write the ADR (topic 16.2).

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [NVIDIA GPU Operator: Simplifying GPU Management in Kubernetes - Kevin Jones (NVIDIA)](https://www.youtube.com/watch?v=zyX9VarIAJk) · OpenShift · 15 min. NVIDIA on drivers, the device plugin and the GPU Operator in Kubernetes.
- [vLLM Explained: Why It Serves LLMs 2–4× Faster on the Same GPU](https://www.youtube.com/watch?v=QeB_dR5u_ak) · AI WITH Rithesh · 12 min. Why vLLM uses GPU memory efficiently (the KV cache).
- [vLLM on Kubernetes in Production](https://www.youtube.com/watch?v=t0iJGEG0IXk) · Kubesimplify · 28 min. Running vLLM on Kubernetes.
- [Amazon Bedrock Explained 2026 | Production-Grade AI Engineering](https://www.youtube.com/watch?v=2zrty4OHg-I) · LearnITGuide Tutorials · 9 min. Amazon Bedrock for production applications.
- [Introducing Azure AI Foundry - Everything you need for AI development](https://www.youtube.com/watch?v=GD7MnIwAxYM) · Microsoft Mechanics · 13 min. Microsoft on Azure AI Foundry (now Microsoft Foundry).
- [Introduction to Vertex AI Model Garden](https://www.youtube.com/watch?v=I7UiSU96CLc) · Google Cloud Tech · 6 min. Google Cloud Tech on Vertex AI Model Garden.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Develop applications with Azure OpenAI in Foundry Models](https://learn.microsoft.com/training/modules/develop-applications-openai/)

**AWS (AWS Skill Builder):**

- [Amazon Bedrock Getting Started](https://skillbuilder.aws/learn/63KTRM86DQ/amazon-bedrock-getting-started/SC2Y3HMAUE)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Google Cloud AI Infrastructure (learning path: GPUs, TPUs and GKE)](https://www.skills.google/paths/2806)

