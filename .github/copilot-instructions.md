## Copilot / AI Agent instructions — RAG repository (concise)

Purpose: give an AI coding agent immediate, actionable knowledge to be productive in this repo.

Quick checklist for every edit
- Prefer small, reversible changes and preserve existing style.
- Run repository build or smoke checks after edits when applicable (see "Dev commands").
- Don't commit secrets. Use `.env.supabase` generator (`scripts/supabase/generate_supabase_env.sh`) for local secrets.

Big-picture architecture (what to read first)
- `src/nvidia_rag/` — core Python services: RAG server and Ingestor server. Read `README.md` and `AGENTS.md` for orchestration context.
- `deploy/compose/` — Docker Compose manifests for local stacks (supabase, rag-server, ingestor). Use these to understand service boundaries.
- `frontend/` — Next.js UI that talks to RAG server. Useful for surface-level testing of endpoints.
- `scripts/` — automation (supabase env generator, orchestrator, Cloudflare worker and ingest scripts). These are entry points for developer workflows.

Critical developer workflows (run these locally)
- Python dev: use `uv` (repo uses `uv` wrapper). Typical commands:
  - `uv sync` (install deps)
  - `uv run python -m nvidia_rag.rag_server.main` (run RAG server)
  - `uv run python -m nvidia_rag.ingestor_server.main` (run Ingestor)
- Frontend: `cd frontend && npm install && npm run dev` (Next.js dev server)
- Local Supabase: generate `.env.supabase` with `scripts/supabase/generate_supabase_env.sh`, then `docker compose -f deploy/compose/docker-compose-supabase.yml up -d` and run `scripts/cloudflare/setup_supabase.sh` to apply schema.
- Orchestrator: `scripts/supabase/start_and_publish.sh` wires env generation, compose start, readiness checks, and schema application.

Project-specific conventions and patterns
- Config & secrets
  - Centralized config in Python via `get_config()` and custom `@configclass` decorators.
  - Environment variables follow `APP_SECTION_SETTINGNAME` where relevant; frontend uses `NEXT_PUBLIC_` prefix.
  - Do not hardcode secrets; prefer the `.env.supabase` generator (it can read Bitwarden if present).
- Typing & validation
  - Python code uses strict types and Pydantic models for API input/output. Follow existing typing patterns.
- Vectorstore & external services
  - Milvus (vector DB) and MinIO are used; vectorstore helpers live in `src/nvidia_rag/vectorstore` and are coupled to `create_vectorstore_langchain()`.
  - Ingest pipeline uses Redis for task status; NV-Ingest handles document extraction.

Integration points & external dependencies
- Supabase (self-hosted via Docker Compose) — scripts under `scripts/supabase` and compose file at `deploy/compose/docker-compose-supabase.yml`.
- Cloudflare Worker — `scripts/cloudflare/index.js` implements worker routes and ingestion shims; treat worker code as edge-targeted JS (no Node-only APIs).
- Ingest sources: govinfo/opendiscourse ingestion scripts in `scripts/ingest/*` push NDJSON to `/supabase/store` or `/store` endpoints.

When editing JavaScript worker code
- Keep functions small and pure; Cloudflare linter/Codacy flags cognitive complexity quickly — extract route handlers into small helpers (example: `fetchAndCache`, `handleSupabaseStore`).
- Avoid empty catch blocks; log with `console.debug` or similar and return clear HTTP 4xx/5xx responses.
- Don't use Node-only APIs (fs, process) in worker files — they run at edge.

Testing and smoke checks after changes
- For Python changes: run `uv run pytest` if tests exist; otherwise run the service locally with `uv run python -m nvidia_rag.rag_server.main` and exercise a simple HTTP call.
- For frontend changes: `cd frontend && npm run build` then `npm run lint`.
- For Cloudflare worker edits: run a static linter and unit-test helpers where possible; deploy only with credentials and in a PR.

Files to inspect for common pitfalls
- `scripts/supabase/generate_supabase_env.sh` — env generation semantics and Bitwarden integration.
- `scripts/supabase/start_and_publish.sh` — bootstrapping sequence and path resolution (BASE_DIR handling).
- `scripts/cloudflare/index.js` — edge code; keep cognitive complexity low and avoid silent catches.
- `deploy/compose/*.yml` — port/host mappings; generator writes `POSTGRES_HOST_PORT` used in compose.

If you modify runtime dependencies or install packages
- Update `pyproject.toml` or `frontend/package.json` and run `uv sync` or `npm install` respectively.
- Per repo policy, run Codacy MCP security scan for new dependencies (see `/home/cbwinslow/rag/.github/instructions/codacy.instructions.md`).

When unsure, ask the maintainer for:
- missing Cloudflare credentials (CF_API_TOKEN, CF_ACCOUNT_ID) to test worker publish
- preferred way to run full integration tests (CI or local Docker environment)

Please review and tell me any missing repo-specific details you want included (credentials, CI quirks, or preferred test endpoints).
