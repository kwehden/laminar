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
- [Tested Environment](#tested-environment)
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
  - `http://<your-local-hostname>/ray/`
  - `http://<your-local-hostname>/k3s/`
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

Default configured disk UUID:
- `052b22cb-460f-4951-8d78-7a816f8a6895` (`/dev/sda1` on this host)

### 4) Bootstrap everything

```bash
./scripts/bootstrap.sh
./scripts/healthcheck.sh
```

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
