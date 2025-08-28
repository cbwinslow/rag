#!/usr/bin/env bash
set -euo pipefail

# auto_setup.sh
# Automate local setup: install wrangler, write Worker secrets, optionally set GitHub repo secrets, and publish.
#
# USAGE (recommended): run locally, not on the server:
#   CF_API_TOKEN=... CF_ACCOUNT_ID=... GOVINFO_API_KEY=... AUTORAG_API_KEY=... REPO=owner/repo ./scripts/cloudflare/auto_setup.sh
# Or run interactively and the script will prompt for missing values.


# Find a value from multiple possible env names and export to canonical name
find_and_export(){
  local canonical="$1";
  shift
  local candidates=("$@")
  local val=""
  for n in "${candidates[@]}"; do
    if [ -n "${!n:-}" ]; then
      val="${!n}"
      echo "Found $n in environment; using for $canonical"
      break
    fi
  done
  # fallback: ask interactively
  if [ -z "$val" ]; then
    read -r -p "Enter value for $canonical (leave empty to skip): " val
  fi
  if [ -n "$val" ]; then
    export "$canonical"="$val"
  fi
}

echo "Auto-setup for Cloudflare & GitHub secrets (searching common env name variants)"

# Search for common secret name variants
find_and_export CF_API_TOKEN CF_API_TOKEN CF_TOKEN CLOUDFLARE_TOKEN WF_API_TOKEN
find_and_export CF_ACCOUNT_ID CF_ACCOUNT_ID CLOUDFLARE_ACCOUNT_ID ACCOUNT_ID
find_and_export GOVINFO_API_KEY GOVINFO_API_KEY GOV_INFO_KEY GOVINFO GOV_INFO GOV_KEY
find_and_export AUTORAG_API_KEY AUTORAG_API_KEY AUTORAG_KEY AUTORAG API_KEY
find_and_export REPO REPO GITHUB_REPO GIT_REPO

# Ensure node/npm present for wrangler
if ! command -v wrangler >/dev/null 2>&1; then
  if command -v npm >/dev/null 2>&1; then
    echo "Installing wrangler via npm"
    npm install -g wrangler
  else
    echo "npm not found. Please install Node.js/npm and re-run this script." >&2
    exit 1
  fi
fi

if [ -z "${CF_API_TOKEN:-}" ] || [ -z "${CF_ACCOUNT_ID:-}" ]; then
  echo "CF_API_TOKEN or CF_ACCOUNT_ID missing. You can still write worker secrets using wrangler if logged in." 
fi

cd scripts/cloudflare || exit 1

echo "Writing Worker secrets (wrangler secret put). This requires that wrangler is authenticated or CF_API_TOKEN is configured."

if [ -n "${GOVINFO_API_KEY:-}" ]; then
  printf "%s" "$GOVINFO_API_KEY" | wrangler secret put GOVINFO_API_KEY || echo "wrangler secret put GOVINFO_API_KEY failed"
fi
if [ -n "${AUTORAG_API_KEY:-}" ]; then
  printf "%s" "$AUTORAG_API_KEY" | wrangler secret put AUTORAG_API_KEY || echo "wrangler secret put AUTORAG_API_KEY failed"
fi

echo "Secrets set (or attempted)."

cd - >/dev/null || true

if command -v gh >/dev/null 2>&1 && [ -n "${REPO:-}" ]; then
  echo "Setting GitHub repository secrets using gh for repository $REPO"
  if [ -n "${CF_API_TOKEN:-}" ]; then
    echo "$CF_API_TOKEN" | gh secret set CF_API_TOKEN -R "$REPO" --body - || echo "gh secret set CF_API_TOKEN failed"
  fi
  if [ -n "${CF_ACCOUNT_ID:-}" ]; then
    echo "$CF_ACCOUNT_ID" | gh secret set CF_ACCOUNT_ID -R "$REPO" --body - || echo "gh secret set CF_ACCOUNT_ID failed"
  fi
  if [ -n "${GOVINFO_API_KEY:-}" ]; then
    echo "$GOVINFO_API_KEY" | gh secret set GOVINFO_API_KEY -R "$REPO" --body - || echo "gh secret set GOVINFO_API_KEY failed"
  fi
  if [ -n "${AUTORAG_API_KEY:-}" ]; then
    echo "$AUTORAG_API_KEY" | gh secret set AUTORAG_API_KEY -R "$REPO" --body - || echo "gh secret set AUTORAG_API_KEY failed"
  fi
else
  echo "gh CLI not available or REPO not set; skipping GitHub secrets. Install gh and authenticate (gh auth login) to enable this step." 
fi

echo "Optionally publish now. To publish worker and pages run:"
echo "  CF_API_TOKEN=... CF_ACCOUNT_ID=... ./scripts/cloudflare/deploy_remote.sh --publish-worker --publish-pages"

echo "Done."
