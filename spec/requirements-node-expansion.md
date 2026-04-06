# Laminar Node Expansion Requirements

## Functional Requirements (EARS)
- REQ-NODE-001: The system shall keep the existing `laminarflow` k3s server as control-plane authority for node expansion.
- REQ-NODE-002: The system shall provide a scripted node-join workflow that installs/configures k3s agent on a remote worker host.
- REQ-NODE-003: When join parameters are valid, the system shall register the remote worker as `Ready` in the existing cluster.
- REQ-NODE-004: The system shall provide a scripted node-removal workflow that cordons/drains/deletes cluster membership and uninstalls agent components on the target host.
- REQ-NODE-005: If GPU enablement is requested for a worker, the system shall install/verify NVIDIA container runtime integration and validate `nvidia.com/gpu` allocatable visibility.
- REQ-NODE-006: The system shall preserve KubeRay operator and Ray workload functionality during and after node join.
- REQ-NODE-007: The system shall preserve Ollama service availability during and after node join.
- REQ-NODE-008: The system shall support scheduling intent controls for the new worker (labels and optional taints) so Ray/Ollama placement can be explicit.
- REQ-NODE-009: The system shall maintain idempotent rerun behavior for join/remove workflows without destructive impact to unrelated hosts/resources.
- REQ-NODE-010: The system shall keep sensitive join data (tokens, endpoint secrets) out of version-controlled files and logs.
- REQ-NODE-011: The system shall keep orchestration anchored in repository entrypoints and pinned component versions.
- REQ-NODE-012: The system shall document operator run/verify/recovery procedures for node expansion in a runbook location.
- REQ-NODE-013: The system shall keep Ollama bound to declared storage locality by default (primary-node PVC) and shall require an explicit migration workflow before relocating Ollama workload placement.
- REQ-NODE-014: The system shall perform multi-node network preflight checks for required k3s control-plane and data-plane connectivity before attempting agent join.
- REQ-NODE-015: The system shall include verification that join/remove workflow logs redact token values and do not emit raw secrets.
- REQ-NODE-016: The system shall refuse control-plane node removal by default and shall require an explicit override flag for any control-plane-targeted removal operation.
- REQ-NODE-017: The system shall maintain an explicit node-join ownership registry for remote host artifacts so uninstall/delete operations are restricted to automation-owned components.

## Data & Interface Contracts
- Join entrypoint:
  - `scripts/join-node.sh` (proposed) accepts inventory/host target and optional GPU enablement flag.
- Remove entrypoint:
  - `scripts/remove-node.sh` (proposed) accepts node identity and performs drain/delete/uninstall flow.
- Ansible contracts:
  - inventory-driven remote execution
  - no hardcoded host secrets in tracked files
- Kubernetes contracts:
  - node labels/taints are declarative and re-applied idempotently.

## Error Handling & Recovery
- If remote host preflight fails, join workflow shall exit before cluster mutation.
- If join succeeds but post-check fails, workflow shall emit exact remediation commands.
- If node drain fails on remove, workflow shall stop and avoid partial destructive cleanup unless forced mode is explicitly selected.

## Performance & Scalability
- Phase target: one additional worker node.
- Join-to-ready target: worker becomes `Ready` within 10 minutes on healthy network/hardware.
- Validation must include at least one Ray GPU workload placement on the new worker when GPU mode is enabled.

## Security & Privacy
- Join token handling must use ephemeral runtime env or prompt input.
- Logs must redact token values.
- SSH/auth to remote host must follow least privilege and explicit sudo boundaries.

## Observability
- Healthcheck must be extended to report multi-node status and optional per-node GPU allocatable.
- Validation output must record node labels/taints and workload placement results.
- Join/remove logs must expose stage-level diagnostics without leaking secret values.

## Validation Plan
- REQ-NODE-001/002/003: run join script and verify node appears `Ready`.
- REQ-NODE-004: run remove script and verify node absence + host agent uninstall.
- REQ-NODE-005: run GPU validation pod pinned to worker and confirm `nvidia-smi`.
- REQ-NODE-006/007: verify KubeRay and Ollama pods/services remain healthy.
- REQ-NODE-008: verify configured labels/taints exist and placement rules behave as expected.
- REQ-NODE-009: rerun join/remove dry runs and confirm stable convergence behavior.
- REQ-NODE-010/011/012: inspect logs/config/docs for token hygiene, pin usage, and documented runbook steps.
- REQ-NODE-013: verify Ollama remains pinned to declared storage node unless explicit migration procedure is executed.
- REQ-NODE-014: verify preflight fails when required network ports/routes are unavailable and passes when restored.
- REQ-NODE-015: validate logs redact token values in both success and failure paths.
- REQ-NODE-016: verify remove workflow rejects control-plane node targets unless override flag is explicitly set.
- REQ-NODE-017: verify uninstall logic only removes artifacts listed in ownership registry and leaves non-owned artifacts intact.
