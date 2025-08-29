#!/usr/bin/env bash
set -euo pipefail

# start_and_publish.sh
# Orchestrates: generate env, start compose, export minimal schema, and register assets with Cloudflare.

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "1) Generate .env.supabase (interactive, may use bw)"
"$BASE_DIR/scripts/supabase/generate_supabase_env.sh"

echo "2) Start docker-compose supabase stack"
# ensure variables from .env.supabase are exported so compose sees JWT_SECRET and keys
if [ -f "$BASE_DIR/.env.supabase" ]; then
  # shellcheck disable=SC1091
  set -a
  # shellcheck source=/dev/null
  source "$BASE_DIR/.env.supabase"
  set +a
fi
export POSTGRES_HOST_PORT=${POSTGRES_HOST_PORT:-5432}
export POSTGREST_HOST_PORT=${POSTGREST_HOST_PORT:-3000}
docker compose -f "$BASE_DIR/deploy/compose/docker-compose-supabase.yml" up -d

echo "Waiting 5s for Postgres to accept connections..."
# Wait until Postgres is accepting connections on the host port
HOST_PORT=${POSTGRES_HOST_PORT:-5432}
echo "Waiting for Postgres at localhost:${HOST_PORT} to accept connections..."
for i in {1..30}; do
  if pg_isready -h localhost -p "$HOST_PORT" >/dev/null 2>&1; then
    echo "Postgres is ready"
    break
  fi
  sleep 1
done

# Wait for PostgREST
PGREST_PORT=${POSTGREST_HOST_PORT:-3000}
echo "Waiting for PostgREST at http://localhost:${PGREST_PORT} to respond..."
for i in {1..30}; do
  if curl -sS "http://localhost:${PGREST_PORT}" >/dev/null 2>&1; then
    echo "PostgREST responded"
    break
  fi
  sleep 1
done

# Export a minimal SQL schema placeholder (setup_supabase.sh also contains SQL)
SQL_OUT="$BASE_DIR/data/supabase_schema.sql"
mkdir -p "$(dirname "$SQL_OUT")"
cat > "$SQL_OUT" <<'SQL'
-- Supabase RAG documents schema
CREATE TABLE IF NOT EXISTS documents (
  id SERIAL PRIMARY KEY,
  url TEXT UNIQUE NOT NULL,
  title TEXT,
  content TEXT NOT NULL,
  source TEXT NOT NULL,
  date TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_documents_content_gin ON documents USING gin(to_tsvector('english', content));
CREATE INDEX IF NOT EXISTS idx_documents_title_gin ON documents USING gin(to_tsvector('english', title));
SQL

echo "3) Apply SQL via setup script (will fallback to psql inside container if needed)"
"$BASE_DIR/scripts/cloudflare/setup_supabase.sh"

echo "4) Create Cloudflare assets and upload compose + schema (will NOT upload secrets by default)"
CF_API_TOKEN=${CF_API_TOKEN:-}
CF_ACCOUNT_ID=${CF_ACCOUNT_ID:-}
if [ -z "$CF_API_TOKEN" ] || [ -z "$CF_ACCOUNT_ID" ]; then
  echo "CF_API_TOKEN or CF_ACCOUNT_ID not set — skipping Cloudflare assets creation. Export them to run that step."
  exit 0
fi

UPLOAD_SECRETS=${UPLOAD_SECRETS:-0}
export UPLOAD_SECRETS

"$BASE_DIR/scripts/cloudflare/create_cloudflare_assets.sh"

echo "Done."
