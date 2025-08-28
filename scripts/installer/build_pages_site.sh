#!/usr/bin/env bash
set -euo pipefail

# build_pages_site.sh
# Collect files for Cloudflare Pages site into ./dist
# Usage:
#   ./build_pages_site.sh --public-key /path/to/rag_deploy.pub --domain example.pages.dev

OUTDIR="dist"
PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-}"
DOMAIN_PLACEHOLDER="example.pages.dev"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-key) PUBLIC_KEY_PATH="$2"; shift 2 ;;
    --domain) DOMAIN_PLACEHOLDER="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 --public-key /path/to/pub --domain your.pages.dev"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

mkdir -p "$OUTDIR/keys"

if [ -n "$PUBLIC_KEY_PATH" ]; then
  if [ ! -f "$PUBLIC_KEY_PATH" ]; then
    echo "Public key file not found: $PUBLIC_KEY_PATH"; exit 1
  fi
  cp "$PUBLIC_KEY_PATH" "$OUTDIR/keys/rag_deploy.pub"
else
  echo "No public key provided; creating placeholder pub key file"
  cat > "$OUTDIR/keys/rag_deploy.pub" <<'PUB'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBEXAMPLEKEYPLACEHOLDER user@example.com
PUB
fi

# Copy installer and index.html, replace domain placeholder
cp scripts/installer/post_install.sh "$OUTDIR/post_install.sh"
chmod +x "$OUTDIR/post_install.sh"

INDEX_SRC="scripts/installer/cloudflare_pages_template/index.html"
INDEX_DST="$OUTDIR/index.html"
if [ -f "$INDEX_SRC" ]; then
  sed "s|example.pages.dev|$DOMAIN_PLACEHOLDER|g" "$INDEX_SRC" > "$INDEX_DST"
else
  echo "Missing template index.html at $INDEX_SRC"; exit 1
fi

tar -C "$OUTDIR" -czf "${OUTDIR}.tar.gz" .
echo "Built Pages bundle at ${OUTDIR}.tar.gz. Upload the extracted contents to Cloudflare Pages."
