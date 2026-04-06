# Laminar GPU Ray Platform Context

## Problem Statement
The project needs a repeatable way to run concurrent GPU Ray workloads on a single host without manual reconfiguration between runs. Current state is design intent only; no executable platform assets exist yet.

## Goals (bullet list, measurable when possible)
- Stand up a single-node k3s cluster with working NVIDIA GPU scheduling.
- Run one KubeRay-managed RayCluster with CPU head and GPU workers.
- Enable GPU sharing via NVIDIA time-slicing and validate concurrent GPU task execution.
- Provide bootstrap automation plus credentials/helper scripts for k3s console access.
- Provide healthcheck automation for reproducible local checks.
- Ensure rerunning install converges to Day-0 desired state with no stale project-managed configuration.
- Produce a baseline benchmark at 1, 2, and 4 concurrent jobs for tuning.

## Non-Goals / Out of Scope
- Multi-node Kubernetes orchestration.
- Multi-tenant isolation and enterprise auth.
- Production ingress, service mesh, or internet-exposed control planes.
- MIG partitioning by default.

## Users & Use-Cases
- Primary user: one platform owner/operator on a single Linux workstation.
- Use-case 1: bootstrap the host and cluster from scratch.
- Use-case 2: deploy Ray and submit concurrent GPU workloads.
- Use-case 3: run healthchecks after host reboot or upgrades.
- Use-case 4: tune time-slice and Ray concurrency for stable throughput.

## Constraints & Invariants (include constitution items and platform constraints)
- Single host, single-node k3s topology is required for phase 1.
- NVIDIA driver and `nvidia-container-toolkit` must be host-compatible before Kubernetes GPU work.
- GPU sharing mode defaults to time-slicing; MIG is conditional.
- Keep architecture simple and operationally lightweight for one main user.
- Cleanup/removal operations must be limited to project-managed resources and managed host config paths.
- Host baseline for phase 1 implementation (captured on this machine):
  - OS: Ubuntu 26.04 (Resolute), kernel `7.0.0-10-generic`
  - CPU: AMD Ryzen 7 5700G, 16 logical CPUs
  - Memory: 61 GiB RAM
  - Disk: 146 GiB free on `/` (`/dev/nvme0n1p2`)
  - GPU: NVIDIA GeForce RTX 5060 Ti, 16311 MiB VRAM, driver `580.126.09` (CUDA 13.0)

## Success Metrics & Acceptance Criteria
- `nvidia.com/gpu` is visible as allocatable on the node.
- CUDA test pod successfully executes `nvidia-smi`.
- Ray head and GPU worker pods become ready.
- Concurrent GPU tasks succeed under 1, 2, and 4 job levels.
- Bootstrap and healthcheck scripts complete without interactive host debugging.
- Bootstrap output provides credentials/helper path for k3s console access (for example exported `KUBECONFIG` and/or helper command).
- Re-running bootstrap converges environment to the same Day-0 desired state and removes stale managed configuration from prior runs.

## Risks & Edge Cases
- Driver/toolkit/runtime mismatch blocks GPU pods.
- Over-aggressive time-slice replicas create unstable job latency.
- Local disk saturation from Ray object spilling/log growth.
- Kubernetes updates drift from pinned versions.

## Observability / Telemetry expectations
- Capture basic cluster readiness, allocatable GPU state, and pod health.
- Record benchmark throughput/latency at defined concurrency levels.
- Preserve healthcheck output suitable for troubleshooting regressions.

## Rollout & Backward Compatibility (if applicable)
- Rollout is single-host and staged: host GPU stack -> k3s -> NVIDIA plugin -> KubeRay -> Ray workload tests.
- Backward compatibility is managed via explicit version pinning and idempotent scripts.

## Open Questions (with owner and how to resolve)
- Should baseline support be limited to Ubuntu 26.04 first, or include adjacent Ubuntu LTS variants immediately? Owner: platform owner. Resolve during requirement prioritization.
- Is initial benchmark concurrency cap fixed at 4, or should it scale by GPU count when additional cards are present? Owner: platform owner. Resolve in Gate 2 requirements.
- Is remote dashboard access required or local-only acceptable? Owner: platform owner. Resolve during gate 3 design approval.

## Glossary (define overloaded terms)
- k3s: lightweight Kubernetes distribution using embedded containerd.
- KubeRay: Kubernetes operator managing Ray custom resources.
- RayCluster: Ray deployment resource containing head/worker groups.
- Time-slicing: sharing one physical GPU across multiple schedulable slices.
- MIG: Multi-Instance GPU hardware partitioning mode on supported NVIDIA cards.
