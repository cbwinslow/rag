# Supabase local deployment helper

This folder contains tools to run a minimal self-hosted Supabase stack using Docker Compose and to generate the secret environment file from Bitwarden (if available).

Files:

- `generate_supabase_env.sh` — creates `.env.supabase` by reading Bitwarden (`bw`) or prompting for values. Backups existing `.env.supabase`.

- `docker-compose-supabase.yml` — located in `deploy/compose/` (root compose carries the file). Minimal stack: Postgres + PostgREST.


Quick start:

1. Ensure `bw` (Bitwarden CLI) is installed and you're logged in/unlocked if you want to pull secrets from your vault.

1. Generate the env file:

```bash
./scripts/supabase/generate_supabase_env.sh
```

1. Start the stack:

```bash
docker compose -f deploy/compose/docker-compose-supabase.yml up -d
```

1. Apply the schema:

```bash
./scripts/cloudflare/setup_supabase.sh
```

Notes:

- `.env.supabase` is ignored by git. Keep it secure.

- This is a minimal deployment; if you need the full Supabase self-hosted stack (auth, storage, realtime), ask and a fuller compose can be added.
