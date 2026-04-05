# LocalK8s Runbook

## Purpose
This runbook records install, reconciliation, and validation evidence for the single-node LocalK8s baseline.

Use it to capture:
- what was changed
- what commands were run
- what passed/failed
- what follow-up is required

## Environment Snapshot
- Date:
- Operator:
- Hostname:
- Linux distro/version:
- GPU (`nvidia-smi -L`):
- Branch/commit:

## Bootstrap Procedure
Run in order:

```bash
./scripts/setup.sh
./scripts/bootstrap.sh
./scripts/healthcheck.sh
```

If model disk is required:

```bash
./scripts/mount-ollama-model-disk.sh
```

If migrating host Ollama to in-cluster:

```bash
./scripts/remove-host-ollama.sh
```

## Validation Checklist
Record command + result (`PASS`/`FAIL`) for each:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml describe node "$(kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes -o jsonpath='{.items[0].metadata.name}')" | rg 'nvidia.com/gpu'
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get raycluster -n ray
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get pods -n ollama
curl -fsS "http://${LOCAL_HOSTNAME:-$(hostname -s)}/ray/" >/dev/null
curl -fsS "http://${LOCAL_HOSTNAME:-$(hostname -s)}/k3s/" >/dev/null
```

## Idempotency / Day-0 Convergence
Run and capture outcome:

```bash
./scripts/idempotency-check.sh
```

Expected: second reconciliation is clean, managed resources converge, no stale managed config remains.

## Incident Notes
- Symptom:
- Root cause:
- Resolution:
- Preventive action:

## Change Log Entries
- YYYY-MM-DD: short summary of infra/config change and validation result.
