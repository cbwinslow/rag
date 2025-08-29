#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_BIN="$(command -v node || true)"
if [[ -z "$NODE_BIN" ]]; then
  echo "Node.js not found. Please install Node.js (v16+ recommended)." >&2
  exit 2
fi
node "$SCRIPT_DIR/collect_assets.js"
