#!/usr/bin/env bash
#
# shutdown-cluster.sh - gracefully power off the whole Kubernetes/Talos
# cluster from the controller host.
#
# Talos has no QEMU guest agent and does not handle ACPI shutdown signals, so
# `qm shutdown` on Proxmox will not work; the graceful path is the Talos API:
# `talosctl shutdown` (cordon/drain happened first, then services are stopped
# in order and the VM powers itself off).
#
# Order: worker nodes first, control-plane nodes one at a time (etcd quorum
# is preserved: 3 control planes -> always >=2 alive while stopping each one).
#
# Defaults (all discovered from the applied OpenTofu state / the cluster):
#   kubeconfig  <repo>/kubeconfig.yaml
#   talosconfig <repo>/talosconfig, or generated on the fly from
#               `tofu output -raw talos_config` into a temp file
#   node IPs    OpenTofu outputs controlplane_ips / worker_ips
#   node names  kubectl labels node-role.kubernetes.io/{control-plane,worker}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KUBECONFIG="${REPO_ROOT}/kubeconfig.yaml"
TALOSCONFIG="${REPO_ROOT}/talosconfig"
DRAIN_TIMEOUT="300s"
DRY_RUN=""
NO_DRAIN=""
FORCE=""
TMP_TALOS=""

usage() {
  cat <<'EOF'
Usage: shutdown-cluster.sh [options]

Gracefully power off every Talos node (workers first, then control planes one
at a time): drain each node from Kubernetes, then `talosctl shutdown --wait`.
Talos ignores ACPI, so `qm shutdown` on Proxmox will not stop the VMs.

Options:
  --dry-run             Print the commands that would run; do not execute them.
  --no-drain            Skip `kubectl drain` before shutting each node.
  --force               Pass --force to talosctl (skip graceful drain wait).
  --kubeconfig <path>   Kubeconfig for kubectl.
                        Default: <repo>/kubeconfig.yaml
  --talosconfig <path>  talosconfig for talosctl. If missing, it is generated
                        from `tofu output -raw talos_config` into a temp file.
  --drain-timeout <t>   kubectl drain --timeout. Default: 300s
  -h, --help            Show this help.
EOF
}

cleanup() {
  if [[ -n "$TMP_TALOS" ]]; then rm -f "$TMP_TALOS"; fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=1; shift ;;
    --no-drain)       NO_DRAIN=1; shift ;;
    --force)          FORCE=1; shift ;;
    --kubeconfig)     KUBECONFIG="$2"; shift 2 ;;
    --talosconfig)    TALOSCONFIG="$2"; shift 2 ;;
    --drain-timeout)  DRAIN_TIMEOUT="$2"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for bin in tofu kubectl talosctl; do
  command -v "$bin" >/dev/null 2>&1 \
    || { echo "error: '$bin' not found in PATH" >&2; exit 1; }
done

[[ -f "$KUBECONFIG" ]] || {
  echo "error: kubeconfig not found at ${KUBECONFIG}" >&2
  echo "       run 'scripts/export-kubeconfig.sh' first" >&2
  exit 1
}

# Read a list output (tuple) from the state as whitespace-separated values.
read_ip_list() {
  local name="$1"
  local value
  value="$(cd "$REPO_ROOT" && tofu output -json "$name")" || {
    echo "error: cannot read OpenTofu output '$name' (run 'tofu apply' first?)" >&2
    exit 1
  }
  # ["192.168.15.225","192.168.15.226"] -> "192.168.15.225 192.168.15.226"
  printf '%s' "$value" | tr -d '[]\" ' | tr ',' ' '
}

node_names_by_role() {
  local role="$1"
  kubectl --kubeconfig "$KUBECONFIG" get nodes \
    -l "node-role.kubernetes.io/${role}" \
    -o jsonpath='{.items[*].metadata.name}'
}

run() {
  if [[ -n "$DRY_RUN" ]]; then
    printf '  %s\n' "$*"
  else
    printf '+ %s\n' "$*"
    "$@"
  fi
}

drain_node() {
  local name="$1"
  run kubectl --kubeconfig "$KUBECONFIG" drain "$name" \
    --ignore-daemonsets --delete-emptydir-data --timeout="$DRAIN_TIMEOUT"
}

shutdown_node() {
  local ip="$1"
  local extra=()
  [[ -n "$FORCE" ]] && extra+=(--force)
  run talosctl --talosconfig "$TALOSCONFIG" -n "$ip" shutdown "${extra[@]}" --wait
}

# talosconfig: use the explicit path, or generate one from OpenTofu state.
if [[ ! -f "$TALOSCONFIG" ]]; then
  TMP_TALOS="$(mktemp)"
  (cd "$REPO_ROOT" && tofu output -raw talos_config) > "$TMP_TALOS"
  chmod 600 "$TMP_TALOS"
  TALOSCONFIG="$TMP_TALOS"
  echo "talosconfig: generated from OpenTofu state (temp file)"
else
  echo "talosconfig: ${TALOSCONFIG}"
fi
echo "kubeconfig:  ${KUBECONFIG}"

WORKER_IPS="$(read_ip_list worker_ips)"
CONTROLPLANE_IPS="$(read_ip_list controlplane_ips)"
WORKERS="$(node_names_by_role worker)"
CONTROL_PLANES="$(node_names_by_role control-plane)"

[[ -n "$WORKERS" ]] || { echo "error: no worker nodes found (label node-role.kubernetes.io/worker)" >&2; exit 1; }
[[ -n "$CONTROL_PLANES" ]] || { echo "error: no control-plane nodes found" >&2; exit 1; }

echo
echo "Workers:"
for n in $WORKERS; do echo "  ${n}"; done
echo "Control planes:"
for n in $CONTROL_PLANES; do echo "  ${n}"; done
echo

if [[ -z "$NO_DRAIN" ]]; then
  echo "== Draining workers =="
  for n in $WORKERS; do drain_node "$n"; done
fi
echo "== Shutting down workers =="
for ip in $WORKER_IPS; do shutdown_node "$ip"; done

if [[ -z "$NO_DRAIN" ]]; then
  echo "== Draining control planes (one at a time) =="
  for n in $CONTROL_PLANES; do drain_node "$n"; done
fi
echo "== Shutting down control planes (one at a time, preserves etcd quorum) =="
for ip in $CONTROLPLANE_IPS; do shutdown_node "$ip"; done

if [[ -n "$DRY_RUN" ]]; then
  echo
  echo "Dry-run only - nothing was executed."
else
  echo
  echo "Cluster powered off. Start it back with 'qm start <vmid>' on Proxmox."
fi