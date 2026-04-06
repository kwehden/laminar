# Laminar Platform Prerequisites and Applicability

## Purpose
This document defines the host prerequisites Laminar assumes, the environment it has been validated on, and where the current spec should or should not be applied without adaptation.

## Tested Baseline (Validated)
- OS: Ubuntu 26.04 (Resolute, Debian family)
- Kubernetes: k3s `v1.33.1+k3s1`
- GPU stack:
  - NVIDIA driver `580.126.09` (CUDA 13.0 shown by `nvidia-smi`)
  - `nvidia-container-toolkit` installed and runtime detected by k3s/containerd
- Host class used for baseline validation:
  - CPU: AMD Ryzen 7 5700G
  - RAM: 61 GiB
  - GPU: NVIDIA GeForce RTX 5060 Ti (16 GiB VRAM class)

## Control-Plane Host Prerequisites
- `x86_64` Linux host with `sudo` privileges
- `apt`-based distro (current setup automation targets Debian family)
- Internet access to package/chart repositories (Ubuntu, NVIDIA, Helm charts)
- Required tools installed via `./scripts/setup.sh`:
  - `ansible-playbook`, `helm`, `helmfile`, `rg`, `jq`, `curl`
- For GPU scheduling:
  - `nvidia-smi` works on host before running `bootstrap.sh`

## Worker Node Prerequisites (Node Expansion)
- SSH connectivity from control-plane host to worker (`ansible_user` + sudo)
- Worker can reach control-plane k3s API (`tcp/6443`)
- Data-plane networking allowed for cluster operation
- Recommended for automation stability: passwordless sudo for the worker automation user
- GPU worker only:
  - NVIDIA driver installed
  - Toolkit/runtime setup succeeds (`node_gpu_runtime` role)

## Applicability Matrix
### Applies Directly
- Single control-plane host bootstrap on Ubuntu 26.04 (Debian family)
- Optional CPU/GPU worker expansion using `join-node.sh`/`remove-node.sh`

### Likely Applies With Minor Adaptation (Not Fully Validated)
- Adjacent Ubuntu/Debian releases with compatible package names/repos
- Different NVIDIA GPUs supported by current driver/toolkit path

### Not Currently Covered by This Spec
- Non-`apt` Linux distributions (RHEL/Fedora/Arch) without script changes
- Non-NVIDIA GPU stacks
- Production-grade multi-control-plane HA
- Internet-exposed unauthenticated dashboard deployments

## When to Treat This Spec as Reference Only
- You deviate from Debian-family package management.
- Your GPU/runtime stack requires nonstandard driver/toolkit configuration.
- You require strict enterprise controls (authn/z, TLS everywhere, multi-tenant policy).

In these cases, keep Laminar script structure, but adapt host/runtime roles and validate each gate in a staging environment first.
