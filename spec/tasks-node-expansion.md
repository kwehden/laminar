# Laminar Node Expansion Tasks

## Task Graph Overview
Order is dependency-driven: define node-join configuration and contracts, implement join/remove automation, add worker GPU runtime path, then validate placement and convergence behavior.

## Tasks
### NODE-TASK-001
- Goal: Add node-expansion configuration model and inventory scaffolding.
- Files/areas expected to change: `packages/node-join/README.md`, `packages/node-join/inventory.example.ini`, `config/` additions as needed.
- Dependencies: none.
- Recommended Mode: executor.
- Steps:
  1. Define inventory format for remote worker host(s).
  2. Define required inputs: node address, SSH user, optional labels/taints, GPU mode flag.
  3. Document secure token input pattern (env/prompt; no tracked secrets).
  4. Define required network preflight checks (control-plane + data-plane paths) and fail criteria.
  5. Define node ownership-registry format/path for automation-managed remote artifacts.
- Verification: schema/readme walkthrough and shell lint for any helper scripts.
- Risk level: Low.

### NODE-TASK-002
- Goal: Implement k3s agent install/join Ansible role.
- Files/areas expected to change: `ansible/roles/k3s_agent/*`, `ansible/site.yml` integration, `scripts/join-node.sh`.
- Dependencies: NODE-TASK-001.
- Recommended Mode: executor.
- Steps:
  1. Add idempotent agent install flow.
  2. Inject `K3S_URL` + token securely.
  3. Wait for node registration and readiness.
  4. Apply labels/taints.
- Verification: run join flow against one remote host and confirm `kubectl get nodes`.
- Risk level: High.

### NODE-TASK-003
- Goal: Implement worker GPU runtime role for optional Tesla M10 enablement.
- Files/areas expected to change: `ansible/roles/node_gpu_runtime/*`, `scripts/join-node.sh`, version/pin references where needed.
- Dependencies: NODE-TASK-002.
- Recommended Mode: executor.
- Steps:
  1. Add NVIDIA runtime preflight/setup for remote host.
  2. Verify runtime integration for k3s agent workloads.
  3. Validate worker allocatable `nvidia.com/gpu`.
- Verification: worker-targeted CUDA test pod passes.
- Risk level: High.

### NODE-TASK-004
- Goal: Add controlled node removal workflow.
- Files/areas expected to change: `scripts/remove-node.sh`, `ansible/roles/k3s_agent/*` uninstall tasks, docs updates.
- Dependencies: NODE-TASK-002.
- Recommended Mode: executor.
- Steps:
  1. Reject control-plane node target by default unless explicit override flag is provided.
  2. Cordon/drain target node.
  3. Delete node from cluster.
  4. Uninstall k3s agent and owned runtime artifacts on remote host using ownership registry scope.
- Verification: target node absent from cluster and remote agent service removed.
- Risk level: Medium.

### NODE-TASK-005
- Goal: Add Ray/Ollama placement validation for multi-node behavior.
- Files/areas expected to change: `k8s/managed/` scheduling policy updates, validation scripts/manifests, `scripts/healthcheck.sh`.
- Dependencies: NODE-TASK-003.
- Recommended Mode: test-engineer.
- Steps:
  1. Add optional affinity/selectors targeting secondary GPU worker.
  2. Validate Ray workload placement and completion.
  3. Enforce default Ollama primary-node storage locality and document explicit migration-only relocation path.
  4. Validate Ollama endpoint health and optional placement behavior.
- Verification: healthcheck plus targeted workload checks pass.
- Risk level: Medium.

### NODE-TASK-006
- Goal: Add convergence/idempotency checks for join/remove workflows.
- Files/areas expected to change: `scripts/idempotency-check.sh` extensions or new node-check script, `docs/runbook.md`.
- Dependencies: NODE-TASK-002, NODE-TASK-004, NODE-TASK-005.
- Recommended Mode: test-engineer.
- Steps:
  1. Rerun join on already-joined host and verify no destructive changes.
  2. Rerun remove on absent host and verify safe behavior.
  3. Validate secret redaction in join/remove logs (no raw token emission).
  4. Capture expected outcomes and failure triage in runbook.
- Verification: scripted checks pass with clear result output.
- Risk level: High.

## Definition of Done
- [ ] Node-join workflow adds one remote worker to existing `laminarflow` cluster.
- [ ] Optional GPU worker mode succeeds on Tesla M10 host and advertises allocatable GPU.
- [ ] KubeRay and Ollama remain healthy during and after expansion.
- [ ] Node removal workflow is reversible and safe.
- [ ] Reruns converge cleanly without stale managed artifacts.
- [ ] `docs/runbook.md` includes operator steps and validation evidence for expansion.

## Traceability (Requirement -> Task IDs)
- REQ-NODE-001 -> NODE-TASK-002
- REQ-NODE-002 -> NODE-TASK-001, NODE-TASK-002
- REQ-NODE-003 -> NODE-TASK-002
- REQ-NODE-004 -> NODE-TASK-004
- REQ-NODE-005 -> NODE-TASK-003
- REQ-NODE-006 -> NODE-TASK-005
- REQ-NODE-007 -> NODE-TASK-005
- REQ-NODE-008 -> NODE-TASK-002, NODE-TASK-005
- REQ-NODE-009 -> NODE-TASK-002, NODE-TASK-004, NODE-TASK-006
- REQ-NODE-010 -> NODE-TASK-001, NODE-TASK-002, NODE-TASK-006
- REQ-NODE-011 -> NODE-TASK-001, NODE-TASK-002, NODE-TASK-003
- REQ-NODE-012 -> NODE-TASK-006
- REQ-NODE-013 -> NODE-TASK-005
- REQ-NODE-014 -> NODE-TASK-001, NODE-TASK-002
- REQ-NODE-015 -> NODE-TASK-006
- REQ-NODE-016 -> NODE-TASK-004
- REQ-NODE-017 -> NODE-TASK-001, NODE-TASK-004
