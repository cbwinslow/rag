#!/usr/bin/env bash
set -euo pipefail

# deploy_remote.sh
# Usage:
#   CF_API_TOKEN=... CF_ACCOUNT_ID=... ./deploy_remote.sh --publish-worker --publish-pages

PUBLISH_WORKER=false
PUBLISH_PAGES=false
OUTDIR=${OUTDIR:-site_dist}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish-worker) PUBLISH_WORKER=true; shift ;;
    --publish-pages) PUBLISH_PAGES=true; shift ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    *) echo "Unknown arg $1"; exit 1 ;;
  esac
done

if ! command -v wrangler >/dev/null 2>&1; then
  echo "Installing wrangler..."
  npm install -g wrangler
fi

if [ "$PUBLISH_WORKER" = true ]; then
  echo "Publishing worker..."
  wrangler publish scripts/cloudflare --env production
fi

if [ "$PUBLISH_PAGES" = true ]; then
  echo "Building pages site..."
  ./scripts/installer/build_pages_site.sh --public-key scripts/installer/example_keys/rag_deploy.pub --domain my-rag.pages.dev --outdir "$OUTDIR"
  echo "Publishing pages..."
  wrangler pages publish "$OUTDIR" --project-name rag-bootstrap --branch main
fi

echo "Deploy complete"
