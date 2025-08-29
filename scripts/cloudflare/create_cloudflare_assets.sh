#!/usr/bin/env bash
set -euo pipefail

# create_cloudflare_assets.sh
# Create all necessary Cloudflare assets for the RAG system
# Requires: CF_API_TOKEN, CF_ACCOUNT_ID

echo "Creating Cloudflare assets for RAG system..."

# Check for required environment variables
if [ -z "${CF_API_TOKEN:-}" ] || [ -z "${CF_ACCOUNT_ID:-}" ]; then
  echo "Error: CF_API_TOKEN and CF_ACCOUNT_ID must be set"
  exit 1
fi

# Create KV namespace
echo "Creating KV namespace..."
KV_RESPONSE=$(curl -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"title": "rag-autorag-kv"}')

KV_ID=$(echo $KV_RESPONSE | jq -r '.result.id')
if [ "$KV_ID" = "null" ] || [ -z "$KV_ID" ]; then
  echo "Failed to create KV namespace"
  echo "Response: $KV_RESPONSE"
  exit 1
fi
echo "Created KV namespace: $KV_ID"

# Create D1 database
echo "Creating D1 database..."
D1_RESPONSE=$(curl -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/d1/database" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"name": "rag_documents"}')

D1_ID=$(echo $D1_RESPONSE | jq -r '.result.uuid')
if [ "$D1_ID" = "null" ] || [ -z "$D1_ID" ]; then
  echo "Failed to create D1 database"
  echo "Response: $D1_RESPONSE"
  exit 1
fi
echo "Created D1 database: $D1_ID"

# Create R2 bucket
echo "Creating R2 bucket..."
R2_RESPONSE=$(curl -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/r2/buckets" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"name": "rag-documents"}')

R2_ID=$(echo $R2_RESPONSE | jq -r '.result.id')
if [ "$R2_ID" = "null" ] || [ -z "$R2_ID" ]; then
  echo "Failed to create R2 bucket"
  echo "Response: $R2_RESPONSE"
  exit 1
fi
echo "Created R2 bucket: $R2_ID"

# Update wrangler.toml with the actual IDs
WRANGLER_FILE="/home/cbwinslow/rag/scripts/cloudflare/wrangler.toml"
sed -i "s/YOUR_AUTORAG_KV_ID/$KV_ID/g" "$WRANGLER_FILE"
sed -i "s/YOUR_D1_DATABASE_ID/$D1_ID/g" "$WRANGLER_FILE"
sed -i "s/YOUR_R2_BUCKET_ID/$R2_ID/g" "$WRANGLER_FILE"

echo "Updated wrangler.toml with asset IDs"

# Create D1 tables
echo "Creating D1 tables..."
D1_QUERY_RESPONSE=$(curl -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/d1/database/$D1_ID/query" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '[{"sql": "CREATE TABLE IF NOT EXISTS documents (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT UNIQUE, title TEXT, content TEXT, source TEXT, date TEXT, metadata TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)", "params": []}]')

if ! echo $D1_QUERY_RESPONSE | jq -e '.success' >/dev/null; then
  echo "Failed to create D1 tables"
  echo "Response: $D1_QUERY_RESPONSE"
  exit 1
fi

echo "Created D1 tables successfully"

# Output the asset information
cat << EOF
Cloudflare assets created successfully!

Asset IDs:
- KV Namespace: $KV_ID
- D1 Database: $D1_ID
- R2 Bucket: $R2_ID

Next steps:
1. Set up Supabase project and get SUPABASE_URL and SUPABASE_ANON_KEY
2. Update wrangler.toml with your Supabase credentials
3. Run: wrangler secret put SUPABASE_URL
4. Run: wrangler secret put SUPABASE_ANON_KEY
5. Deploy the worker: wrangler deploy

Asset information saved to: /home/cbwinslow/rag/data/cloudflare_assets.json
EOF

# Save asset information
mkdir -p /home/cbwinslow/rag/data
cat > /home/cbwinslow/rag/data/cloudflare_assets.json << EOF
{
  "kv_namespace_id": "$KV_ID",
  "d1_database_id": "$D1_ID",
  "r2_bucket_id": "$R2_ID",
  "created_at": "$(date -Iseconds)"
}
EOF

# Upload local supabase artifacts to R2 (if files exist)
echo "Uploading local Supabase artifacts to R2 bucket..."

R2_BUCKET_NAME="rag-documents"

upload_to_r2() {
  local file_path="$1"
  local object_key="$2"
  if [ ! -f "$file_path" ]; then
    echo "Skipping $file_path — not found"
    return 0
  fi

  # Create an unsigned URL via the Cloudflare API for object upload (requires account-level API)
  # Note: R2 supports an S3-compatible API; alternatively, use signed URLs or bucket keys.
  UPLOAD_URL="https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/r2/buckets/$R2_BUCKET_NAME/objects/$object_key"

  echo "Uploading $file_path -> $object_key"
  HTTP_RESPONSE=$(curl -sS -X PUT "$UPLOAD_URL" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$file_path" || true)

  if [ -z "$HTTP_RESPONSE" ]; then
    echo "Uploaded $object_key"
  else
    echo "Response: $HTTP_RESPONSE"
  fi
}

# Determine files to upload
BASE_DIR="/home/cbwinslow/rag"
COMPOSE_FILE="$BASE_DIR/deploy/compose/docker-compose-supabase.yml"
ENV_FILE="$BASE_DIR/.env.supabase"
SQL_DUMP_FILE="$BASE_DIR/data/supabase_schema.sql"

# If SQL file doesn't exist, try to export the CREATE statements from the setup script (best-effort)
if [ ! -f "$SQL_DUMP_FILE" ]; then
  echo "Creating SQL dump placeholder at $SQL_DUMP_FILE"
  mkdir -p "$BASE_DIR/data"
  echo "-- Supabase schema for RAG documents" > "$SQL_DUMP_FILE"
  echo "-- Use scripts/cloudflare/setup_supabase.sh to apply schema live" >> "$SQL_DUMP_FILE"
fi

upload_to_r2 "$COMPOSE_FILE" "supabase/docker-compose-supabase.yml"
# Only upload secrets file if UPLOAD_SECRETS=1
if [ "${UPLOAD_SECRETS:-0}" = "1" ]; then
  upload_to_r2 "$ENV_FILE" "supabase/.env.supabase"
else
  echo "Skipping upload of .env.supabase (UPLOAD_SECRETS not set). To upload secrets set UPLOAD_SECRETS=1"
fi
upload_to_r2 "$SQL_DUMP_FILE" "supabase/supabase_schema.sql"

# Record uploaded artifacts in cloudflare_assets.json
jq --arg r2 "$R2_ID" \
   --arg compose "supabase/docker-compose-supabase.yml" \
   --arg env "supabase/.env.supabase" \
   --arg sql "supabase/supabase_schema.sql" \
   '. + {"r2_uploaded": {"compose": $compose, "env": $env, "sql": $sql}}' \
   /home/cbwinslow/rag/data/cloudflare_assets.json > /home/cbwinslow/rag/data/cloudflare_assets.json.tmp && mv /home/cbwinslow/rag/data/cloudflare_assets.json.tmp /home/cbwinslow/rag/data/cloudflare_assets.json

echo "Uploaded assets metadata updated in /home/cbwinslow/rag/data/cloudflare_assets.json"
