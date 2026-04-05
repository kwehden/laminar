# LocalK8s GPU Ray Platform Design

## 1. Architecture Summary
A single Linux host runs a single-node k3s cluster (control plane + worker). GPU scheduling is enabled through NVIDIA runtime integration and Kubernetes device plugin. KubeRay manages one RayCluster optimized for predictable local operation.

## 2. Logical Components
- Host OS + NVIDIA driver
- Container runtime + `nvidia-container-toolkit`
- k3s (embedded containerd)
- NVIDIA k8s-device-plugin (+ optional GPU feature discovery)
- KubeRay operator
- RayCluster (1 head group, 1+ worker groups)

## 3. Deployment Topology
- Node count: 1
- Namespace strategy:
  - `kuberay-system` for operator
  - `ray` for Ray workloads
- Storage:
  - Use local-path storage class for cluster-local persistence.
  - Reserve host paths for Ray logs/object spilling.

## 4. GPU Scheduling Design
- Configure runtime so GPU pods launch reliably on k3s/containerd.
- Install NVIDIA device plugin via Helm and publish `nvidia.com/gpu`.
- Start with time-slicing enabled and conservative replicas per physical GPU (for example `2`).
- MIG path is optional and only enabled when card capability and workload isolation requirements justify it.

## 5. RayCluster Design
- Head pod:
  - CPU-only
  - No GPU requests
  - Exposes dashboard/service for local access
- Worker pod group:
  - Requests/limits `nvidia.com/gpu`
  - Uses explicit Ray `num_gpus` per task/actor
  - Conservative autoscaling (or fixed replicas) for deterministic behavior

## 6. Guardrails and Operations
- Add namespace `LimitRange` and `ResourceQuota` to reduce accidental resource starvation.
- Keep ingress/auth simple for single-user mode (port-forward or local-only ingress).
- Pin versions in Helm values and scripts to avoid drift.
- Provide idempotent bootstrap + healthcheck scripts.

## 7. Validation Plan
- Infrastructure checks:
  - `kubectl get nodes -o wide`
  - `kubectl describe node <node> | rg -n "nvidia.com/gpu"`
- GPU runtime check:
  - CUDA test pod runs `nvidia-smi`
- Ray checks:
  - RayCluster reaches ready state
  - Concurrent GPU task benchmark at 1, 2, and N clients
- Tuning loop:
  - Adjust time-slice replicas and Ray concurrency from benchmark results.

## 8. Risks and Mitigations
- Driver/runtime mismatch: pin tested versions and validate with containerized `nvidia-smi` before installing KubeRay.
- Over-subscription instability: begin with low time-slice replicas and explicit `num_gpus`.
- Local disk pressure: pre-allocate and monitor spill/log paths.
