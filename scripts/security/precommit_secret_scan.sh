#!/usr/bin/env bash
# Lightweight pre-commit secret scanner for common env names and patterns.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

patterns=("CF_API_TOKEN" "CF_ACCOUNT_ID" "SUPABASE_ANON_KEY" "JWT_SECRET" "NGC_API_KEY" "AUTORAG_API_KEY")
exit_code=0
for p in "${patterns[@]}"; do
  if git diff --cached --name-only | xargs -r grep -In -- "${p}" >/dev/null 2>&1; then
    echo "Potential secret pattern '${p}' found in staged files. Please remove secrets and use env vars or secrets manager."
    exit_code=2
  fi
done

if [ $exit_code -ne 0 ]; then
  echo "Secret scan failed"
  exit $exit_code
fi

echo "Secret scan passed"
exit 0
