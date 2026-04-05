# Ownership Registry Contract

Node join/remove automation must track owned artifacts on each remote host.

## Registry Path
`/var/lib/localk8s/node-join-owned-artifacts.yaml`

## Purpose
- define cleanup scope for uninstall/remove
- prevent deletion of non-owned host configuration
- support idempotent reruns

## Schema (v1)
```yaml
schema_version: 1
node_name: gpu-worker-01
managed_by: localk8s-node-join
artifacts:
  files:
    - /etc/rancher/k3s/k3s-agent.service.env
  directories:
    - /var/lib/rancher/k3s/agent
  services:
    - k3s-agent
  packages:
    - nvidia-container-toolkit
last_reconciled_utc: "2026-04-05T00:00:00Z"
```

## Update Rules
- Add entries only when automation creates/manages the artifact.
- Remove entries only when uninstall/remove successfully deletes artifact.
- Never auto-import preexisting host artifacts into ownership scope.

## Uninstall Rules
- Remove workflow must read registry first.
- If registry is missing/corrupt, abort destructive cleanup by default.
- Allow explicit force mode only with clear operator confirmation and logs.
