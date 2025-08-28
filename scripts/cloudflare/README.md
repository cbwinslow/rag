Cloudflare deployment for RAG - opendiscourse integration

This folder contains a minimal Cloudflare Worker and deployment artifacts to:

- Host a Worker that fetches pages from https://opendiscourse.net and caches them for ingestion.
- Provide a Pages-ready site bundle via `scripts/installer` (post_install.sh, public key, index.html).
- CI workflow example to publish the worker via GitHub Actions.

Files:
- `index.js` - Cloudflare Worker that serves `/fetch?path=` to retrieve remote pages and optionally return JSON.
- `wrangler.toml` - Wrangler configuration (fill `account_id` and other settings before publishing).
- `.github/workflows/deploy-cloudflare.yml` - workflow template that publishes the worker on pushes to `main`.

How it fits with RAG and opendiscourse:
- The Worker provides a simple, cache-backed endpoint to fetch and normalize pages from opendiscourse.net. The RAG ingestion pipeline or retriever can call it to pull docs for indexing.
- Example: call `https://<worker-host>/fetch?path=/docs/some-page` to fetch a page's HTML (or request JSON by sending Accept: application/json).

Before you deploy
- Create a Cloudflare API token with permissions for Workers and Pages as needed and add it to the repository secrets as `CF_API_TOKEN`.
- Update `wrangler.toml` with your Cloudflare `account_id` and `name`.
- Test locally with `wrangler dev` or `wrangler preview`.

Security notes:
- The Worker fetches public pages only. If you plan to fetch private content, add authentication and secure storage for credentials.
