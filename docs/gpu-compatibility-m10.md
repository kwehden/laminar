# Tesla M10 Compatibility Notes (Laminar)

## Purpose
Capture operational guardrails for adding a Tesla M10 worker to a mixed-GPU Laminar cluster.

## Practical Compatibility Guidance
- Treat Tesla M10 as a **legacy Maxwell-generation** GPU for planning and scheduling.
- Keep M10-targeted workloads on **CUDA 12.x-era images**.
- Avoid assuming CUDA 13 toolchain support for Maxwell-targeted builds.
- Use an NVIDIA driver branch that remains compatible with Maxwell in your environment (current Laminar baseline uses R580 on the control-plane host).

## Why This Matters
- Mixed GPU generations can coexist in one Kubernetes cluster, but workload images/toolchains must match each node's GPU capability envelope.
- A container image that works on newer GPUs can fail on M10 due to architecture/toolchain assumptions.

## Recommended Cluster Policy
- Label M10 node(s), for example:
  - `localk8s.io/accelerator=tesla-m10`
  - `localk8s.io/accelerator-gen=maxwell`
- Use `nodeSelector`/affinity in Ray/Ollama manifests for workloads that must run on M10-compatible nodes.
- Keep newer CUDA-heavy workloads pinned to newer GPUs.

## Source References
- CUDA Toolkit, Driver, and Architecture Matrix (NVIDIA):  
  https://docs.nvidia.com/datacenter/tesla/drivers/cuda-toolkit-driver-and-architecture-matrix.html
- Supported Drivers and CUDA Toolkit Versions (NVIDIA):  
  https://docs.nvidia.com/datacenter/tesla/drivers/supported-drivers-and-cuda-toolkit-versions.html

## Maintenance Note
Re-check NVIDIA matrices before major upgrades (driver branch, CUDA major version, or base container images).
