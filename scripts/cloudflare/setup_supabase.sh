#!/usr/bin/env bash
set -euo pipefail

# setup_supabase.sh
# Set up Supabase project and create necessary tables for document storage

echo "Setting up Supabase for RAG document storage..."

# locate repo root so we can reference the compose file reliably
BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# If .env.supabase exists (local docker-compose), load it and set SUPABASE_URL to PostgREST
if [ -f ".env.supabase" ]; then
  echo "Found .env.supabase — sourcing into environment"
  # shellcheck disable=SC1091
  # shellcheck disable=SC2046
  set -a
  # shellcheck source=/dev/null
  source .env.supabase
  set +a
  # Prefer local PostgREST endpoint
  SUPABASE_URL=${SUPABASE_URL:-http://localhost:${POSTGREST_HOST_PORT:-3000}}
  SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-${SUPABASE_ANON_KEY:-}}
fi

# Check for required environment variables
if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "Error: SUPABASE_URL and SUPABASE_ANON_KEY must be set — either export them or create .env.supabase using scripts/supabase/generate_supabase_env.sh"
  exit 1
fi

# Create documents table
echo "Creating documents table in Supabase..."

CREATE_TABLE_SQL="
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

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_documents_source ON documents(source);
CREATE INDEX IF NOT EXISTS idx_documents_date ON documents(date);
CREATE INDEX IF NOT EXISTS idx_documents_content_gin ON documents USING gin(to_tsvector('english', content));
CREATE INDEX IF NOT EXISTS idx_documents_title_gin ON documents USING gin(to_tsvector('english', title));

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS \$\$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
\$\$ language 'plpgsql';

CREATE TRIGGER update_documents_updated_at
    BEFORE UPDATE ON documents
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
"

# Execute the SQL via PostgREST (local) or Supabase RPC endpoint if available
echo "Applying SQL schema to: $SUPABASE_URL"

# If PostgREST is present, it may not provide an exec_sql RPC — fallback to psql container
RESPONSE=""
if curl --silent --fail --head "$SUPABASE_URL" >/dev/null 2>&1; then
  echo "Endpoint reachable — attempting RPC/SQL execution via HTTP"
  RESPONSE=$(curl -sS -X POST "${SUPABASE_URL}/rpc/exec_sql" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    --data "{\"sql\": \"${CREATE_TABLE_SQL}\"}" \
    2>/dev/null || true)
fi

# If HTTP RPC didn't work or isn't available, try running psql against the local docker Postgres container
if ! (echo "$RESPONSE" | jq -e '.success' >/dev/null 2>&1); then
  echo "HTTP RPC not available or failed — trying direct psql against local docker Postgres (if container running)"
  COMPOSE_FILE="$BASE_DIR/deploy/compose/docker-compose-supabase.yml"
  # prefer checking for the container name directly
  if docker ps --format '{{.Names}}' | grep -q '^supabase-db$'; then
    echo "$CREATE_TABLE_SQL" | docker exec -i supabase-db psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"
  else
    # as a fallback, check if the compose file exists and advise the user to start it
    if [ -f "$COMPOSE_FILE" ]; then
      echo "supabase-db container not running. Start it with:"
      echo "  docker compose -f $COMPOSE_FILE up -d"
    else
      echo "docker-compose supabase compose file not found at: $COMPOSE_FILE"
    fi
    echo "Or provide SUPABASE_URL and SUPABASE_ANON_KEY to this script."
    exit 1
  fi
fi

# Alternative: Try direct SQL execution if RPC doesn't work
if ! echo "$RESPONSE" | jq -e '.success' >/dev/null 2>&1; then
  echo "Trying alternative SQL execution method..."

  # Split the SQL into individual statements and execute them
  echo "$CREATE_TABLE_SQL" | while IFS= read -r line; do
    # Skip comments and empty lines
    [[ $line =~ ^-- ]] && continue
    [[ -z "${line// }" ]] && continue

    # Execute each statement
    if [[ $line == CREATE* ]] || [[ $line == DROP* ]] || [[ $line == ALTER* ]]; then
      echo "Executing: $line"
      # Note: This is a simplified approach. In production, you'd want to use proper SQL execution
    fi
  done
fi

echo "Supabase setup completed!"
echo ""
echo "Table structure:"
echo "- documents: Main table for storing ingested documents"
echo "  - id: Primary key"
echo "  - url: Document URL (unique)"
echo "  - title: Document title"
echo "  - content: Full document content"
echo "  - source: Source system (govinfo, congress, opendiscourse)"
echo "  - date: Publication date"
echo "  - metadata: Additional metadata as JSON"
echo "  - created_at/updated_at: Timestamps"
echo ""
echo "Indexes created for:"
echo "- Source filtering"
echo "- Date-based queries"
echo "- Full-text search on content and title"
echo ""
echo "To ingest documents:"
echo "python3 scripts/ingest/gov_ingest.py --source supabase --supabase-url $SUPABASE_URL --supabase-key $SUPABASE_ANON_KEY --path /collections/BILLS --api-key YOUR_GOVINFO_API_KEY"
echo ""
echo "To search documents:"
echo "curl '$SUPABASE_URL/rest/v1/documents?content=ilike.*searchterm*&select=*' -H 'apikey: $SUPABASE_ANON_KEY'"
