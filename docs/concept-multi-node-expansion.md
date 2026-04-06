# System2 Concept: Multi-Node Expansion for Laminar

## Gate 0 Scope
Explore how to add a second machine (with an additional GPU) as a cluster member, while preserving the current Laminar Day-0 convergence model.

Decision question:
- Do we need to move from k3s to upstream/kubeadm Kubernetes to support this?  

## Gate 1 Context
Current baseline is a single-node k3s cluster with:
- host automation via Ansible
- release management via Helm/Helmfile
- managed manifests for Ray, Ollama, and ingress
- idempotent reconciliation through `scripts/bootstrap.sh`

Desired next state:
- one existing control-plane node
- one additional worker node on the LAN
- optional GPU scheduling on the new node

## Gate 2 Requirements (Concept-Level)
- Add a node using repeatable automation, not manual CLI-only steps.
- Keep existing single-node bootstrap behavior intact.
- Support secure join (`K3S_URL` + join token), with minimal secret exposure.
- Keep ownership boundaries explicit so reruns are safe.
- Validate node readiness and GPU allocatable state after join.
- Provide reversible operations (node drain/remove/uninstall flow).

## Gate 3 Design Options

### Option A: Keep k3s, add k3s agent node (Recommended)
Use current node as k3s server; new machine joins as k3s agent.

Pros:
- No platform migration.
- Lowest operational risk and fastest path.
- Reuses existing automation patterns and tooling.

Cons:
- Single control-plane remains a SPOF.
- Future scale limits compared with larger distributions.

### Option B: Move to k3s HA (multi-server)
Keep k3s, introduce embedded/externally-backed HA control plane.

Pros:
- Better control-plane resilience.
- Still lighter than kubeadm.

Cons:
- Added complexity now; unnecessary for immediate 2-node goal.

### Option C: Migrate to kubeadm/mainline Kubernetes

Pros:
- Full upstream defaults and ecosystem parity.

Cons:
- Large migration cost for little immediate gain.
- Higher maintenance burden for local-lab workflow.

## Recommendation
Do **not** migrate to kubeadm for this expansion.  
Adopt **Option A** now: multi-node k3s with a new GPU worker agent.

Revisit platform migration only if one of these triggers occurs:
- need managed HA control plane
- need strict upstream behavior not available/acceptable in k3s
- node count and operational complexity exceed current automation model

## Proposed Sub-Package
Create a new automation slice in this repo:

`packages/node-join/`

Suggested contents:
- `packages/node-join/README.md`: operator flow
- `packages/node-join/inventory.example.ini`: remote host definition
- `ansible/roles/k3s_agent/`: install/join/remove logic
- `ansible/roles/node_gpu_runtime/`: NVIDIA runtime setup on remote worker
- `scripts/join-node.sh`: orchestrated join entrypoint
- `scripts/remove-node.sh`: drain + delete + host uninstall path

## Execution Flow (High-Level)
1. Control node preflight:
   - resolve server API endpoint
   - fetch/validate join token
2. Worker host preflight:
   - OS/support checks
   - network reachability to k3s API (`6443`)
   - GPU/runtime prerequisites (if GPU worker)
3. Join:
   - install k3s agent and start service
   - apply labels/taints (for scheduling intent)
4. Post-join validation:
   - `kubectl get nodes`
   - node Ready + expected labels
   - GPU allocatable checks (`nvidia.com/gpu`) if configured
5. Rollback/remove:
   - cordon/drain
   - delete node object
   - uninstall k3s agent/runtime artifacts on remote host

## Risks and Controls
- Token leakage:
  - pass token through ephemeral env vars, never commit to repo.
- Scheduling contention:
  - add node labels/affinity and explicit GPU requests.
- Runtime mismatch on worker:
  - enforce preflight and fail fast before join.
- Drift across nodes:
  - pin versions and run periodic healthcheck across all nodes.

## Verification Plan (Concept)
- Join test: node appears Ready within timeout.
- GPU test: CUDA validation pod lands on worker and passes.
- Workload test: Ray/Ollama placement on targeted node works as expected.
- Idempotency test: rerunning join bootstrap does not duplicate or corrupt state.
- Removal test: remove-node workflow leaves no stale k3s-managed membership.

## Next System2 Artifact Chain
If approved, create:
1. `spec/context-node-expansion.md`
2. `spec/requirements-node-expansion.md`
3. `spec/design-node-expansion.md`
4. `spec/tasks-node-expansion.md`

This keeps scale-out work gated and independent from the current single-node baseline.
