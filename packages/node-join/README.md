# Node Join Package

This package defines the node-join baseline for adding remote worker nodes to an existing LocalK8s cluster.

Current scope:
- inventory contract
- secure token input contract
- network preflight contract
- ownership-registry contract
- worker validation handoff for CPU and GPU nodes

Initial script/role skeletons now exist in:
- `scripts/join-node.sh`
- `scripts/remove-node.sh`
- `ansible/roles/k3s_agent/tasks/main.yml`
- `ansible/roles/node_gpu_runtime/tasks/main.yml`
- `scripts/validate-cpu-worker.sh`
- `scripts/validate-gpu-worker.sh`

Current `NODE-TASK-002` behavior:
- installs/configures k3s agent on target host
- waits for node registration + `Ready` condition
- applies configured labels/taints via `kubectl`

Current `NODE-TASK-003` behavior:
- enables NVIDIA container toolkit on GPU-profile workers
- configures k3s-agent containerd runtime with `nvidia-ctk`
- verifies NVIDIA runtime wiring in k3s agent containerd config
- keeps uninstall mode non-destructive until ownership-registry-scoped cleanup is implemented

Worker validation helpers:
- `scripts/validate-cpu-worker.sh` checks CPU worker labels and canary scheduling.
- `scripts/validate-gpu-worker.sh` checks GPU worker labels and runs an ephemeral CUDA pod that executes `nvidia-smi`.

## Inventory Contract
Use [inventory.example.ini](./inventory.example.ini) as the template.

Required host-level fields:
- `ansible_host`
- `ansible_user`

Common optional fields:
- `localk8s_node_profile` (`cpu` or `gpu`, default `cpu`)
- `localk8s_gpu_enable` (`true`/`false`, legacy compatibility fallback; prefer `localk8s_node_profile`)
- `localk8s_node_name` (explicit Kubernetes node name override; defaults to remote `hostname -s`)
- `localk8s_node_labels` (comma-separated `key=value`, appended to profile defaults)
- `localk8s_node_taints` (comma-separated `key=value:Effect`)
- `localk8s_allow_control_plane_remove` (`false` by default)

Default labels by profile:
- `cpu`: `localk8s.io/worker-class=cpu`, `localk8s.io/ray-eligible=true`, `localk8s.io/ollama-eligible=false`
- `gpu`: `localk8s.io/worker-class=gpu`, `localk8s.io/ray-eligible=true`, `localk8s.io/ollama-eligible=true`

Reserved labels:
- `localk8s.io/worker-class`
- `localk8s.io/ray-eligible`
- `localk8s.io/ollama-eligible`

These are profile-managed and must not be set in `localk8s_node_labels`.

Required group-level fields (`[node_join_targets:vars]`):
- `localk8s_k3s_url` (example: `https://<control-plane-hostname>:6443`)
- `ansible_become=true`

Join workflow also consumes pinned `K3S_VERSION` from `config/versions.env` (or `K3S_VERSION` env override).

## Secure Token Input Pattern
Do not store tokens in tracked files.

Supported input order for future join/remove scripts:
1. `K3S_JOIN_TOKEN` environment variable.
2. Interactive prompt (silent input) when env var is not set.

Join script compatibility notes:
- `--gpu` remains supported and now forces `localk8s_node_profile=gpu`.
- Inventory `localk8s_node_profile=gpu` also enables GPU runtime installation by default.
- Recommended post-join validation for GPU workers: `./scripts/validate-gpu-worker.sh --node standpunkt --namespace ray --timeout 300s`

Logging requirements:
- never print raw token values
- mask token-bearing env vars in debug output

## Network Preflight Contract
See [network-preflight.md](./network-preflight.md).

At minimum, preflight must fail if required control-plane/data-plane paths are unavailable.
Best-effort probes (for example UDP VXLAN probes) may warn without hard-failing join preflight.

## Ownership Registry Contract
See [ownership-registry.md](./ownership-registry.md).

Uninstall/remove workflows must only act on artifacts listed in the local registry.
