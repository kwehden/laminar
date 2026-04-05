# LocalK8s Node Expansion Context

## Problem Statement
The current platform is a single-node k3s cluster on `laminarflow`. We need a repeatable way to attach a second machine on the LAN as a cluster worker, including GPU enablement, while preserving current KubeRay and Ollama functionality.

## Goals
- Add one remote worker node to the existing k3s cluster without rebuilding control plane.
- Keep k3s as the cluster distribution for this phase.
- Support GPU scheduling on the new worker (Tesla M10, late model) for small-to-medium Ray workloads.
- Keep both KubeRay and Ollama as supported in-cluster workloads after expansion.
- Preserve Day-0 idempotent reconciliation and managed-ownership cleanup patterns.

## Non-Goals
- Migrating from k3s to kubeadm/mainline Kubernetes in this phase.
- Multi-control-plane HA.
- Multi-tenant policy/enterprise auth hardening.
- Large-LLM optimization on the Tesla M10 class GPU.

## Users & Use Cases
- Primary user: single operator managing a local LAN lab.
- Use case 1: join a remote node to the existing cluster with one command entrypoint.
- Use case 2: validate worker node and GPU readiness for Ray/Ollama placement.
- Use case 3: remove/drain the worker node cleanly if hardware changes.

## Constraints & Invariants
- Existing `laminarflow` k3s server is reachable on the LAN during join flow.
- Join must use secure k3s server token flow; no tokens committed to repo.
- Existing cluster workloads must remain available during node-join operations.
- Automation must remain idempotent and converge managed state on rerun.
- Node removal workflow must protect the control-plane node by default.
- Ollama model storage remains primary-node-local by default; no implicit storage migration is allowed during node join.
- Node expansion preflight must verify not only k3s API reachability but also required node-to-node networking for the cluster data plane.
- Tesla M10 is treated as a workload-fit GPU for smaller jobs; scheduling policy must avoid assumptions suitable only for large LLM inference.

## Success Criteria
- New worker appears `Ready` in `kubectl get nodes`.
- If GPU runtime role is enabled, worker reports allocatable `nvidia.com/gpu`.
- KubeRay workloads can be scheduled to the worker via labels/affinity and run successfully.
- Ollama remains reachable and functional after expansion.
- Join/remove scripts can be rerun safely without manual host surgery.

## Risks
- LAN reachability/firewall issues to k3s API (`6443`) block join.
- NVIDIA runtime mismatch on worker prevents GPU advertising.
- Poor scheduling constraints cause contention with existing workloads.
- Token handling mistakes create operational/security risk.

## Decision Outcome (from concept gate)
- Continue with k3s and add agent-node workflow.
- Revisit kubeadm only if control-plane HA or strict upstream parity becomes mandatory.
