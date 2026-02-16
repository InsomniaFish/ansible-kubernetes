#!/usr/bin/env bash
set -euo pipefail

# Generate an inventory file for an arbitrary master + worker nodes.
# Useful when you want to create a K8s cluster from any set of node IPs.

OUT_FILE="${OUT_FILE:-/root/ansible/hosts.generated.ini}"

usage() {
  cat <<'EOF'
Usage:
  gen_inventory.sh --master <master_ip> --nodes <ip1,ip2,...> [--user <u>] [--password <p>] [--out <file>]

Examples:
  ./gen_inventory.sh --master 192.168.48.100 --nodes 192.168.48.101,192.168.48.102 --user root --password 'elysia123.'
  ./gen_inventory.sh --master 10.0.0.10 --nodes 10.0.0.11 --out /root/ansible/hosts.any.ini

Notes:
  - If master_ip matches a local IPv4 on this machine, master01 will be set to ansible_connection=local.
  - This writes ansible_password in plaintext; for production use SSH keys or Ansible Vault.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

master_ip=""
nodes_csv=""
user="root"
password=""
out="$OUT_FILE"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --master) master_ip="${2:-}"; shift 2;;
    --nodes) nodes_csv="${2:-}"; shift 2;;
    --user) user="${2:-}"; shift 2;;
    --password) password="${2:-}"; shift 2;;
    --out) out="${2:-}"; shift 2;;
    *) die "Unknown arg: $1";;
  esac
done

[[ -n "$master_ip" ]] || die "--master is required"
[[ -n "$nodes_csv" ]] || die "--nodes is required"

# Determine if master is local.
local_ips="$(hostname -I 2>/dev/null | tr ' ' '\n' | sed '/^$/d' || true)"
master_local="0"
if echo "$local_ips" | grep -qx "$master_ip"; then
  master_local="1"
fi

IFS=',' read -r -a node_ips <<<"$nodes_csv"
[[ "${#node_ips[@]}" -ge 1 ]] || die "No nodes parsed from --nodes"

mkdir -p "$(dirname "$out")"

{
  echo "[k8s_master]"
  if [[ "$master_local" == "1" ]]; then
    echo "master01 ansible_host=${master_ip} ansible_connection=local"
  else
    echo "master01 ansible_host=${master_ip}"
  fi
  echo
  echo "[k8s_nodes]"
  i=1
  for ip in "${node_ips[@]}"; do
    ip="$(echo "$ip" | xargs)"
    [[ -n "$ip" ]] || continue
    printf "node%02d ansible_host=%s\n" "$i" "$ip"
    i=$((i+1))
  done
  echo
  echo "[k8s_cluster:children]"
  echo "k8s_master"
  echo "k8s_nodes"
  echo
  echo "[linux:children]"
  echo "k8s_cluster"
  echo
  echo "[linux:vars]"
  echo "ansible_user=${user}"
  if [[ -n "$password" ]]; then
    echo "ansible_password=${password}"
  else
    echo "# ansible_password=YOUR_PASSWORD"
  fi
} > "$out"

echo "Wrote inventory: $out"
echo
echo "Next:"
echo "  INV_FILE=$out ./ssh-init.sh"
echo "  ansible-playbook -i $out k8s-cluster.yaml"


