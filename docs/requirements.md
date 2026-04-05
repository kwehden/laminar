# LocalK8s GPU Ray Platform Requirements

## 1. Objective
Build a single-host platform for concurrent GPU workloads using k3s + NVIDIA + KubeRay with low operational overhead.

## 2. In Scope
- Single-node k3s cluster on one Linux host.
- NVIDIA GPU support for containers and Kubernetes scheduling.
- One KubeRay operator deployment.
- One RayCluster with CPU-only head and GPU worker pods.
- GPU sharing via NVIDIA time-slicing as default.
- Bootstrap and healthcheck scripts for repeatable setup.

## 3. Out of Scope (Phase 1)
- Multi-node Kubernetes.
- Multi-tenant security hardening.
- Production-grade external auth, SSO, or service mesh.
- MIG-based partitioning unless hardware support and isolation needs are confirmed.

## 4. Host Prerequisites
- Linux host with supported NVIDIA GPU and driver.
- Container runtime integration via `nvidia-container-toolkit`.
- Sufficient CPU, memory, and disk for Ray object spilling and logs.
- Network access to fetch k3s, Helm charts, and container images.

## 5. Functional Requirements
- FR1: Node must advertise allocatable `nvidia.com/gpu` resources.
- FR2: CUDA test pod must successfully run `nvidia-smi`.
- FR3: Ray head pod runs without GPU requests.
- FR4: Ray worker group requests/limits GPU resources and can execute GPU tasks.
- FR5: Multiple Ray tasks/actors run concurrently via time-slicing.
- FR6: Setup is reproducible via bootstrap automation.
- FR7: Healthcheck script reports cluster, GPU, and Ray status.

## 6. Non-Functional Requirements
- NFR1: Version pinning for k3s, NVIDIA components, and KubeRay.
- NFR2: Initial deployment should be recoverable without manual host surgery.
- NFR3: Resource guardrails prevent accidental host exhaustion.
- NFR4: Architecture should remain simple for one primary user.

## 7. Success Criteria
- End-to-end validation succeeds for 1, 2, and N concurrent GPU jobs.
- No manual runtime reconfiguration required between workload runs.
- Measurable tuning guidance exists for time-slice replica count and Ray concurrency.

## 8. Acceptance Artifacts
- `scripts/bootstrap.sh`
- `scripts/healthcheck.sh`
- Kubernetes manifests/Helm values for NVIDIA plugin and RayCluster.
- Runbook documenting validation commands and expected outputs.
