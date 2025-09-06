#!/usr/bin/env bash
set -euo pipefail
echo "Nx MCP quick check"

if command -v npx >/dev/null 2>&1; then
  echo "npx available: $(npx --version)"
else
  echo "npx not found. Install Node.js/npm and try again."
  exit 2
fi

if npx --yes nx --version >/dev/null 2>&1; then
  echo "nx CLI detected: $(npx --yes nx --version 2>/dev/null)"
  echo "If you add Nx workspace files (nx.json, workspace.json, project.json), install the Nx Console extension in your editor to enable MCP server integration."
  exit 0
else
  echo "nx CLI not present in your node installation. That's fine for now; the repo is not an Nx workspace."
  echo "When you convert the repo, run: npx nx init";
  exit 0
fi
