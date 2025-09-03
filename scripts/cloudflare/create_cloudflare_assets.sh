#!/usr/bin/env bash
set -euo pipefail

# create_cloudflare_assets.sh
# Create or reuse necessary Cloudflare assets for the RAG system
# Requires: CF_API_TOKEN, CF_ACCOUNT_ID

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DATA_DIR="$BASE_DIR/data"
WRANGLER_FILE="$BASE_DIR/scripts/cloudflare/wrangler.toml"

echo "[info] Cloudflare assets script starting (BASE_DIR=$BASE_DIR)"

# tool checks
for bin in curl jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Error: $bin is required but not installed. Install and retry."
    exit 1
  fi
done

# Check for required environment variables
if [ -z "${CF_API_TOKEN:-}" ] || [ -z "${CF_ACCOUNT_ID:-}" ]; then
  echo "Error: CF_API_TOKEN and CF_ACCOUNT_ID must be set"
  exit 1
fi

API_HDR=( -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" )

mkdir -p "$DATA_DIR"

reuse_or_create_kv() {
  local title="$1"
  echo "[info] ensuring KV namespace '$title'"
  # try to find existing namespace
  local list
  list=$(curl -sS "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces" "${API_HDR[@]}")
  local existing
  existing=$(echo "$list" | jq -r --arg t "$title" '.result[] | select(.title==$t) | .id' | head -n1 || true)
  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    echo "[info] found existing KV namespace: $existing"
    echo "$existing"
    return 0
  fi

  local resp
  resp=$(curl -sS -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces" "${API_HDR[@]}" --data "{\"title\": \"$title\"}")
  local id
  id=$(echo "$resp" | jq -r '.result.id // empty') || true
  if [ -n "$id" ]; then
    echo "[info] created KV namespace: $id"
    echo "$id"
    return 0
  fi
  echo "[warn] failed to create KV namespace; response: $resp"
  return 1
}

reuse_or_create_d1() {
  local name="$1"
  echo "[info] ensuring D1 database '$name'"
  local list
  list=$(curl -sS "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/d1/database" "${API_HDR[@]}" || true)
  local existing
  existing=$(echo "$list" | jq -r --arg n "$name" '.result[] | select(.name==$n) | .uuid' | head -n1 || true)
  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    echo "[info] found existing D1 database: $existing"
    echo "$existing"
    return 0
  fi
  local resp
  resp=$(curl -sS -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/d1/database" "${API_HDR[@]}" --data "{\"name\": \"$name\"}" || true)
  local id
  id=$(echo "$resp" | jq -r '.result.uuid // empty' || true)
  if [ -n "$id" ]; then
    echo "[info] created D1 database: $id"
    echo "$id"
    return 0
  fi
  echo "[warn] failed to create D1 database; response: $resp"
  return 1
}

reuse_or_create_r2() {
  local bucket_name="$1"
  echo "[info] ensuring R2 bucket '$bucket_name'"
  local list
  list=$(curl -sS "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/r2/buckets" "${API_HDR[@]}" || true)
  local existing
  existing=$(echo "$list" | jq -r --arg b "$bucket_name" '.result[] | select(.name==$b) | .id' | head -n1 || true)
  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    echo "[info] found existing R2 bucket: $existing"
    echo "$existing"
    return 0
  fi
  local resp
  resp=$(curl -sS -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/r2/buckets" "${API_HDR[@]}" --data "{\"name\": \"$bucket_name\"}" || true)
  local id
  id=$(echo "$resp" | jq -r '.result.id // empty' || true)
  if [ -n "$id" ]; then
    echo "[info] created R2 bucket: $id"
    echo "$id"
    return 0
  fi
  echo "[warn] failed to create R2 bucket; response: $resp"
  return 1
}

echo "[info] creating or reusing assets (this may be idempotent)"
KV_ID=$(reuse_or_create_kv "rag-autorag-kv") || true
D1_ID=$(reuse_or_create_d1 "rag_documents") || true
R2_ID=$(reuse_or_create_r2 "rag-documents") || true

echo "[info] KV_ID=$KV_ID D1_ID=$D1_ID R2_ID=$R2_ID"

# Update wrangler.toml placeholders if present
if [ -f "$WRANGLER_FILE" ]; then
  echo "[info] updating $WRANGLER_FILE with asset ids"
  [ -n "$KV_ID" ] && sed -i "s/YOUR_AUTORAG_KV_ID/$KV_ID/g" "$WRANGLER_FILE" || true
  [ -n "$D1_ID" ] && sed -i "s/YOUR_D1_DATABASE_ID/$D1_ID/g" "$WRANGLER_FILE" || true
  [ -n "$R2_ID" ] && sed -i "s/YOUR_R2_BUCKET_ID/$R2_ID/g" "$WRANGLER_FILE" || true
fi

# Create D1 tables if D1 available
if [ -n "$D1_ID" ]; then
  echo "[info] creating D1 tables (if not exist)"
  D1_Q='[{"sql": "CREATE TABLE IF NOT EXISTS documents (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT UNIQUE, title TEXT, content TEXT, source TEXT, date TEXT, metadata TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)", "params": []}]'
  D1_QUERY_RESPONSE=$(curl -sS -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/d1/database/$D1_ID/query" "${API_HDR[@]}" --data "$D1_Q" || true)
  if echo "$D1_QUERY_RESPONSE" | jq -e '.success' >/dev/null 2>&1; then
    echo "[info] Created/verified D1 tables"
  else
    echo "[warn] D1 table creation response: $D1_QUERY_RESPONSE"
  fi
fi

# Save asset information
ASSETS_FILE="$DATA_DIR/cloudflare_assets.json"
cat > "$ASSETS_FILE" << EOF
{
  "kv_namespace_id": "$KV_ID",
  "d1_database_id": "$D1_ID",
  "r2_bucket_id": "$R2_ID",
  "created_at": "$(date -Iseconds)"
}
EOF

echo "[info] Assets recorded to $ASSETS_FILE"

# Upload local supabase artifacts to R2 (best-effort)
echo "[info] Uploading local Supabase artifacts to R2 bucket (best-effort)"

R2_BUCKET_NAME="rag-documents"

upload_to_r2() {
  local file_path="$1"
  local object_key="$2"
  if [ ! -f "$file_path" ]; then
    echo "[info] skipping $file_path — not found"
    return 0
  fi
  local upload_url="https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/r2/buckets/$R2_BUCKET_NAME/objects/$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$object_key")"
  echo "[info] uploading $file_path -> $object_key"
  HTTP_RESPONSE=$(curl -sS -X PUT "$upload_url" "${API_HDR[@]}" -H "Content-Type: application/octet-stream" --data-binary "@$file_path" || true)
  if [ -z "$HTTP_RESPONSE" ]; then
    echo "[info] uploaded $object_key (no body returned)"
  else
    # if CF returns a JSON success blob, print a short summary
    echo "[info] upload response: $(echo "$HTTP_RESPONSE" | jq -c '. | {success: .success, result: (.result // "")}' 2>/dev/null || echo "$HTTP_RESPONSE")"
  fi
}

# Determine files to upload
COMPOSE_FILE="$BASE_DIR/deploy/compose/docker-compose-supabase.yml"
ENV_FILE="$BASE_DIR/.env.supabase"
SQL_DUMP_FILE="$DATA_DIR/supabase_schema.sql"

if [ ! -f "$SQL_DUMP_FILE" ]; then
  echo "[info] creating SQL dump placeholder at $SQL_DUMP_FILE"
  echo "-- Supabase schema for RAG documents" > "$SQL_DUMP_FILE"
  echo "-- Use scripts/cloudflare/setup_supabase.sh to apply schema live" >> "$SQL_DUMP_FILE"
fi

upload_to_r2 "$COMPOSE_FILE" "supabase/docker-compose-supabase.yml"
if [ "${UPLOAD_SECRETS:-0}" = "1" ]; then
  upload_to_r2 "$ENV_FILE" "supabase/.env.supabase"
else
  echo "[info] Skipping upload of .env.supabase (UPLOAD_SECRETS not set). To upload secrets set UPLOAD_SECRETS=1"
fi
upload_to_r2 "$SQL_DUMP_FILE" "supabase/supabase_schema.sql"

echo "[info] Finished creating/updating Cloudflare assets"

