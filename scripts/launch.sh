#!/usr/bin/env bash
set -euo pipefail

# NVIDIA RAG Blueprint local launcher
# Usage: ./scripts/launch.sh [--profile accuracy|perf|none] [--mode onprem|cloud] [--build] [--stop]

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_DIR="$ROOT_DIR/deploy/compose"
ENV_FILE="$COMPOSE_DIR/.env"

show_help(){
  cat <<EOF
Usage: $0 [options]

Options:
  --profile <accuracy|perf|none>   Load additional env profile (accuracy/perf)
  --mode <onprem|cloud>            Use on-prem NIMs (default) or NVIDIA hosted endpoints
  --build                          Pass --build to docker compose up for services that support --build
  --stop                           Stop the services started by this script
  -h, --help                       Show this help

Examples:
  # Start with on-prem models and accuracy profile
  ./scripts/launch.sh --profile accuracy

  # Start using NVIDIA hosted endpoints
  ./scripts/launch.sh --mode cloud

  # Stop services
  ./scripts/launch.sh --stop
EOF
}

# default options
PROFILE="none"
MODE="onprem"
BUILD=false
STOP=false

REMOTE_HOST=""
REMOTE_USER=""
REMOTE_PATH=""
SSH_KEY=""
ANSIBLE_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"; shift 2;;
    --mode)
      MODE="$2"; shift 2;;
    --build)
      BUILD=true; shift;;
    --stop)
      STOP=true; shift;;
    --remote-host)
      REMOTE_HOST="$2"; shift 2;;
    --remote-user)
      REMOTE_USER="$2"; shift 2;;
    --remote-path)
      REMOTE_PATH="$2"; shift 2;;
    --ssh-key)
      SSH_KEY="$2"; shift 2;;
    --ansible-only)
      ANSIBLE_ONLY=true; shift;;
    -h|--help)
      show_help; exit 0;;
    *)
      echo "Unknown arg: $1"; show_help; exit 2;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found in PATH. Please install Docker and the NVIDIA Container Toolkit if you plan to run GPU-accelerated services." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose plugin not available. Please install Docker Compose v2+." >&2
  exit 1
fi

if [ "$STOP" = true ]; then
  echo "Stopping services..."
  docker compose -f "$COMPOSE_DIR/docker-compose-rag-server.yaml" down || true
  docker compose -f "$COMPOSE_DIR/docker-compose-ingestor-server.yaml" down || true
  docker compose -f "$COMPOSE_DIR/vectordb.yaml" down || true
  docker compose -f "$COMPOSE_DIR/nims.yaml" down || true
  echo "Stopped."
  exit 0
fi

# If user requested ansible-only, generate playbook and exit
if [ "$ANSIBLE_ONLY" = true ]; then
  echo "Generating a simple Ansible playbook/template in scripts/ansible/ (use ansible-playbook with proper inventory and vars)"
  echo "See scripts/ansible/README.md for usage"
  exit 0
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Expected env file at $ENV_FILE not found." >&2
  exit 1
fi

echo "Loading base environment from $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

# Ensure NGC_API_KEY is set (required to pull images from nvcr.io / access NIMs)
if [ -z "${NGC_API_KEY:-}" ]; then
  echo "NGC_API_KEY not set. You must set or export your NGC_API_KEY (see docs/quickstart.md)."
  read -r -p "Enter NGC_API_KEY (will not be stored): " -s NGC_API_KEY_INPUT
  echo
  if [ -z "$NGC_API_KEY_INPUT" ]; then
    echo "NGC_API_KEY is required to continue." >&2
    exit 1
  fi
  export NGC_API_KEY="$NGC_API_KEY_INPUT"
  export NVIDIA_API_KEY="$NGC_API_KEY_INPUT"
fi

# MODE-specific overrides
if [ "$MODE" = "cloud" ]; then
  echo "Configuring for NVIDIA-hosted endpoints (cloud). Overriding some service URLs to use hosted endpoints."
  export APP_EMBEDDINGS_SERVERURL=""
  export APP_LLM_SERVERURL=""
  export APP_RANKING_SERVERURL=""
  export SUMMARY_LLM_SERVERURL=""
  # Set embedding integration endpoint used by some services
  export EMBEDDING_NIM_ENDPOINT="https://integrate.api.nvidia.com/v1"
  export PADDLE_HTTP_ENDPOINT="https://ai.api.nvidia.com/v1/cv/baidu/paddleocr"
  export PADDLE_INFER_PROTOCOL="http"
  export YOLOX_HTTP_ENDPOINT="https://ai.api.nvidia.com/v1/cv/nvidia/nemoretriever-page-elements-v2"
  export YOLOX_INFER_PROTOCOL="http"
