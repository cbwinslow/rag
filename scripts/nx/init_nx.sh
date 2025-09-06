#!/usr/bin/env bash
set -euo pipefail
echo "This script initializes an Nx workspace in this repository."
echo "It will run: npx nx init --preserve-existing-files"
echo "You should review changes and run your package manager to install dev dependencies."

if ! command -v npx >/dev/null 2>&1; then
  echo "npx not found. Install Node.js and npm first."
  exit 2
fi

read -p "Proceed with npx nx init in this repo? (y/N) " -r
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  npx --yes nx init --preserve-existing-files
  echo "Nx init completed. Install node deps (npm install) and then run the Codacy trivy scan per repo policy."
else
  echo "Canceled. No changes made."
fi
