# Laminar GPU Ray Platform Requirements

## Functional Requirements (EARS, numbered with IDs)
- REQ-001: The system shall install and run a single-node k3s cluster on the target host.
- REQ-002: When NVIDIA driver and container toolkit prerequisites are met, the system shall configure Kubernetes workloads to access GPU resources.
- REQ-003: The system shall deploy the NVIDIA device plugin and expose allocatable `nvidia.com/gpu` resources on the node.
- REQ-004: When a CUDA validation pod is executed, the system shall return successful `nvidia-smi` output from inside the container.
- REQ-005: The system shall deploy the KubeRay operator into a dedicated namespace.
- REQ-006: The system shall deploy one RayCluster where the head pod requests no GPU and worker pods request/limit `nvidia.com/gpu`.
- REQ-007: Where time-slicing is enabled, the system shall support successful concurrent GPU Ray workload execution at 1, 2, and 4 job levels without interactive host debugging.
- REQ-008: The system shall provide `scripts/bootstrap.sh` to perform idempotent install/deploy actions, converge to Day-0 desired state for managed assets, and provide credentials/helper output for k3s console access.
- REQ-009: The system shall provide `scripts/healthcheck.sh` to report cluster readiness, GPU allocatable state, and Ray workload health.
- REQ-010: If component versions are changed, the system shall keep pinned version declarations in a single tracked configuration location.
- REQ-011: When bootstrap is re-run, the system shall remove stale project-managed Kubernetes resources and managed host configuration that are not part of the current Day-0 desired state.
- REQ-012: If k3s default runtime is not set to `nvidia`, GPU workload pod specs shall explicitly set `runtimeClassName: nvidia`.
- REQ-013: The system shall use `scripts/bootstrap.sh` as the only orchestration entrypoint, delegating host setup to Ansible and Helm release management to Helmfile.
- REQ-014: The system shall provide `scripts/setup.sh` to install and verify host-side bootstrap prerequisites (`ansible-playbook`, `helm`, `helmfile`, `rg`) idempotently.

## Data & Interface Contracts (schemas, APIs, persistence, idempotency)
- Kubernetes interfaces:
  - Helm releases for NVIDIA device plugin and KubeRay operator.
  - RayCluster custom resource manifests.
- Script interfaces:
  - `scripts/bootstrap.sh` exits non-zero on failed stage.
  - `scripts/bootstrap.sh` outputs or writes helper instructions for `kubectl` access using the k3s admin kubeconfig path (`/etc/rancher/k3s/k3s.yaml`) or an explicit equivalent.
  - `scripts/healthcheck.sh` exits non-zero when required checks fail.
- Idempotency:
  - Re-running bootstrap shall converge managed resources to the same Day-0 desired state.
  - Managed resources shall be labeled/identified with explicit ownership metadata for safe cleanup.

## Error Handling & Recovery (including retries, timeouts, fallbacks)
- Bootstrap stages shall fail fast with clear stage labels.
- Network-dependent install steps shall support bounded retries.
- If GPU checks fail, subsequent Ray deployment stages shall stop and report the failure.
- If cleanup scope cannot be proven to be project-managed, bootstrap shall refuse deletion and surface remediation instructions.
- Recovery path shall document rerun-from-stage behavior.

## Performance & Scalability (explicit budgets/thresholds where possible)
- Baseline benchmark shall include 1, 2, and 4 concurrent GPU jobs.
- Initial target: stable execution at concurrency 4 with time-slicing enabled.
- Benchmark output shall include per-run latency and throughput summary.

## Security & Privacy (authn/z, least privilege, input sanitization, logging hygiene)
- Cluster and dashboards shall be local-only by default in phase 1.
- Scripts shall avoid logging secrets and credentials.
- Kubernetes RBAC shall use namespace-scoped permissions where practical.

## Observability (logs/metrics/traces; SLIs/SLOs if relevant)
- Healthcheck shall report node readiness, GPU allocatable, and Ray pod status.
- Validation runbook shall include commands and expected pass/fail signals.
- Benchmark results shall be stored in a timestamped local artifact.

## Backward Compatibility & Migration
- Version upgrades shall be explicit and documented.
- Existing local cluster state outside project-managed ownership scope shall not be force-destroyed by default bootstrap behavior.

## Compliance / Policy Constraints (if relevant)
- No additional compliance constraints identified for phase 1 single-user local deployment.

## Validation Plan (how each requirement will be tested/validated)
- REQ-001: `kubectl get nodes` returns one Ready node.
- REQ-002/REQ-003: `kubectl describe node <node>` shows `nvidia.com/gpu` capacity/allocatable.
- REQ-004: CUDA pod execution of `nvidia-smi` exits successfully.
- REQ-005/REQ-006: `kubectl get pods -n kuberay-system` and `kubectl get raycluster -n ray` show ready resources.
- REQ-007: sample Ray workload completes successfully at 1, 2, and 4 concurrent jobs.
- REQ-008: bootstrap script run outputs console access helper/credentials guidance and returns expected exit code.
- REQ-009: healthcheck script run returns expected exit code and status output.
- REQ-010: pinned versions are present and referenced by scripts/manifests.
- REQ-011: run bootstrap twice and verify no stale project-managed resources or managed host config remain from prior revision.
- REQ-012: confirm GPU workloads run with either k3s `--default-runtime nvidia` or `runtimeClassName: nvidia` set in pod specs.
- REQ-013: verify bootstrap invokes Ansible playbook and Helmfile releases for NVIDIA plugin and KubeRay.
- REQ-014: run setup script multiple times and verify tool prerequisites remain installed without destructive side effects.

## Traceability Matrix (Requirement -> Design Section -> Task IDs)
| Requirement | Design Section(s) | Task IDs |
| --- | --- | --- |
| REQ-001 | Architecture; Rollout Plan | TASK-001, TASK-003 |
| REQ-002 | Public Interfaces; Failure Modes & Recovery | TASK-001, TASK-003 |
| REQ-003 | Architecture; Public Interfaces | TASK-003 |
| REQ-004 | Verification Strategy | TASK-007 |
| REQ-005 | Architecture; Rollout Plan | TASK-004 |
| REQ-006 | Architecture; Public Interfaces | TASK-005 |
| REQ-007 | Concurrency, Ordering, and Consistency; Verification Strategy | TASK-006, TASK-007 |
| REQ-008 | Public Interfaces; Rollout Plan | TASK-001, TASK-003, TASK-004, TASK-005, TASK-008, TASK-009 |
| REQ-009 | Observability; Verification Strategy | TASK-008 |
| REQ-010 | Data Model & Storage; Rollout Plan | TASK-002, TASK-008 |
| REQ-011 | Data Model & Storage; Failure Modes & Recovery; Rollout Plan | TASK-001, TASK-002, TASK-009 |
| REQ-012 | Public Interfaces; Architecture; Verification Strategy | TASK-003, TASK-005, TASK-007 |
| REQ-013 | Architecture; Public Interfaces; Rollout Plan | TASK-001, TASK-003, TASK-004 |
| REQ-014 | Public Interfaces; Rollout Plan | TASK-001, TASK-002 |
