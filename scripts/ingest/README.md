Ingestion helpers for govinfo.gov and congress.gov

This folder contains `gov_ingest.py`, a minimal script that can fetch documents from govinfo.gov (API or bulk), congress.gov, or via the Cloudflare Worker, and emit NDJSON records suitable for autorag ingestion.

Usage examples:

  # Ingest govinfo collection (needs GOVINFO_API_KEY)
  GOVINFO_API_KEY=yourkey python3 scripts/ingest/gov_ingest.py --source govinfo --path /collections/BILLS --api-key $GOVINFO_API_KEY --out bills.ndjson

  # Use a deployed worker to fetch a specific path
  python3 scripts/ingest/gov_ingest.py --source worker --worker-url https://my-worker.example/fetch --path /docs/some-page --out page.ndjson

Notes:
- The script is intentionally minimal and intended to be a starting point — adapt parsing and metadata extraction to fit autorag's ingestion schema.
- For heavy ingest jobs (bulk download), run this on a VM with sufficient disk and network bandwidth.
