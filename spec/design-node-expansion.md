# LocalK8s Node Expansion Design

## Overview
This design extends LocalK8s from single-node to two-node operation by adding a remote k3s agent worker to the existing `laminarflow` server. It preserves current cluster stack choices (k3s, KubeRay, Ollama, Helmfile, Ansible) and adds a controlled join/remove automation path.

## Architecture
- Existing node (`laminarflow`):
  - remains k3s server/control-plane
  - remains orchestration control host for scripts + Ansible
- New remote node:
  - installed as k3s agent
  - optionally configured with NVIDIA runtime + device plugin compatibility
  - receives explicit labels/taints for workload placement control
- Existing cluster services:
  - KubeRay operator remains cluster-scoped
  - RayCluster and Ollama remain managed manifests/releases

## Proposed Repository Additions
- `packages/node-join/README.md`
- `packages/node-join/inventory.example.ini`
- `ansible/roles/k3s_agent/` (install/join/service/uninstall)
- `ansible/roles/node_gpu_runtime/` (worker GPU runtime preflight/setup)
- `scripts/join-node.sh` (entrypoint)
- `scripts/remove-node.sh` (entrypoint)

## Control Flow
1. Join preflight:
   - verify `laminarflow` cluster reachable
   - verify required multi-node connectivity (k3s API and CNI/data-plane paths)
   - obtain k3s server URL/token securely
   - validate remote host SSH/sudo access
2. Remote provisioning:
   - install k3s agent with `K3S_URL` and token
   - optional NVIDIA runtime setup on worker
   - apply labels/taints
3. Cluster post-checks:
   - wait for node `Ready`
   - verify labels/taints
   - verify optional `nvidia.com/gpu`
4. Workload placement validation:
   - run Ray/Ollama checks with worker-targeted selectors/affinity

## Scheduling Strategy
- Preserve current defaults for existing workloads unless explicit placement policy is configured.
- Introduce node labels such as:
  - `localk8s.io/worker-class=gpu-secondary`
  - `localk8s.io/accelerator=tesla-m10`
- Use Ray worker group affinity/selectors when directing small-model workloads to Tesla M10 node.
- Keep Ollama placement configurable (sticky on primary by default; opt-in migration to secondary).

## Ollama Storage Locality Policy
- Default behavior: Ollama remains pinned to the primary node where model PVC/storage is declared.
- Node expansion shall not implicitly move Ollama to secondary worker nodes.
- Any Ollama relocation requires an explicit migration workflow:
  1. provision destination storage
  2. synchronize model data
  3. update scheduling constraints
  4. validate endpoint health and rollback path

## Idempotency and Ownership
- Join script is converge-style:
  - if agent already installed and joined, verify and exit cleanly.
- Remote host ownership registry:
  - maintain a machine-local registry at a fixed path (for example `/var/lib/localk8s/node-join-owned-artifacts.yaml`)
  - record only artifacts created/managed by node-join automation
  - consume this registry during uninstall to constrain cleanup scope
- Remove script is safe-by-default:
  - requires explicit target node
  - refuses control-plane node removal unless explicit override flag is set
  - drains before deletion
  - uninstalls only components owned by node-join automation.

## Failure Modes
- API unreachable:
  - fail preflight with network diagnostics.
- Invalid token:
  - fail join and do not continue with partial config.
- GPU runtime mismatch:
  - fail GPU checks explicitly and stop GPU-enable path with remediation guidance.
- Drain blocked:
  - stop removal and emit unblock procedure.
- Preflight network ports unavailable:
  - fail before join with explicit connectivity diagnostics and retry guidance.
- Token/log leakage risk:
  - enforce redaction in script logging helpers and verify with dedicated tests.

## Network Preflight Baseline
- Validate control-plane reachability to k3s API (`6443/tcp`).
- Validate node-to-node cluster data-plane connectivity required by chosen CNI mode (for current defaults, include flannel VXLAN path checks).
- Validate host firewall policy does not block required cluster node traffic.

## Compatibility Decision
- k3s is fully compatible with this expansion pattern via agent joins.
- No kubeadm migration is required for two-node baseline objectives.

## Verification Strategy
- Node lifecycle:
  - join -> ready -> label check -> remove -> absent
- GPU lifecycle:
  - worker allocatable check + CUDA pod check
- Workload lifecycle:
  - Ray job scheduled to worker with success
  - Ollama endpoint remains healthy
- Rerun behavior:
  - repeated join/remove operations produce stable, non-destructive outcomes.
