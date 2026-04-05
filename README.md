# LocalK8s

[![Platform](https://img.shields.io/badge/platform-k3s-blue)](https://k3s.io/)
[![GPU](https://img.shields.io/badge/gpu-NVIDIA-76B900)](https://www.nvidia.com/)
[![Orchestrator](https://img.shields.io/badge/ray-KubeRay-orange)](https://ray.io/)
[![LLM Runtime](https://img.shields.io/badge/ollama-in--cluster-black)](https://ollama.com/)

LocalK8s is a single-host GPU Kubernetes baseline for local AI systems work.  
It provisions k3s, NVIDIA runtime/device plugin, KubeRay, in-cluster Ollama, dashboard ingress routes, and day-0 convergence scripts.

## Table of Contents

- [What This Repo Does](#what-this-repo-does)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Access Endpoints](#access-endpoints)
- [Model Management](#model-management)
- [Repository Layout](#repository-layout)
- [Operations](#operations)
- [Security Notes](#security-notes)

## What This Repo Does

- Installs and reconciles a **single-node k3s** cluster.
- Enables **NVIDIA GPU scheduling** with time-slicing.
- Deploys **KubeRay** and a GPU-backed `RayCluster`.
- Deploys **Ollama in-cluster** on GPU with persistent model storage.
- Exposes gateway routes via Traefik:
  - `http://laminarflow/ray/`
  - `http://laminarflow/k3s/`
- Keeps managed resources idempotent and prune-safe via ownership labels.

## Architecture

Execution model:

1. `scripts/setup.sh`: installs local tooling (`ansible`, `helm`, `helmfile`, `rg`).
2. `scripts/bootstrap.sh`: orchestrates full reconciliation.
3. Ansible (`ansible/site.yml`):
   - host prerequisites
   - k3s install/config
   - NVIDIA runtime setup
4. Helmfile (`helmfile.yaml`):
   - NVIDIA device plugin
   - KubeRay operator
   - Headlamp dashboard
5. Managed manifests (`k8s/managed/`):
   - RayCluster and limits
   - Ollama workload + storage
   - ingress/middleware routes

## Quick Start

### 1) Install tools

```bash
./scripts/setup.sh
```

### 2) (Optional but recommended) Remove host Ollama

```bash
./scripts/remove-host-ollama.sh
```

### 3) Mount model disk (required in this repo baseline)

```bash
./scripts/mount-ollama-model-disk.sh
```

Default configured disk UUID:
- `052b22cb-460f-4951-8d78-7a816f8a6895` (`/dev/sda1` on this host)

### 4) Bootstrap everything

```bash
./scripts/bootstrap.sh
./scripts/healthcheck.sh
```

## Access Endpoints

- Ray dashboard: `http://laminarflow/ray/`
- Cluster dashboard (Headlamp): `http://laminarflow/k3s/`
- Ollama API: `http://laminarflow:11434` (or `http://127.0.0.1:11434` from host)

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
docs/            System2 seed docs and gate artifacts
helm/values/     Helm values for operators and plugins
k8s/managed/     Managed Kubernetes manifests (pruned by label)
scripts/         Setup/bootstrap/health/ops helper scripts
spec/            Context/requirements/design/tasks chain
```

## Operations

Re-run reconciliation safely:

```bash
./scripts/bootstrap.sh
```

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
