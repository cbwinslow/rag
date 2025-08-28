#!/usr/bin/env bash
set -euo pipefail

# create_cloudflare_resources.sh
# Creates additional Cloudflare resources for the RAG system

echo "Creating additional Cloudflare resources..."

# Check if wrangler is authenticated
if ! wrangler whoami >/dev/null 2>&1; then
  echo "Wrangler not authenticated. Please run 'wrangler auth login' or set CF_API_TOKEN"
  exit 1
fi

echo "Creating KV namespace for RAG API data..."
RAG_API_KV_ID=$(wrangler kv:namespace create "RAG_API_DATA" --preview false | grep -o 'id = "[^"]*"' | cut -d'"' -f2)

if [ -n "$RAG_API_KV_ID" ]; then
  echo "Created KV namespace: $RAG_API_KV_ID"
  # Update the wrangler.toml with the actual KV ID
  sed -i "s/your_kv_namespace_id_here/$RAG_API_KV_ID/g" scripts/cloudflare/rag-api-wrangler.toml
else
  echo "Failed to create KV namespace"
fi

echo "Creating D1 database for structured data..."
# Note: D1 database creation requires manual setup in Cloudflare dashboard
# or using the API directly
echo "D1 database creation requires manual setup in Cloudflare dashboard"
echo "Please create a D1 database named 'rag_structured_data' in your Cloudflare account"

echo "Creating additional KV namespace for search index..."
SEARCH_INDEX_KV_ID=$(wrangler kv:namespace create "RAG_SEARCH_INDEX" --preview false | grep -o 'id = "[^"]*"' | cut -d'"' -f2)

if [ -n "$SEARCH_INDEX_KV_ID" ]; then
  echo "Created search index KV namespace: $SEARCH_INDEX_KV_ID"
else
  echo "Failed to create search index KV namespace"
fi

echo "Resources created successfully!"
echo "KV Namespaces:"
echo "  RAG_API_DATA: $RAG_API_KV_ID"
echo "  RAG_SEARCH_INDEX: $SEARCH_INDEX_KV_ID"
echo ""
echo "Next steps:"
echo "1. Create D1 database 'rag_structured_data' in Cloudflare dashboard"
echo "2. Update wrangler.toml files with the new resource IDs"
echo "3. Deploy the workers with: ./deploy_remote.sh --publish-rag-api --publish-docs"
