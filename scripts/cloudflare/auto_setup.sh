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

# Source .bash_secrets if it exists to load existing secrets
if [ -f "$HOME/.bash_secrets" ]; then
  echo "Sourcing $HOME/.bash_secrets to load existing secrets"
  # shellcheck disable=SC1090
  source "$HOME/.bash_secrets"
fi

# Search for common secret name variants
find_and_export CF_API_TOKEN CF_API_TOKEN CF_TOKEN CLOUDFLARE_TOKEN WF_API_TOKEN CLOUDFLARE_API_TOKEN
find_and_export CF_ACCOUNT_ID CF_ACCOUNT_ID CLOUDFLARE_ACCOUNT_ID ACCOUNT_ID
find_and_export GOVINFO_API_KEY GOVINFO_API_KEY GOV_INFO_KEY GOVINFO GOV_INFO GOV_KEY
find_and_export AUTORAG_API_KEY AUTORAG_API_KEY AUTORAG_KEY AUTORAG API_KEY
find_and_export REPO REPO GITHUB_REPO GIT_REPO
find_and_export GITHUB_TOKEN GITHUB_TOKEN GH_TOKEN PAT_TOKEN
find_and_export DOCKER_USERNAME DOCKER_USERNAME DOCKER_USER
find_and_export DOCKER_PASSWORD DOCKER_PASSWORD DOCKER_PASS
find_and_export OPENROUTER_API_KEY OPENROUTER_API_KEY OPENROUTER_KEY
find_and_export AWS_ACCESS_KEY_ID AWS_ACCESS_KEY_ID AWS_KEY_ID
find_and_export AWS_SECRET_ACCESS_KEY AWS_SECRET_ACCESS_KEY AWS_SECRET_KEY
find_and_export POSTGRES_URL POSTGRES_URL DATABASE_URL DB_URL
find_and_export SUPABASE_URL SUPABASE_URL
find_and_export SUPABASE_ANON_KEY SUPABASE_ANON_KEY SUPABASE_KEY

# Scan common local files (if present) for exported variables and report candidate names
scan_files=("$HOME/bash_secrets" "$HOME/.bash_secrets" "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "/etc/bash_secrets" "$HOME/.env")
echo "Scanning common files for secret variable names (no values will be printed)"
for f in "${scan_files[@]}"; do
  if [ -f "$f" ]; then
    echo "Found file: $f"
    # print exported variable names only
    grep -E "^[[:space:]]*(export )?[A-Z0-9_]+=" "$f" || true
  fi
done

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

if [ -n "${SUPABASE_URL:-}" ]; then
  printf "%s" "$SUPABASE_URL" | wrangler secret put SUPABASE_URL || echo "wrangler secret put SUPABASE_URL failed"
fi
if [ -n "${SUPABASE_ANON_KEY:-}" ]; then
  printf "%s" "$SUPABASE_ANON_KEY" | wrangler secret put SUPABASE_ANON_KEY || echo "wrangler secret put SUPABASE_ANON_KEY failed"
fi

echo "Secrets set (or attempted)."

# Create Cloudflare assets if credentials are available
if [ -n "${CF_API_TOKEN:-}" ] && [ -n "${CF_ACCOUNT_ID:-}" ]; then
  echo "Creating Cloudflare assets (KV, D1, R2)..."
  if [ -f "create_cloudflare_assets.sh" ]; then
    bash create_cloudflare_assets.sh
  else
    echo "create_cloudflare_assets.sh not found, skipping asset creation"
  fi
fi

# Set up Supabase if credentials are available
if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_ANON_KEY:-}" ]; then
  echo "Setting up Supabase tables..."
  if [ -f "setup_supabase.sh" ]; then
    bash setup_supabase.sh
  else
    echo "setup_supabase.sh not found, skipping Supabase setup"
  fi
fi

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
echo ""
echo "To deploy just the install pages site:"
echo "  ./scripts/cloudflare/deploy_remote.sh --publish-pages"

echo "Done."
