#!/usr/bin/env bash
set -euo pipefail

# wrangler_auth_helper.sh
# If CF_API_TOKEN is present in env, configure wrangler to use it non-interactively.
# This script writes a minimal ~/.wrangler/config/default.toml for wrangler v3 if needed.

if [ -z "${CF_API_TOKEN:-}" ]; then
  echo "CF_API_TOKEN not set. Use 'wrangler login' to authenticate interactively or export CF_API_TOKEN and rerun."
  exit 1
fi

WRANGLER_CFG_DIR="$HOME/.wrangler"
mkdir -p "$WRANGLER_CFG_DIR"
CFG_FILE="$WRANGLER_CFG_DIR/config/default.toml"
mkdir -p "$(dirname "$CFG_FILE")"

cat > "$CFG_FILE" <<EOF
[http]
token = "$CF_API_TOKEN"
EOF

echo "Wrote wrangler config to $CFG_FILE (wrangler will use CF_API_TOKEN)."
