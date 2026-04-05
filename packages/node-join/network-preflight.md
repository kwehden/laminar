# Network Preflight Contract

This preflight applies before attempting `k3s` agent join.

## Required Paths
1. Worker -> control-plane (`laminarflow`) `tcp/6443` (k3s API).
2. Worker -> control-plane CNI data-plane probe (current default: flannel VXLAN `udp/8472` best-effort probe).

If any required path fails, join must stop with actionable diagnostics.

## Post-Join Required Path
3. Control-plane -> worker kubelet path `tcp/10250`.

If this check fails after join, the workflow must fail and surface remediation guidance.

## Recommended Checks
From worker host:

```bash
nc -zv laminarflow 6443
```

From each node (best-effort UDP probe for VXLAN path):

```bash
timeout 2 bash -c 'echo > /dev/udp/<peer-node-ip>/8472'
```

From control-plane host to worker (after join):

```bash
nc -zv <worker-node-ip> 10250
```

## Firewall Guidance
- Allow cluster internal traffic for required ports/protocols between node IPs.
- Keep exposure limited to trusted LAN CIDRs.
- Record blocked-port findings in `docs/runbook.md` during validation.
