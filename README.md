# Laminar

[![Platform](https://img.shields.io/badge/platform-k3s-blue)](https://k3s.io/)
[![GPU](https://img.shields.io/badge/gpu-NVIDIA-76B900)](https://www.nvidia.com/)
[![Orchestrator](https://img.shields.io/badge/ray-KubeRay-orange)](https://ray.io/)
[![LLM Runtime](https://img.shields.io/badge/ollama-in--cluster-black)](https://ollama.com/)

Laminar is a k3s control-plane baseline for local AI systems work.  
It provisions and reconciles a control-plane host with NVIDIA runtime/device plugin, KubeRay, in-cluster Ollama, and local dashboard routes. It also includes inventory-driven node join/remove automation for adding CPU or GPU workers, with validation scripts and idempotent convergence workflows so reruns return to a known day-0 state.

## Table of Contents

- [What This Repo Does](#what-this-repo-does)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Node Expansion (Optional)](#node-expansion-optional)
- [CPU Worker Canary](#cpu-worker-canary)
- [GPU Worker Validation](#gpu-worker-validation)
- [Tested Environment](#tested-environment)
- [Access Endpoints](#access-endpoints)
- [Model Management](#model-management)
- [Repository Layout](#repository-layout)
- [Operations](#operations)
- [Security Notes](#security-notes)

## What This Repo Does

- Installs and reconciles a **single-node k3s** cluster.
- Supports optional **remote worker expansion** via scripted join/remove flows.
- Enables **NVIDIA GPU scheduling** with time-slicing.
- Deploys **KubeRay** and a GPU-backed `RayCluster`.
- Deploys **Ollama in-cluster** on GPU with persistent model storage.
- Exposes gateway routes via Traefik:
  - `http://<your-local-hostname>/ray/`
  - `http://<your-local-hostname>/k3s/`
- Keeps managed resources idempotent and prune-safe via ownership labels.

## Architecture

Execution model:

1. `scripts/setup.sh`: installs local tooling (`ansible`, `helm`, `helmfile`, `rg`).
2. `scripts/bootstrap.sh`: reconciles control-plane host + in-cluster components.
3. Ansible (`ansible/site.yml`):
   - host prerequisites
   - k3s install/config
   - NVIDIA runtime setup (host and worker paths)
4. Helmfile (`helmfile.yaml`):
   - NVIDIA device plugin
   - KubeRay operator
   - Headlamp dashboard
5. Managed manifests (`k8s/managed/`):
   - RayCluster and limits
   - Ollama workload + storage
   - ingress/middleware routes
6. Node lifecycle scripts:
   - `scripts/join-node.sh`: add CPU/GPU workers from inventory
   - `scripts/remove-node.sh`: controlled drain/delete/uninstall with ownership-registry gating

## Quick Start

### 1) Install tools

```bash
./scripts/setup.sh
```

`setup.sh` writes `config/local.env` with `LOCAL_HOSTNAME` for local route checks and examples.

Optional shell persistence:

```bash
echo 'export LOCAL_HOSTNAME="<your-local-hostname>"' >> ~/.bashrc
# or ~/.zshrc
```

### 2) (Optional but recommended) Remove host Ollama

```bash
./scripts/remove-host-ollama.sh
```

### 3) Mount model disk (required in this repo baseline)

```bash
./scripts/mount-ollama-model-disk.sh
```

If your model disk UUID or mount path differ, override:

```bash
OLLAMA_MODEL_DISK_UUID=<your-disk-uuid> ./scripts/mount-ollama-model-disk.sh
# optional: OLLAMA_MODEL_MOUNT_POINT=/mnt/ollama-models
```

### 4) Bootstrap everything

```bash
./scripts/bootstrap.sh
./scripts/healthcheck.sh
```

## Node Expansion (Optional)

Use the inventory in `packages/node-join/inventory.example.ini` as the template for remote workers.

Join a worker:

```bash
K3S_JOIN_TOKEN='<token>' ./scripts/join-node.sh --target polecat
```

Join a GPU worker:

```bash
K3S_JOIN_TOKEN='<token>' ./scripts/join-node.sh --target standpunkt --gpu
```

Remove a worker (controlled cleanup):

```bash
./scripts/remove-node.sh --node <k8s-node-name> --target <inventory-host>
```

Break-glass removal (missing/corrupt/mismatched registry):

```bash
./scripts/remove-node.sh --node <k8s-node-name> --target <inventory-host> --force-without-registry
```

## CPU Worker Canary

Before rolling out a GPU worker, validate remote worker provisioning on a CPU-only node:

```bash
./scripts/validate-cpu-worker.sh
```

Defaults:
- target node: `polecat`
- kubeconfig: `$KUBECONFIG` or `/etc/rancher/k3s/k3s.yaml`

Optional target override:

```bash
./scripts/validate-cpu-worker.sh --node polecat --timeout 300s
```

## GPU Worker Validation

After joining a GPU-capable worker, validate runtime and scheduling with:

```bash
./scripts/validate-gpu-worker.sh
```

Defaults:
- target node: `standpunkt`
- namespace: `ray`
- timeout: `300s`
- validation image: `nvidia/cuda:12.5.0-base-ubuntu22.04`

Optional override example:

```bash
./scripts/validate-gpu-worker.sh --node standpunkt --namespace ray --timeout 300s
```

This check confirms:
- the node is `Ready`
- GPU profile labels are present
- an ephemeral CUDA pod can request `nvidia.com/gpu=1` and run `nvidia-smi`

## Tested Environment

Validated on:
- Linux: Ubuntu 26.04 (Resolute Raccoon, Debian family)
- Local tooling installed by `scripts/setup.sh`:
  - `ansible-core` 2.20.1
  - `helm` v3.17.3
  - `helmfile` 0.169.1
  - `ripgrep` 15.1.0
- Platform pins from `config/versions.env`:
  - `k3s` v1.33.1+k3s1
  - `nvidia-device-plugin` chart 0.17.1
  - `kuberay-operator` chart 1.3.0
  - `ray` image tag 2.47.1
  - `headlamp` chart 0.41.0

## Access Endpoints

- Ray dashboard: `http://<your-local-hostname>/ray/`
- Cluster dashboard (Headlamp): `http://<your-local-hostname>/k3s/`
- Ollama API: `http://<your-local-hostname>:11434` (or `http://127.0.0.1:11434` from host)

Headlamp token helper:

```bash
./scripts/get-headlamp-token.sh
./scripts/get-headlamp-token.sh --duration 24h
```

## Model Management

Pull/verify configured Ollama models:

```bash
./scripts/pull-models.sh
./scripts/pull-models.sh --verify-only
```

Model list source:
- `config/models.txt` (one tag per line, `#` comments supported)

## Repository Layout

```text
ansible/         Host and k3s configuration roles
config/          Version pins, managed-scope config, model list
helm/values/     Helm values for operators and plugins
k8s/managed/     Managed Kubernetes manifests (pruned by label)
packages/node-join/  Inventory contracts and node join/remove docs
scripts/         Setup/bootstrap/health/ops helper scripts
spec/            Context/requirements/design/tasks chain
docs/runbook.md  Operational execution log and validation evidence
```

## Operations

Re-run reconciliation safely:

```bash
./scripts/bootstrap.sh
```

Remove a worker node with controlled cleanup:

```bash
./scripts/remove-node.sh --node <k8s-node-name> --target <inventory-host>
```

Removal behavior is ownership-registry gated:
- the workflow cordons, drains, and deletes the node object first
- remote uninstall only cleans artifacts listed in `/var/lib/localk8s/node-join-owned-artifacts.yaml`
- if the registry is missing or corrupt, removal fails by default
- break-glass mode is explicit: `--force-without-registry`

Convergence check (requires interactive sudo):

```bash
./scripts/idempotency-check.sh
```

Manual cluster context:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

## Security Notes

- Current route exposure is unauthenticated by design for local/trusted use.
- If network scope expands, add Traefik auth middleware and TLS before wider access.
- Managed cleanup is restricted by:
  - label selector `app.kubernetes.io/managed-by=localk8s-bootstrap`
  - explicit prune allowlist in `scripts/bootstrap.sh`
