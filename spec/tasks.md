# Laminar GPU Ray Platform Tasks

## Task Graph Overview (short)
Execution order is mostly linear due to platform dependencies: establish host/runtime prerequisites, pin versions and ownership scope, install cluster and GPU stack, deploy Ray, then validate and operationalize. The final step is explicit convergence verification by re-running bootstrap and confirming no stale managed configuration remains.

## Tasks (the full list)
### TASK-001
- Goal: Create bootstrap script skeleton with staged execution, fail-fast behavior, and reconciliation semantics.
- Files/areas expected to change: `scripts/setup.sh`, `scripts/bootstrap.sh`, `README.md`.
- Dependencies: none.
- Recommended Mode: executor.
- Steps:
  1. Add setup script for required local toolchain prerequisites.
  2. Add staged bootstrap framework with named phases and strict shell options.
  3. Add reusable logging and error-handling helpers.
  4. Add orchestration hooks for Ansible and Helmfile execution.
  5. Add placeholders for k3s, NVIDIA, Ray install, and managed cleanup stages.
- Verification: run `bash -n scripts/bootstrap.sh`.
- Rollback / Backout note: remove script and references if foundational approach changes.
- Risk level: Low (structural scaffolding only).

### TASK-002
- Goal: Add central version pin and managed-ownership configuration consumed by automation.
- Files/areas expected to change: `config/versions.env`, `config/managed-assets.env` (or equivalent), `scripts/bootstrap.sh`, `spec/` references.
- Dependencies: TASK-001.
- Recommended Mode: executor.
- Steps:
  1. Define pinned versions for k3s, NVIDIA plugin/chart, and KubeRay.
  2. Load version pins in bootstrap script.
  3. Define explicit ownership selectors/paths for managed Kubernetes and host configuration.
  4. Add validation for missing or malformed config.
- Verification: source config files and run bootstrap preflight validation stage.
- Rollback / Backout note: revert to inline pins only if config indirection causes instability.
- Risk level: Low.

### TASK-003
- Goal: Implement k3s install/runtime compatibility plus NVIDIA device plugin deployment with time-slicing defaults.
- Files/areas expected to change: `scripts/bootstrap.sh`, `ansible/roles/k3s/*`, `ansible/roles/nvidia_runtime/*`, `helm/values/nvidia-device-plugin.yaml`.
- Dependencies: TASK-001, TASK-002.
- Recommended Mode: executor.
- Steps:
  1. Implement Ansible role flow for k3s single-node install/verify and node readiness checks.
  2. Emit k3s kubeconfig helper output (for example `/etc/rancher/k3s/k3s.yaml` guidance or `KUBECONFIG` export).
  3. Configure GPU runtime path compatibility (`--default-runtime nvidia` or pod-level `runtimeClassName: nvidia` strategy).
  4. Deploy NVIDIA device plugin through Helmfile with time-slice baseline (`2`).
  5. Validate allocatable `nvidia.com/gpu` appears on node.
- Verification: `kubectl get nodes`; `kubectl describe node <node> | rg -n "nvidia.com/gpu"`; runtime compatibility check command(s).
- Rollback / Backout note: uninstall plugin release and remove manifest resources.
- Risk level: High (hardware/runtime compatibility).

### TASK-004
- Goal: Deploy KubeRay operator and Ray namespace guardrails.
- Files/areas expected to change: `helm/values/kuberay-operator.yaml`, `k8s/managed/namespace-*.yaml`, `k8s/managed/ray-limits.yaml`, `scripts/bootstrap.sh`.
- Dependencies: TASK-003.
- Recommended Mode: executor.
- Steps:
  1. Create `ray` namespace manifests with `LimitRange` and `ResourceQuota`.
  2. Install KubeRay operator via Helmfile into `kuberay-system`.
  3. Ensure resources are tagged as project-managed for cleanup safety.
  4. Verify operator pods are ready.
- Verification: `kubectl get pods -n kuberay-system`; `kubectl get quota -n ray`.
- Rollback / Backout note: remove namespace guardrails and uninstall operator Helm release.
- Risk level: Medium.

### TASK-005
- Goal: Create RayCluster manifest with CPU head and GPU workers.
- Files/areas expected to change: `k8s/managed/raycluster.yaml`, `scripts/bootstrap.sh`.
- Dependencies: TASK-004.
- Recommended Mode: executor.
- Steps:
  1. Define head group with CPU-only resource requests.
  2. Define worker group requesting `nvidia.com/gpu` with conservative replicas.
  3. Set `runtimeClassName: nvidia` for GPU workloads when cluster default runtime is not `nvidia`.
  4. Add ownership labels/annotations for managed cleanup.
  5. Add bootstrap stage to apply/reconcile and wait for RayCluster readiness.
- Verification: `kubectl get raycluster -n ray`; `kubectl get pods -n ray`.
- Rollback / Backout note: delete RayCluster resource and related services.
- Risk level: Medium.

