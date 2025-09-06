#!/usr/bin/env bash
set -euo pipefail

PACKAGE=${1:-BILLS}
PAGESIZE=${2:-5}
OUT=${3:-/tmp/govinfo_sample.ndjson}

API_KEY=${GOVINFO_API_KEY-}

echo "Fetching govinfo collection: $PACKAGE (pageSize=$PAGESIZE)"
if [ -z "$API_KEY" ]; then
  echo "Warning: GOVINFO_API_KEY not set. Request may be rate-limited or rejected by the API."
fi

URL="https://api.govinfo.gov/collections/${PACKAGE}"

echo "Querying $URL"
HTTP_STATUS=$(curl -s -w "%{http_code}" -o /tmp/govinfo_resp.json \
  -G "$URL" --data-urlencode "pageSize=$PAGESIZE" --data-urlencode "offset=0" \
  ${API_KEY:+-H "X-Api-Key: $API_KEY"})

if [ "$HTTP_STATUS" != "200" ]; then
  echo "govinfo API returned HTTP $HTTP_STATUS"
  cat /tmp/govinfo_resp.json || true
  exit 1
fi

jq -c '.packages[] | {packageId, title: .title, dateIssued: .dateIssued, detailsLink: .detailsLink, collection: .collection}' /tmp/govinfo_resp.json | tee "$OUT"

echo "Wrote sample NDJSON to $OUT"
