#!/usr/bin/env bash

# Sequential ping and SSH connectivity tester for Ansible hosts
# Usage:
#   ./ping_hosts.sh          # Defaults to pinging DNS hosts
#   ./ping_hosts.sh dns      # Ping DNS group hosts
#   ./ping_hosts.sh lan      # Ping LAN group hosts
#   ./ping_hosts.sh all      # Ping all unique hosts in inventory

TARGET="${1:-dns}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="../hosts"

if [[ ! -f "$INVENTORY_FILE" ]]; then
  echo "Error: Inventory file '$INVENTORY_FILE' not found."
  exit 1
fi

get_hosts() {
  case "$1" in
    dns)
      echo "dns01.internal.bladewdr.xyz"
      echo "dns02.internal.bladewdr.xyz"
      echo "adguard03.bladewdr.xyz"
      ;;
    lan)
      sed -n '/^\[lan\]/,/^\[/p' "$INVENTORY_FILE" | grep -v '^\[' | grep -oE '^[a-zA-Z0-9._-]+' | sort -u
      ;;
    all)
      grep -oE '^[a-zA-Z0-9._-]+' "$INVENTORY_FILE" | grep -vE '^(;|\[|nagios_|host_)' | sort -u
      ;;
    *)
      # Attempt to parse as arbitrary group name from inventory
      sed -n "/^\[$1\]/,/^\[/p" "$INVENTORY_FILE" | grep -v '^\[' | grep -oE '^[a-zA-Z0-9._-]+' | sort -u
      ;;
  esac
}

HOSTS=$(get_hosts "$TARGET")

if [[ -z "$HOSTS" ]]; then
  echo "No hosts found for target '$TARGET'."
  exit 1
fi

echo "=========================================================="
echo " Testing connectivity for target: $TARGET"
echo "=========================================================="
printf "%-35s %-15s %-15s\n" "HOST" "ICMP PING" "SSH (PORT 22)"
echo "----------------------------------------------------------"

for host in $HOSTS; do
  # 1. Test ICMP Ping (1s timeout)
  if ping -c 1 -W 1 "$host" > /dev/null 2>&1; then
    ICMP_STATUS="✅ UP"
  else
    ICMP_STATUS="❌ DOWN"
  fi

  # 2. Test SSH connection (2s timeout, key ~/.ssh/ansible, user ansible)
  if ssh -o ConnectTimeout=2 -o BatchMode=yes -o StrictHostKeyChecking=no -i ~/.ssh/ansible ansible@"$host" "echo ok" > /dev/null 2>&1; then
    SSH_STATUS="✅ OK"
  else
    SSH_STATUS="❌ FAILED"
  fi

  printf "%-35s %-15s %-15s\n" "$host" "$ICMP_STATUS" "$SSH_STATUS"
done

echo "=========================================================="
