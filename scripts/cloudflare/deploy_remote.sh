#!/usr/bin/env bash
set -euo pipefail

# deploy_remote.sh
# Usage:
#   CF_API_TOKEN=... CF_ACCOUNT_ID=... ./deploy_remote.sh --publish-worker --publish-pages --publish-rag-api --publish-docs

PUBLISH_WORKER=false
PUBLISH_PAGES=false
PUBLISH_RAG_API=false
PUBLISH_DOCS=false
OUTDIR=${OUTDIR:-site_dist}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish-worker) PUBLISH_WORKER=true; shift ;;
    --publish-pages) PUBLISH_PAGES=true; shift ;;
    --publish-rag-api) PUBLISH_RAG_API=true; shift ;;
    --publish-docs) PUBLISH_DOCS=true; shift ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    *) echo "Unknown arg $1"; exit 1 ;;
  esac
done

if ! command -v wrangler >/dev/null 2>&1; then
  echo "Installing wrangler..."
  npm install -g wrangler
fi

if [ "$PUBLISH_WORKER" = true ]; then
  echo "Publishing main worker..."
  wrangler publish scripts/cloudflare --env production
fi

if [ "$PUBLISH_RAG_API" = true ]; then
  echo "Publishing RAG API worker..."
  wrangler publish scripts/cloudflare/rag-api-worker.js --config scripts/cloudflare/rag-api-wrangler.toml --env production
fi

if [ "$PUBLISH_DOCS" = true ]; then
  echo "Publishing documentation site..."
  wrangler pages publish scripts/cloudflare/docs-site --project-name rag-docs --branch main
fi

if [ "$PUBLISH_PAGES" = true ]; then
  echo "Publishing install pages site..."
  cd scripts/cloudflare/pages-site
  wrangler pages deploy . --project-name rag-install --branch main
  cd ../../..
fi

echo "Deploy complete"
