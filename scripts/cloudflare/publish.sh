#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "Cloudflare publish helper for this repo"

usage(){
  cat <<EOF
Usage: $0 [--dry-run]
Options:
  --dry-run   Show what would be published but don't call Wrangler or APIs

This script prefers using the Cloudflare Wrangler CLI. If Wrangler is not
available it will print manual steps to publish assets and the worker.
EOF
}

DRY=0
if [ "${1-}" = "--dry-run" ]; then DRY=1; fi

if [ $DRY -eq 1 ]; then echo "DRY RUN: no network calls will be made"; fi

if command -v wrangler >/dev/null 2>&1; then
  echo "Found wrangler: $(wrangler --version 2>/dev/null || true)"
  if [ $DRY -eq 1 ]; then
    echo "Would run: wrangler publish --config $ROOT/scripts/cloudflare/wrangler.toml"
  else
    if [ -z "${CF_API_TOKEN-}" ]; then
      echo "CF_API_TOKEN environment variable not set. You can export it or run 'wrangler login'"
      echo "Abort: set CF_API_TOKEN or run 'wrangler login'"
      exit 2
    fi
    echo "Publishing with wrangler..."
    wrangler publish --config "$ROOT/scripts/cloudflare/wrangler.toml"
    echo "Published via wrangler."
  fi
else
  echo "wrangler not found on PATH. Manual publish instructions:";
  cat <<'MAN'
Manual publish steps (summary):
1. Create a Cloudflare Worker with the Worker UI or API.
2. Upload the worker script and set routes or worker name.
3. For asset uploads (Pages or R2), use the Cloudflare dashboard or `wrangler pages deploy`/R2 API.
4. Set secrets via `wrangler secret put` or via the dashboard (CF_API_TOKEN or per-worker secrets).
5. Test the worker endpoint and verify supabase ingest endpoints are reachable.

See: https://developers.cloudflare.com/workers/
MAN
  if [ $DRY -eq 1 ]; then echo "DRY RUN: manual instructions shown above"; fi
fi
