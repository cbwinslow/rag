#!/usr/bin/env bash
set -euo pipefail

# provision_apps.sh
# High-level orchestrator to deploy a set of self-hosted services on a single node using Docker Compose.
# It will clone repositories (Flowise, agentic-knowledge-rag-graph) and create a `deploy/host-compose.yml` file with common services.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/deploy/host-compose.yml"

echo "This script will create a docker-compose file at $COMPOSE_FILE and clone selected repos under $ROOT_DIR/external"
read -r -p "Proceed? (y/N) " yn
if [[ "$yn" != "y" && "$yn" != "Y" ]]; then
  echo "Aborting"
  exit 1
fi

mkdir -p "$ROOT_DIR/external"

echo "Cloning agentic-knowledge-rag-graph and flowise (if missing)"
if [ ! -d "$ROOT_DIR/external/agentic-knowledge-rag-graph" ]; then
  git clone https://github.com/yourchoice/agentic-knowledge-rag-graph.git "$ROOT_DIR/external/agentic-knowledge-rag-graph" || echo "Clone failed, ensure repo exists or clone manually"
fi
if [ ! -d "$ROOT_DIR/external/flowise" ]; then
  git clone https://github.com/FlowiseAI/Flowise.git "$ROOT_DIR/external/flowise" || echo "Clone failed, ensure repo exists or clone manually"
fi

cat > "$COMPOSE_FILE" <<'YAML'
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: example
    volumes:
      - postgres-data:/var/lib/postgresql/data

  supabase:
    image: supabase/postgres:latest
    depends_on:
      - postgres

  nextcloud:
    image: nextcloud:latest
    ports:
      - '8082:80'
    volumes:
      - nextcloud-data:/var/www/html

  localai:
    image: ghcr.io/go-skynet/LocalAI:latest
    environment:
      - MODEL=ggml-model.bin
    ports:
      - '8080:8080'

  openwebui:
    image: openwebui/openwebui:latest
    ports:
      - '8081:8080'

  anythingllm:
    image: ghcr.io/yourchoice/anythingllm:latest
    restart: unless-stopped

volumes:
  postgres-data:
  nextcloud-data:
  localai-models:
YAML

echo "Created compose file: $COMPOSE_FILE"
echo "Run: docker compose -f $COMPOSE_FILE up -d"

exit 0