else
  echo "Configuring for on-prem NIMs (default). Using endpoints from $ENV_FILE"
fi

# load optional profiles
if [ "$PROFILE" = "accuracy" ]; then
  echo "Loading accuracy profile"
  # shellcheck disable=SC1090
  source "$COMPOSE_DIR/accuracy_profile.env"
elif [ "$PROFILE" = "perf" ]; then
  echo "Loading perf profile"
  # shellcheck disable=SC1090
  source "$COMPOSE_DIR/perf_profile.env"
else
  echo "No additional profile loaded"
fi

# Ensure model cache directory
if [ -z "${MODEL_DIRECTORY:-}" ]; then
  MODEL_DIRECTORY="$HOME/.cache/model-cache"
  mkdir -p "$MODEL_DIRECTORY"
  export MODEL_DIRECTORY
  echo "Set MODEL_DIRECTORY to $MODEL_DIRECTORY"
fi

BUILD_ARG=""
if [ "$BUILD" = true ]; then
  BUILD_ARG="--build"
fi

echo "Starting NIMs... (this can take a while on first run while models download)"
if [ -n "$REMOTE_HOST" ]; then
  # SSH-based remote deploy flow
  if ! command -v rsync >/dev/null 2>&1; then
    echo "rsync is required for remote deploy. Please install rsync." >&2
    exit 1
  fi

  if [ -z "$REMOTE_USER" ]; then
    REMOTE_USER=$(whoami)
    echo "No --remote-user provided, defaulting to local user: $REMOTE_USER"
  fi

  if [ -z "$REMOTE_PATH" ]; then
    REMOTE_PATH="/tmp/rag-deploy-$(date +%s)"
    echo "No --remote-path provided, defaulting to $REMOTE_PATH"
  fi

  SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  if [ -n "$SSH_KEY" ]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
  fi

  echo "Syncing repository to $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"
  rsync -az --delete --exclude='.git' --exclude='data/dataset.zip' "$ROOT_DIR/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/" -e "ssh $SSH_OPTS"

  # Build remote command to run the launcher on the remote side with same options
  REMOTE_CMD="cd $REMOTE_PATH && chmod +x ./scripts/launch.sh && \
    NGC_API_KEY=\"${NGC_API_KEY:-}\" MODEL_DIRECTORY=\"${MODEL_DIRECTORY:-}\" ./scripts/launch.sh"

  # Append profile/mode/build flags
  if [ "$PROFILE" != "none" ]; then
    REMOTE_CMD="$REMOTE_CMD --profile $PROFILE"
  fi
  if [ "$MODE" = "cloud" ]; then
    REMOTE_CMD="$REMOTE_CMD --mode cloud"
  fi
  if [ "$BUILD" = true ]; then
    REMOTE_CMD="$REMOTE_CMD --build"
  fi

  echo "Running remote launcher on $REMOTE_HOST"
  ssh $SSH_OPTS "$REMOTE_USER@$REMOTE_HOST" "$REMOTE_CMD"
  echo "Remote deploy finished. Check the remote host for container status."
  exit 0
else
  USERID=$(id -u) docker compose -f "$COMPOSE_DIR/nims.yaml" up -d $BUILD_ARG
fi

echo "Starting Milvus / Vector DB..."
docker compose -f "$COMPOSE_DIR/vectordb.yaml" up -d $BUILD_ARG

echo "Starting Ingestor server and NV-Ingest..."
docker compose -f "$COMPOSE_DIR/docker-compose-ingestor-server.yaml" up -d $BUILD_ARG

echo "Starting RAG server and frontend..."
docker compose -f "$COMPOSE_DIR/docker-compose-rag-server.yaml" up -d $BUILD_ARG

echo "All services started."
echo "Check status with: docker ps --format 'table {{.Names}}\t{{.Status}}'"
echo "RAG UI: http://localhost:8090 (rag-playground)"
echo "RAG Server health: http://localhost:8081/v1/health?check_dependencies=true"

exit 0
