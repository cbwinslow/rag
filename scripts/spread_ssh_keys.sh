#!/usr/bin/env bash
set -euo pipefail

# spread_ssh_keys.sh
# Distribute an SSH public key to a list of hosts (append to authorized_keys)
# Supports reading hosts from a file or CLI args, and supports SSH key forwarding or specifying a private key

usage(){
  cat <<EOF
Usage: $0 [options] [host1 host2 ...]

Options:
  --hosts-file FILE     File with host (one per line) optionally user@host
  --user USER           Default SSH user
  --ssh-key KEY         SSH private key to use to connect to hosts
  --pubkey FILE         Public key file to distribute (default ~/.ssh/id_rsa.pub)
  --port PORT           SSH port (default 22)
  -h, --help            Show this help

Examples:
  ./scripts/spread_ssh_keys.sh --hosts-file hosts.txt --user root --ssh-key ~/.ssh/id_rsa
  ./scripts/spread_ssh_keys.sh host1.example.com host2.example.com

This script will attempt to copy the specified public key to each host's ~/.ssh/authorized_keys (creating dirs and files as needed).
It uses SSH to run remote commands; disabling strict host key checking for convenience (change as needed).
EOF
}

HOSTS_FILE=""
USER=""
SSH_KEY=""
PUBKEY_FILE="${HOME}/.ssh/id_rsa.pub"
PORT=22
ANSIBLE=false
TEMP_INVENTORY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hosts-file) HOSTS_FILE="$2"; shift 2;;
    --user) USER="$2"; shift 2;;
    --ssh-key) SSH_KEY="$2"; shift 2;;
    --pubkey) PUBKEY_FILE="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
  --ansible) ANSIBLE=true; shift;;
  -h|--help) usage; exit 0;;
  *) HOSTS+=("$1"); shift;;
  esac
done

if [ -n "$HOSTS_FILE" ]; then
  mapfile -t FILE_HOSTS < "$HOSTS_FILE"
  HOSTS=("${FILE_HOSTS[@]}")
fi

if [ "$ANSIBLE" = true ]; then
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "ansible-playbook not found; please install ansible-core or unset --ansible" >&2
    exit 2
  fi
  TEMP_INVENTORY=$(mktemp)
  for h in "${HOSTS[@]}"; do
    echo "$h" >> "$TEMP_INVENTORY"
  done
  echo "Using temp inventory $TEMP_INVENTORY"
  ansible-playbook -i "$TEMP_INVENTORY," scripts/ansible/ssh_key_distribute.yaml --extra-vars "pubkey_path=${PUBKEY_FILE}"
  rm -f "$TEMP_INVENTORY"
  echo "Ansible distribution complete"
  exit 0
fi

if [ ${#HOSTS[@]} -eq 0 ]; then
  echo "No hosts provided"; usage; exit 2
fi

if [ -z "$USER" ]; then USER=$(whoami); fi

if [ ! -f "$PUBKEY_FILE" ]; then echo "Public key not found at $PUBKEY_FILE"; exit 2; fi
PUBKEY_CONTENT=$(cat "$PUBKEY_FILE")

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $PORT"
if [ -n "$SSH_KEY" ]; then SSH_OPTS="$SSH_OPTS -i $SSH_KEY"; fi

for h in "${HOSTS[@]}"; do
  # allow user@host in list
  if [[ "$h" == *@* ]]; then
    tgt="$h"
  else
    tgt="$USER@$h"
  fi
  echo "Copying public key to $tgt"
  ssh $SSH_OPTS "$tgt" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && grep -qxF '$PUBKEY_CONTENT' ~/.ssh/authorized_keys || echo '$PUBKEY_CONTENT' >> ~/.ssh/authorized_keys"
done

echo "Done. You can test passwordless SSH: ssh $USER@<host>"

exit 0
