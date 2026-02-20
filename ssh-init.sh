#!/usr/bin/env bash
set -euo pipefail

# SSH bootstrap / connectivity check (no Ansible required).
# - Reads ansible_user/ansible_password from hosts.ini ([linux:vars])
# - Reads hosts from [k8s_nodes] and [k8s_master]
# - Skips hosts marked with ansible_connection=local

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INV_FILE="${INV_FILE:-$SCRIPT_DIR/hosts.ini}"

usage() {
  cat <<'EOF'
Usage:
  ssh-init.sh [--list]

Examples:
  cd "$SCRIPT_DIR"
  ./ssh-init.sh
  ./ssh-init.sh --list

Env overrides:
  INV_FILE=./hosts.ini
  ANSIBLE_USER=...
  ANSIBLE_PASSWORD=...
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }
}

get_linux_var() {
  local key="$1"
  awk -F= -v k="$key" '
    BEGIN{invars=0}
    /^\[linux:vars\]/{invars=1; next}
    /^\[/{if(invars==1){exit}}
    invars==1 && $0 !~ /^[[:space:]]*#/ && $1 ~ "^[[:space:]]*"k"[[:space:]]*$" {
      v=$2
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      print v; exit
    }
  ' "$INV_FILE"
}

inventory_hosts_in_group() {
  local group="$1"
  awk -v grp="[$group]" -v gname="$group" '
    $0==grp {in_section=1; next}
    /^\[/ { if(in_section==1){ exit } }
    in_section==1 && $0 !~ /^[[:space:]]*($|#)/ {
      line=$0
      split($0,a," ")
      name=a[1]
      host=name
      if (match(line, /ansible_host=([^[:space:]]+)/, m)) host=m[1]
      localconn=0
      if (line ~ /ansible_connection=local/) localconn=1
      print gname "\t" name "\t" host "\t" localconn
    }
  ' "$INV_FILE"
}

tcp22_check() {
  local host="$1"
  # Prefer nc if available; otherwise use /dev/tcp with timeout.
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 5 "$host" 22 >/dev/null 2>&1
  else
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/${host}/22" >/dev/null 2>&1
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ "${1:-}" == "--list" ]]; then
    { inventory_hosts_in_group k8s_master; inventory_hosts_in_group k8s_nodes; } \
      | awk -F'\t' '{printf "%-10s %-10s %-18s %s\n",$1,$2,$3,($4=="1"?"(local)":"")}'
    exit 0
  fi

  if [[ ! -f "$INV_FILE" ]]; then
    echo "ERROR: inventory not found: $INV_FILE" >&2
    exit 2
  fi

  need_cmd sshpass
  need_cmd ssh
  need_cmd timeout

  local user="${ANSIBLE_USER:-$(get_linux_var ansible_user)}"
  local pass="${ANSIBLE_PASSWORD:-$(get_linux_var ansible_password)}"
  if [[ -z "${user:-}" || -z "${pass:-}" ]]; then
    echo "ERROR: Could not read ansible_user/ansible_password from $INV_FILE ([linux:vars])." >&2
    echo "You can override via ANSIBLE_USER / ANSIBLE_PASSWORD env vars." >&2
    exit 3
  fi

  echo "== SSH bootstrap check (inventory: $INV_FILE) =="
  local failures=0

  while IFS=$'\t' read -r group name host localconn; do
    [[ -z "${name:-}" ]] && continue
    if [[ "${localconn:-0}" == "1" ]]; then
      echo "-- $group: $name (local) -- SKIP"
      continue
    fi

    echo "-- $group: $name ($host) --"

    if ! tcp22_check "$host"; then
      echo "FAILED: TCP/22 not reachable: $name ($host)" >&2
      failures=$((failures+1))
      continue
    fi

    # Force password auth and avoid prompts.
    SSHPASS="$pass" sshpass -e ssh -n \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      -o ConnectTimeout=10 \
      "${user}@${host}" -- 'echo connected' </dev/null >/dev/null \
      || { echo "FAILED: SSH auth/exec failed: $name ($host)" >&2; failures=$((failures+1)); }
  done < <({ inventory_hosts_in_group k8s_master; inventory_hosts_in_group k8s_nodes; })

  if [[ "$failures" -gt 0 ]]; then
    echo "ERROR: ssh-init failed on $failures host(s)." >&2
    exit 10
  fi

  echo "OK: all hosts reachable and SSH auth succeeded."
}

main "$@"


