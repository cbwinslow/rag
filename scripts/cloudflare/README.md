# Cloudflare RAG Setup

This directory contains scripts to set up a complete RAG (Retrieval-Augmented Generation) system on Cloudflare with Supabase integration for document storage and search.

## Overview

The system includes:

- **Cloudflare Worker**: API endpoints for fetching documents from opendiscourse.net, govinfo.gov, and congress.gov
- **Cloudflare KV**: Key-value storage for document caching
- **Cloudflare D1**: SQLite database for structured document storage
- **Cloudflare R2**: Object storage for large files
- **Supabase**: PostgreSQL database for advanced document search and analytics

## Prerequisites

1. **Cloudflare Account**: Sign up at [cloudflare.com](https://cloudflare.com)
2. **Supabase Account**: Sign up at [supabase.com](https://supabase.com)
3. **Wrangler CLI**: Install with `npm install -g wrangler`
4. **API Keys**:
   - Cloudflare API Token (with Workers, KV, D1, R2 permissions)
   - GovInfo API Key (from [govinfo.gov](https://www.govinfo.gov/app/registration))
   - Supabase Project URL and Anon Key

## Quick Setup

1. **Set Environment Variables**:

   ```bash
   export CF_API_TOKEN="your_cloudflare_api_token"
   export CF_ACCOUNT_ID="your_cloudflare_account_id"
   export GOVINFO_API_KEY="your_govinfo_api_key"
   export SUPABASE_URL="https://your-project.supabase.co"
   export SUPABASE_ANON_KEY="your_supabase_anon_key"
   export AUTORAG_API_KEY="your_secret_api_key"
   ```

2. **Run Auto Setup**:

   ```bash
   cd scripts/cloudflare
   ./auto_setup.sh
   ```

   This will:
   - Create KV namespace, D1 database, and R2 bucket
   - Set up Supabase tables
   - Configure Worker secrets
   - Deploy the Worker

## Manual Setup Steps

### 1. Create Cloudflare Assets

```bash
./create_cloudflare_assets.sh
```

This creates:

- KV Namespace: `rag-autorag-kv`
- D1 Database: `rag_documents`
- R2 Bucket: `rag-documents`

### 2. Set Up Supabase

```bash
./setup_supabase.sh
```

This creates the `documents` table with:

- Full-text search indexes
- Metadata storage
- Automatic timestamps

### 3. Configure Worker Secrets

```bash
wrangler secret put GOVINFO_API_KEY
wrangler secret put AUTORAG_API_KEY
wrangler secret put SUPABASE_URL
wrangler secret put SUPABASE_ANON_KEY
```

### 4. Deploy Worker

```bash
wrangler deploy
```

## API Endpoints

Once deployed, your Worker provides these endpoints:

### Document Fetching

- `GET /fetch?path=/api/path` - Fetch from opendiscourse.net
- `GET /govinfo?path=/collections/BILLS` - Fetch from govinfo.gov API
- `GET /congress?path=/search` - Fetch from congress.gov

### Storage

- `POST /store` - Store NDJSON documents in KV
- `POST /supabase/store` - Store documents in Supabase

### Search

- `GET /supabase/search?q=searchterm` - Search documents in Supabase
- `GET /kv/list` - List KV keys (admin only)

## Document Ingestion

### Direct to Supabase

```bash
python3 scripts/ingest/gov_ingest.py \
  --source supabase \
  --supabase-url $SUPABASE_URL \
  --supabase-key $SUPABASE_ANON_KEY \
  --path /collections/BILLS \
  --api-key $GOVINFO_API_KEY
```

### Via Worker

```bash
# Generate NDJSON
python3 scripts/ingest/gov_ingest.py \
  --source govinfo \
  --path /collections/BILLS \
  --api-key $GOVINFO_API_KEY \
  --out documents.ndjson

# Push to Worker
python3 scripts/ingest/gov_ingest.py \
  --source govinfo \
  --path /collections/BILLS \
  --api-key $GOVINFO_API_KEY \
  --push-worker \
  --worker-store-url https://your-worker.workers.dev/supabase/store
```

## Testing

Run the test suite:

```bash
./test_ingestion.sh
```

This tests:

- Supabase connectivity
- Document ingestion
- Search functionality

## Search Examples

### Full-text Search

```bash
curl 'https://your-project.supabase.co/rest/v1/documents?content=ilike.*bill*&select=title,source,date' \
  -H 'apikey: your_supabase_anon_key'
```

### Filter by Source

```bash
curl 'https://your-project.supabase.co/rest/v1/documents?source=eq.govinfo&select=*' \
  -H 'apikey: your_supabase_anon_key'
```

### Date Range Search

```bash
curl 'https://your-project.supabase.co/rest/v1/documents?date=gte.2024-01-01&select=title,date' \
  -H 'apikey: your_supabase_anon_key'
```

## Configuration Files

- `wrangler.toml` - Worker configuration
- `index.js` - Main Worker code
- `auto_setup.sh` - Automated setup script
- `create_cloudflare_assets.sh` - Asset creation script
- `setup_supabase.sh` - Supabase setup script
- `test_ingestion.sh` - Test suite

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `CF_API_TOKEN` | Cloudflare API token | Yes |
| `CF_ACCOUNT_ID` | Cloudflare account ID | Yes |
| `GOVINFO_API_KEY` | GovInfo API key | For govinfo ingestion |
| `SUPABASE_URL` | Supabase project URL | For Supabase features |
| `SUPABASE_ANON_KEY` | Supabase anon key | For Supabase features |
| `AUTORAG_API_KEY` | API key for admin operations | Yes |

## Troubleshooting

### Worker Deployment Issues

- Check `wrangler.toml` configuration
- Verify API token permissions
- Ensure account ID is correct

### Supabase Connection Issues

- Verify project URL and keys
- Check Supabase project is active
- Ensure anon key has proper permissions

### Ingestion Failures

- Check API keys are valid
- Verify network connectivity
- Check rate limits for external APIs

## Security Notes

- Store API keys as Worker secrets, not in code
- Use the `AUTORAG_API_KEY` for admin operations
- Regularly rotate API keys
- Monitor usage in Cloudflare dashboard

## Cost Considerations

- **Workers**: Pay per request
- **KV**: Pay per GB stored and operations
- **D1**: Pay per GB stored and queries
- **R2**: Pay per GB stored and operations
- **Supabase**: Free tier available, paid for high usage

## Files Overview

- `index.js` - Cloudflare Worker that serves multiple endpoints for document fetching, storage, and search
- `wrangler.toml` - Wrangler configuration (fill `account_id` and other settings before publishing)
- `auto_setup.sh` - Automated setup script for complete deployment
- `create_cloudflare_assets.sh` - Creates KV, D1, and R2 assets
- `setup_supabase.sh` - Sets up Supabase tables and indexes
- `test_ingestion.sh` - Test suite for the ingestion pipeline
- `.github/workflows/deploy-cloudflare.yml` - CI workflow template

## CI / Deployment

We added GitHub Actions workflows to validate and deploy components automatically:

- `.github/workflows/docker-build-push.yml` — builds and pushes Docker images for `frontend`, `rag-server`, and `ingestor-server` to GHCR on push to `main` or PRs.
- `.github/workflows/python-ci.yml` — basic Python lint/test checks on PRs and pushes.
- `.github/workflows/deploy-cloudflare.yml` — publishes the Cloudflare Worker (requires `CF_API_TOKEN` secret).
- `.github/workflows/deploy-pages.yml` — deploys the Pages site when installer changes are pushed.

Required repository secrets (set in GitHub Settings → Secrets → Actions):

- `CF_API_TOKEN` — Cloudflare API token with Workers/KV/D1/R2 permissions.
- `CF_ACCOUNT_ID` — Cloudflare account id used by pages/wrangler.
- `GOVINFO_API_KEY` — for ingestion jobs.

Notes:

- The docker build workflow pushes to the GitHub Container Registry `ghcr.io/${{ github.repository_owner }}` using the default `GITHUB_TOKEN`. For cross-account pushes or external registries, set `CR_PAT` or use other secrets.
- By default we DO NOT upload `.env.supabase` to Cloudflare R2. To enable that, set `UPLOAD_SECRETS=1` in the environment when running `create_cloudflare_assets.sh` locally or in a secure workflow (not recommended without encryption).

