#!/usr/bin/env bash
set -euo pipefail

# bitwarden_chezmoi_key_sync.sh
# Template: fetch a public SSH key from Bitwarden (via bw CLI) and add it to chezmoi-managed dotfiles.
# Requires: bw (Bitwarden CLI) logged in with session export, and chezmoi installed.

if ! command -v bw >/dev/null 2>&1; then
  echo "bw (Bitwarden CLI) not found"; exit 1
fi
if ! command -v chezmoi >/dev/null 2>&1; then
  echo "chezmoi not found"; exit 1
fi

ITEM_ID=""
FIELD_NAME="public_key"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <bitwarden-item-id-or-name> [field_name]"; exit 1
fi
ITEM_ID="$1"
if [ $# -ge 2 ]; then FIELD_NAME="$2"; fi

# Ensure BW session
if [ -z "${BW_SESSION:-}" ]; then
  echo "Please authenticate to Bitwarden first: bw login and export BW_SESSION. Aborting."; exit 1
fi

echo "Fetching key from Bitwarden item '$ITEM_ID' field '$FIELD_NAME'"
KEY_CONTENT=$(bw get item "$ITEM_ID" | jq -r ".fields[] | select(.name==\"$FIELD_NAME\") | .value")
if [ -z "$KEY_CONTENT" ]; then
  echo "No key found in that field"; exit 1
fi

TARGET_PATH="~/.ssh/id_rsa.pub"
chezmoi add --source-path <(printf "%s" "$KEY_CONTENT") --dest "$TARGET_PATH" || true
echo "Added public key to chezmoi at $TARGET_PATH; run 'chezmoi apply' to install"
