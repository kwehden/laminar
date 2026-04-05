# Node Join Package

This package defines `NODE-TASK-001` scaffolding for adding remote worker nodes to an existing LocalK8s cluster.

Current scope:
- inventory contract
- secure token input contract
- network preflight contract
- ownership-registry contract

Initial script/role skeletons now exist in:
- `scripts/join-node.sh`
- `scripts/remove-node.sh`
- `ansible/roles/k3s_agent/tasks/main.yml`
- `ansible/roles/node_gpu_runtime/tasks/main.yml`

These are safe placeholders and intentionally avoid full destructive host mutation until later tasks are approved.

## Inventory Contract
Use [inventory.example.ini](./inventory.example.ini) as the template.

Required host-level fields:
- `ansible_host`
- `ansible_user`

Common optional fields:
- `localk8s_gpu_enable` (`true`/`false`)
- `localk8s_node_labels` (comma-separated `key=value`)
- `localk8s_node_taints` (comma-separated `key=value:Effect`)
- `localk8s_allow_control_plane_remove` (`false` by default)

Required group-level fields (`[node_join_targets:vars]`):
- `localk8s_k3s_url` (example: `https://laminarflow:6443`)
- `ansible_become=true`

## Secure Token Input Pattern
Do not store tokens in tracked files.

Supported input order for future join/remove scripts:
1. `K3S_JOIN_TOKEN` environment variable.
2. Interactive prompt (silent input) when env var is not set.

Logging requirements:
- never print raw token values
- mask token-bearing env vars in debug output

## Network Preflight Contract
See [network-preflight.md](./network-preflight.md).

At minimum, preflight must fail if required control-plane/data-plane paths are unavailable.

## Ownership Registry Contract
See [ownership-registry.md](./ownership-registry.md).

Uninstall/remove workflows must only act on artifacts listed in the local registry.
