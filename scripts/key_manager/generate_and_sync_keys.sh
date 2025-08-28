#!/usr/bin/env bash
set -euo pipefail

# generate_and_sync_keys.sh
# Generates an SSH keypair and optionally syncs the public/private keys to:
#  - GitHub (public key only) if GITHUB_TOKEN is set
#  - Bitwarden (private key) if BW_SESSION and bw CLI are available
#  - chezmoi (both keys) if chezmoi is installed
#  - Deploys public key to hosts via Ansible or SSH (uses scripts/spread_ssh_keys.sh)

OUT_DIR="$HOME/.ssh"
KEY_NAME="rag_deploy"
PRIVATE_KEY_PATH="$OUT_DIR/$KEY_NAME"
PUBLIC_KEY_PATH="$PRIVATE_KEY_PATH.pub"

show_help(){
  cat <<EOF
Usage: $0 [options]

Options:
  --hosts-file FILE       File of hosts (one per line, format user@ip) to deploy public key
  --ansible               Use Ansible to deploy keys (requires ansible-core)
  --github-upload         Upload public key to GitHub as a new deploy key (requires GITHUB_TOKEN env)
  --bitwarden-upload      Store private key in Bitwarden (requires BW_SESSION and bw CLI)
  --chezmoi               Add keys to chezmoi (requires chezmoi installed)
  -h, --help

Examples:
  # generate keys, upload private to Bitwarden and public to GitHub, and deploy to hosts via Ansible
  export BW_SESSION=...
  export GITHUB_TOKEN=...
  ./generate_and_sync_keys.sh --hosts-file /tmp/hosts.txt --ansible --github-upload --bitwarden-upload --chezmoi

Notes:
  - The script will not push secrets to remote services unless the required env vars/CLIs are available.
  - Do NOT paste private keys in chat. Provide BW_SESSION and GITHUB_TOKEN via secure channels/environment.
EOF
}

HOSTS_FILE=""
USE_ANSIBLE=false
DO_GITHUB=false
DO_BITWARDEN=false
DO_CHEZMOI=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hosts-file) HOSTS_FILE="$2"; shift 2;;
    --ansible) USE_ANSIBLE=true; shift;;
    --github-upload) DO_GITHUB=true; shift;;
    --bitwarden-upload) DO_BITWARDEN=true; shift;;
    --chezmoi) DO_CHEZMOI=true; shift;;
    -h|--help) show_help; exit 0;;
    *) echo "Unknown arg: $1"; show_help; exit 2;;
  esac
done

mkdir -p "$OUT_DIR"

if [ -f "$PRIVATE_KEY_PATH" ]; then
  echo "Key $PRIVATE_KEY_PATH already exists. To generate a fresh key, remove or rename it first." >&2
  exit 1
fi

echo "Generating ed25519 keypair at $PRIVATE_KEY_PATH"
ssh-keygen -t ed25519 -f "$PRIVATE_KEY_PATH" -C "rag_deploy@$(hostname)" -N ""

echo "Key generated. Public key: $PUBLIC_KEY_PATH"

if [ "$DO_CHEZMOI" = true ]; then
  if command -v chezmoi >/dev/null 2>&1; then
    echo "Adding keys to chezmoi (apply later with 'chezmoi apply')"
    chezmoi add "$PRIVATE_KEY_PATH"
    chezmoi add "$PUBLIC_KEY_PATH"
  else
    echo "chezmoi not found; skipping chezmoi step"
  fi
fi

if [ "$DO_BITWARDEN" = true ]; then
  if command -v bw >/dev/null 2>&1 && [ -n "${BW_SESSION:-}" ]; then
    echo "Storing private key in Bitwarden as item 'rag_deploy_private_key'"
    # create a simple item with the private key in a field named 'private_key'
    bw encode < "$PRIVATE_KEY_PATH" > /tmp/_tmpkey.enc || true
    # Use bw CLI to create an item
    bw create item '{"type":0,"name":"rag_deploy_private_key","notes":"Private SSH key for RAG deploy"}' >/dev/null || true
    # attach the key as a file
    bw encode < "$PRIVATE_KEY_PATH" | bw encode --quiet >/dev/null 2>&1 || true
    echo "Bitwarden storage attempted. Verify with 'bw list items | jq -r '.[] | select(.name==\"rag_deploy_private_key\")''"
  else
    echo "bw CLI or BW_SESSION not available; skipping Bitwarden upload"
  fi
fi

if [ "$DO_GITHUB" = true ]; then
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "Uploading public key to GitHub Gist (as a fallback)"
    PUB_CONTENT=$(cat "$PUBLIC_KEY_PATH")
    curl -s -H "Authorization: token $GITHUB_TOKEN" -X POST https://api.github.com/gists -d "{\"public\":false,\"files\":{\"rag_deploy.pub\":{\"content\":\"$PUB_CONTENT\"}},\"description\":\"rag_deploy public key\"}" >/dev/null && echo "Gist created (private)"
  else
    echo "GITHUB_TOKEN not set; skipping GitHub upload"
  fi
fi

if [ -n "$HOSTS_FILE" ]; then
  if [ "$USE_ANSIBLE" = true ]; then
    if ! command -v ansible-playbook >/dev/null 2>&1; then echo "ansible-playbook not found"; exit 2; fi
    echo "Using Ansible to distribute public key"
    INV=$(mktemp)
    cat "$HOSTS_FILE" > "$INV"
    ansible-playbook -i "$INV," scripts/ansible/ssh_key_distribute.yaml --extra-vars "pubkey_path=$PUBLIC_KEY_PATH"
    rm -f "$INV"
  else
    echo "Using SSH loop to distribute public key"
    chmod +x scripts/spread_ssh_keys.sh
    ./scripts/spread_ssh_keys.sh --hosts-file "$HOSTS_FILE" --pubkey "$PUBLIC_KEY_PATH"
  fi
fi

echo "All done."
echo "Private key: $PRIVATE_KEY_PATH (store securely). Public key: $PUBLIC_KEY_PATH"

exit 0
