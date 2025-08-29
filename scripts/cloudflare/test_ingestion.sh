#!/usr/bin/env bash
set -euo pipefail

# test_ingestion.sh
# Test the complete ingestion pipeline from govinfo to Supabase

echo "Testing RAG ingestion pipeline..."

# Check for required environment variables
if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "Error: SUPABASE_URL and SUPABASE_ANON_KEY must be set"
  exit 1
fi

if [ -z "${GOVINFO_API_KEY:-}" ]; then
  echo "Warning: GOVINFO_API_KEY not set - some tests will be skipped"
fi

# Test 1: Check Supabase connection
echo "Test 1: Checking Supabase connection..."
RESPONSE=$(curl -s "${SUPABASE_URL}/rest/v1/documents?select=count" \
  -H "apikey: ${SUPABASE_ANON_KEY}")

if echo "$RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
  echo "❌ Supabase connection failed"
  echo "Response: $RESPONSE"
  exit 1
else
  echo "✅ Supabase connection successful"
fi

# Test 2: Test ingestion script help
echo "Test 2: Testing ingestion script..."
if python3 scripts/ingest/gov_ingest.py --help >/dev/null 2>&1; then
  echo "✅ Ingestion script runs successfully"
else
  echo "❌ Ingestion script failed"
  exit 1
fi

# Test 3: Test small ingestion (if API key available)
if [ -n "${GOVINFO_API_KEY:-}" ]; then
  echo "Test 3: Testing small document ingestion..."

  # Create a temporary test file
  TEST_FILE="/tmp/test_ingestion.ndjson"

  # Ingest a small collection
  python3 scripts/ingest/gov_ingest.py \
    --source govinfo \
    --path /collections/BILLS \
    --api-key "$GOVINFO_API_KEY" \
    --out "$TEST_FILE" \
    --pagesize 1

  if [ -f "$TEST_FILE" ] && [ -s "$TEST_FILE" ]; then
    echo "✅ Document ingestion successful"
    echo "Sample document:"
    head -1 "$TEST_FILE" | jq '.'

    # Test Supabase storage
    echo "Test 4: Testing Supabase storage..."
    cat "$TEST_FILE" | python3 -c "
import sys
import requests
import json

SUPABASE_URL = '$SUPABASE_URL'
SUPABASE_ANON_KEY = '$SUPABASE_ANON_KEY'

for line in sys.stdin:
    try:
        doc = json.loads(line.strip())
        response = requests.post(
            f'{SUPABASE_URL}/rest/v1/documents',
            json={
                'url': doc['url'],
                'title': doc['title'],
                'content': doc['content'][:1000],  # Limit content for test
                'source': 'test-' + doc['source'],
                'date': doc['date'],
                'metadata': {'test': True}
            },
            headers={
                'Content-Type': 'application/json',
                'Authorization': f'Bearer {SUPABASE_ANON_KEY}',
                'apikey': SUPABASE_ANON_KEY
            }
        )
        if response.status_code in [200, 201]:
            print('✅ Document stored in Supabase')
            break
        else:
            print(f'❌ Failed to store: {response.status_code}')
    except Exception as e:
        print(f'❌ Error: {e}')
        break
"
  else
    echo "❌ Document ingestion failed - no output file"
  fi

  # Cleanup
  rm -f "$TEST_FILE"
else
  echo "⚠️ Skipping ingestion tests - GOVINFO_API_KEY not set"
fi

# Test 5: Test search functionality
echo "Test 5: Testing search functionality..."
SEARCH_RESPONSE=$(curl -s "${SUPABASE_URL}/rest/v1/documents?select=title,source&limit=1" \
  -H "apikey: ${SUPABASE_ANON_KEY}")

if echo "$SEARCH_RESPONSE" | jq -e '.[0]' >/dev/null 2>&1; then
  echo "✅ Search functionality working"
  echo "Found documents:"
  echo "$SEARCH_RESPONSE" | jq '.'
else
  echo "⚠️ No documents found (this is normal if no ingestion has occurred)"
fi

echo ""
echo "Ingestion pipeline test completed!"
echo ""
echo "Next steps:"
echo "1. Set your GOVINFO_API_KEY environment variable"
echo "2. Run full ingestion: python3 scripts/ingest/gov_ingest.py --source supabase --supabase-url $SUPABASE_URL --supabase-key $SUPABASE_ANON_KEY --path /collections/BILLS --api-key YOUR_GOVINFO_API_KEY"
echo "3. Test search: curl '$SUPABASE_URL/rest/v1/documents?content=ilike.*bill*&select=title,source' -H 'apikey: $SUPABASE_ANON_KEY'"