### TASK-006
- Goal: Add sample Ray GPU workload and concurrency tuning controls.
- Files/areas expected to change: `workloads/ray_gpu_benchmark.py`, `k8s/ray/jobs/*.yaml` or script wrapper.
- Dependencies: TASK-005.
- Recommended Mode: executor.
- Steps:
  1. Implement workload that sets explicit Ray `num_gpus` per task/actor.
  2. Parameterize concurrency input for 1, 2, and 4 runs.
  3. Capture throughput/latency output in local artifacts.
- Verification: run benchmark for 1 and 2 first, then 4.
- Rollback / Backout note: remove benchmark assets if design changes to another load harness.
- Risk level: Medium.

### TASK-007
- Goal: Implement validation assets for CUDA and end-to-end checks.
- Files/areas expected to change: `k8s/validation/cuda-test-pod.yaml`, `scripts/healthcheck.sh`, `docs/runbook.md`.
- Dependencies: TASK-003, TASK-005.
- Recommended Mode: test-engineer.
- Steps:
  1. Add CUDA test pod manifest for `nvidia-smi` validation.
  2. Set `runtimeClassName: nvidia` in CUDA test pod when default runtime is not `nvidia`.
  3. Add command runbook and expected outcomes.
  4. Add pass/fail criteria for concurrent GPU workload checks.
- Verification: apply pod manifest and confirm successful command output.
- Rollback / Backout note: remove validation manifest if replaced by a scripted check.
- Risk level: Medium.

### TASK-008
- Goal: Build healthcheck automation and final operator checklist.
- Files/areas expected to change: `scripts/healthcheck.sh`, `README.md`, `docs/runbook.md`.
- Dependencies: TASK-003, TASK-004, TASK-005, TASK-007.
- Recommended Mode: test-engineer.
- Steps:
  1. Implement healthcheck for node, GPU allocatable, and Ray status.
  2. Return non-zero on failed checks and print actionable diagnostics.
  3. Add checks that verify bootstrap helper output and runtime compatibility assumptions.
  4. Document routine operational run sequence.
- Verification: run healthcheck in healthy state and induced failure state.
- Rollback / Backout note: disable CI/automation calls to healthcheck if script is unstable.
- Risk level: Medium.

### TASK-009
- Goal: Implement convergence verification and stale-config cleanup checks for rerun safety.
- Files/areas expected to change: `scripts/bootstrap.sh`, `scripts/idempotency-check.sh`, `docs/runbook.md`.
- Dependencies: TASK-002, TASK-004, TASK-005, TASK-008.
- Recommended Mode: test-engineer.
- Steps:
  1. Implement managed-scope cleanup logic in bootstrap using ownership selectors/managed path list.
  2. Add an idempotency check script that runs bootstrap twice and snapshots managed state.
  3. Verify stale managed resources/config from prior revision are removed after rerun.
  4. Ensure cleanup refuses to act on unowned/ambiguous resources.
- Verification: `scripts/idempotency-check.sh` passes and reports Day-0 convergence.
- Rollback / Backout note: disable cleanup phase and fall back to apply-only mode until ownership boundaries are fixed.
- Risk level: High (cleanup safety and ownership boundaries).

## Definition of Done Checklist
- [ ] `spec/context.md`, `spec/requirements.md`, `spec/design.md`, and `spec/tasks.md` are approved.
- [ ] Bootstrap script deploys k3s, NVIDIA plugin, and KubeRay without manual patching.
- [ ] Bootstrap rerun converges to Day-0 desired state and leaves no stale project-managed configuration.
- [ ] RayCluster reaches ready state with GPU workers.
- [ ] CUDA and concurrent Ray workload validations pass.
- [ ] Healthcheck script reports expected status and fails correctly on broken conditions.
- [ ] Version pins are centralized and referenced by automation.

## Execution Notes (tooling, environment, checkpoints)
- Start every execution cycle by confirming host GPU inventory (`nvidia-smi`) and disk headroom.
- Prefer incremental stage execution to localize failures quickly.
- Record validation command outputs after each stage in `docs/runbook.md`.
- Keep defaults local-only; avoid exposing dashboards beyond localhost in phase 1.

## Traceability (REQ IDs -> TASK IDs)
- REQ-001 -> TASK-001, TASK-003
- REQ-002 -> TASK-001, TASK-003
- REQ-003 -> TASK-003
- REQ-004 -> TASK-007
- REQ-005 -> TASK-004
- REQ-006 -> TASK-005
- REQ-007 -> TASK-006, TASK-007
- REQ-008 -> TASK-001, TASK-003, TASK-004, TASK-005, TASK-008, TASK-009
- REQ-009 -> TASK-008
- REQ-010 -> TASK-002, TASK-008
- REQ-011 -> TASK-001, TASK-002, TASK-009
- REQ-012 -> TASK-003, TASK-005, TASK-007
- REQ-013 -> TASK-001, TASK-003, TASK-004
- REQ-014 -> TASK-001, TASK-002
