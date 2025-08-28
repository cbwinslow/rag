#!/usr/bin/env bash
#
# Name:            NeMo Agent Toolkit Single-Click Deploy
# Date:            2025-08-28 08:21:15 UTC
# Script Name:     deploy_nemo_agent_toolkit.sh
# Version:         1.0.0
# Log Summary:     Single-click installer and local orchestrator for NVIDIA/NeMo-Agent-Toolkit.
# Description:
#   This single-file bash script prepares a development/runtime environment to exercise
#   all major features documented in the repository README:
#     - Framework integrations / optional extras (LangChain, LangSmith, etc.)
#     - Examples installation and runnable workflows
#     - Profiling & observability (Phoenix / Phoenix docker)
#     - Memory backends (Redis example)
#     - HITL example (Jira flow)
#     - UI (nat serve -> FastAPI)
#     - MCP support (nat mcp)
#     - Local LLM connectivity instructions (vLLM / NIM placeholders)
#   It will attempt to be idempotent and do best-effort orchestration on a developer machine.
#
# Change Summary:
#   1.0.0 - Initial release: creates venv (or uses uv if available), installs dependencies,
#           initializes git LFS/submodules, launches example service containers (redis/phoenix),
#           installs example workflows, runs a Hello World nat run test, and starts nat serve/mcp
#           in background with logs.
#
# Inputs:
#   --repo-dir DIR        Path to repo root. Defaults to current working directory.
#   --no-docker           Skip starting docker-compose (useful if you run services manually).
#   --skip-examples       Skip installing example packages.
#   --no-venv             Do not create or activate a venv; uses current Python environment.
#   --nvidia-api-key KEY  Provide NVIDIA_API_KEY on CLI (environment var overrides).
#   --help                Show help.
#
# Outputs:
#   - Creates/uses a Python virtual environment (.venv) or 'uv' environment if available.
#   - Installs package and selected example workflows.
#   - Starts Docker compose stacks for Redis and Phoenix (if docker available and not skipped).
#   - Runs a Hello World workflow test (nat run).
#   - Starts nat serve (FastAPI) and nat mcp in background; logs written to ./deploy_logs/.
#
# Notes:
#   - This script makes reasonable best-effort assumptions about the system. Running
#     heavy model servers (vLLM, local NIM servers) is outside scope — the script will
#     provide commands and placeholders to launch those locally when desired.
#   - You should run this script from the repository root or provide --repo-dir.
#   - The script will not download large LLM weights. It configures and launches the
#     toolkit and example services required to exercise observability, memory, UI, MCP,
#     profiling and evaluation workflows provided by the repo.
#
# Author: GitHub Copilot (as assistant for cbwinslow)
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Default configuration
REPO_DIR="$(pwd)"
NO_DOCKER=false
SKIP_EXAMPLES=false
NO_VENV=false
NVIDIA_API_KEY="${NVIDIA_API_KEY:-}"
VENV_DIR=".venv"
LOG_DIR="deploy_logs"
SLEEP_AFTER_START=6

print_help() {
  cat <<'EOF'
Usage: deploy_nemo_agent_toolkit.sh [options]

Options:
  --repo-dir DIR        Path to the repository root (default: current directory).
  --no-docker           Don't start docker-compose services (redis/phoenix).
  --skip-examples       Skip installing example packages.
  --no-venv             Do not create or activate a virtual environment.
  --nvidia-api-key KEY  Provide NVIDIA_API_KEY for examples that require it.
  --help                Show this help and exit.
EOF
}

# Simple logger
log() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*"; }

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --repo-dir)
      REPO_DIR="$2"; shift 2;;
    --no-docker)
      NO_DOCKER=true; shift;;
    --skip-examples)
      SKIP_EXAMPLES=true; shift;;
    --no-venv)
      NO_VENV=true; shift;;
    --nvidia-api-key)
      NVIDIA_API_KEY="$2"; shift 2;;
    --help)
      print_help; exit 0;;
    *)
      warn "Unknown option: $1"; print_help; exit 1;;
  esac
done

mkdir -p "$LOG_DIR"

# Utility: check command exists
check_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# Ensure repo dir exists
if [[ ! -d "$REPO_DIR" ]]; then
  err "Repository directory not found: $REPO_DIR"
  exit 2
fi

cd "$REPO_DIR"
log "Operating in repository root: $(pwd)"

# Basic environment sanity checks
log "Checking basic commands: git, python3, pip"
REQUIRED_CMDS=(git python3 pip)
for c in "${REQUIRED_CMDS[@]}"; do
  if ! check_cmd "$c"; then
    err "Required command not found: $c. Please install it and re-run this script."
    exit 3
  fi
done

# Git lfs & submodules
if check_cmd git; then
  log "Initializing git submodules (if any) and git LFS..."
  if check_cmd git-lfs; then
    git lfs install || warn "git lfs install failed; continuing"
    # fetch LFS in best-effort mode
    git lfs pull || warn "git lfs pull failed or no lfs objects; continuing"
  else
    warn "git-lfs not installed; large files may fail to fetch."
  fi
  git submodule update --init --recursive || warn "No submodules or update failed; continuing"
fi

# Virtualenv and dependency install
create_and_activate_venv() {
  if [[ "$NO_VENV" == "true" ]]; then
    log "Skipping venv creation as requested (--no-venv). Using current Python environment."
    return 0
  fi

  # Prefer 'uv' if available (project uses uv in docs)
  if check_cmd uv; then
    log "Using 'uv' to create/activate environment..."
    if ! uv venv --list | grep -q "\.venv" 2>/dev/null; then
      # seed a .venv if missing; this is non-destructive
      uv venv --seed .venv || warn "uv venv creation had issues; will fallback to python venv"
    fi
    # Activate uv environment for pip and uv commands run via 'uv pip' later.
    # But 'uv' manages separate venv; we won't try to source unknown path here.
    log "Using 'uv' managed venv. Future package installs will prefer 'uv pip' and 'uv sync'."
    return 0
  fi

  # Fallback to python -m venv
  if [[ ! -d "$VENV_DIR" ]]; then
    log "Creating Python virtual environment at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
  fi

  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"
  log "Activated venv: $VENV_DIR (python: $(python3 --version))"
}

install_repo_and_extras() {
  log "Installing NeMo Agent Toolkit and optional extras (best-effort)..."

  # If uv available, prefer uv sync for full extras
  if check_cmd uv; then
    log "Running: uv sync --all-groups --all-extras"
    uv sync --all-groups --all-extras || warn "uv sync failed; falling back to pip install"
  fi

  # Try to pip install editable with all extras. This may fail if pyproject defines different extras.
  # It's intentionally best-effort: do not fail the whole script if extras not satisfied.
  set +e
  pip install -e ".[all]" >/dev/null 2>&1
  rc="$?"
  set -e
  if [[ "$rc" -ne 0 ]]; then
    warn "pip install -e '.[all]' failed or extras not present. Attempting core install."
    pip install -e . || err "Failed to pip install package in editable mode." && return 1
  fi

  # If uv exists, run uv pip install for optional example packages in an isolated way (best-effort)
  if check_cmd uv; then
    log "Installing example packages via 'uv pip' where applicable..."
    uv pip install -e examples/getting_started/simple_web_query >/dev/null 2>&1 || warn "Example install failed or not present: simple_web_query"
    uv pip install -e examples/memory/redis >/dev/null 2>&1 || warn "Example install failed or not present: memory/redis"
    uv pip install -e examples/HITL/por_to_jiratickets >/dev/null 2>&1 || warn "Example install failed or not present: HITL por_to_jiratickets"
  else
    log "Attempting pip install of a few example packages..."
    pip install -e examples/getting_started/simple_web_query >/dev/null 2>&1 || warn "Example install failed or not present: simple_web_query"
    pip install -e examples/memory/redis >/dev/null 2>&1 || warn "Example install failed or not present: memory/redis"
    pip install -e examples/HITL/por_to_jiratickets >/dev/null 2>&1 || warn "Example install failed or not present: HITL por_to_jiratickets"
  fi

  log "Core package and examples installation attempt complete."
}

start_docker_services() {
  if [[ "$NO_DOCKER" == "true" ]]; then
    log "Docker compose start skipped by user flag (--no-docker)."
    return 0
  fi

  if ! check_cmd docker && ! check_cmd docker-compose; then
    warn "Docker not found. Skipping docker-compose services (Redis, Phoenix)."
    return 0
  fi

  # find docker-compose files used by examples
  DOCKER_COMPOSES=()
  if [[ -f "examples/deploy/docker-compose.redis.yml" ]]; then
    DOCKER_COMPOSES+=("examples/deploy/docker-compose.redis.yml")
  fi
  if [[ -f "examples/deploy/docker-compose.phoenix.yml" ]]; then
    DOCKER_COMPOSES+=("examples/deploy/docker-compose.phoenix.yml")
  fi

  if [[ ${#DOCKER_COMPOSES[@]} -eq 0 ]]; then
    warn "No known docker-compose files found in examples/deploy. Skipping."
    return 0
  fi

  for dc in "${DOCKER_COMPOSES[@]}"; do
    log "Starting docker-compose: $dc (logs -> $LOG_DIR/$(basename "$dc").log)"
    # Use docker compose if available, else docker-compose
    if check_cmd docker && docker compose version >/dev/null 2>&1; then
      nohup docker compose -f "$dc" up --remove-orphans >"$LOG_DIR/$(basename "$dc").log" 2>&1 &
    else
      nohup docker-compose -f "$dc" up --remove-orphans >"$LOG_DIR/$(basename "$dc").log" 2>&1 &
    fi
    sleep 2
  done

  log "Requested docker services starting in background. Wait a few seconds for them to become healthy."
}

# Run a Hello World workflow from README to validate 'nat' CLI
run_hello_world() {
  log "Testing 'nat' CLI and running Hello World workflow..."

  if ! check_cmd nat; then
    warn "'nat' CLI not found in PATH. Trying to detect via 'uv' or virtualenv..."
    if check_cmd uv; then
      # uv provides 'uv pip' but not necessarily a nat executable in PATH. Try python -m nat.cli
      if python3 -c "import importlib,sys; importlib.import_module('nat.cli')" >/dev/null 2>&1; then
        log "Found nat package in environment. Will invoke via 'python -m nat.cli'"
        NAT_CMD="python3 -m nat.cli"
      else
        warn "nat not importable in Python environment. The Hello World test will be skipped."
        return 0
      fi
    else
      warn "Cannot find 'nat' CLI and 'uv' not found. Skipping Hello World test."
      return 0
    fi
  else
    NAT_CMD="nat"
  fi

  # Prepare a temporary workflow.yaml following README example
  TEMP_WF=".tmp_nemo_hello_world_workflow.yaml"
  cat > "$TEMP_WF" <<'YAML'
functions:
   wikipedia_search:
      _type: wiki_search
      max_results: 2

llms:
   nim_llm:
      _type: nim
      model_name: meta/llama-3.1-70b-instruct
      temperature: 0.0

workflow:
   _type: react_agent
   tool_names: [wikipedia_search]
   llm_name: nim_llm
   verbose: true
   parse_agent_response_max_retries: 3
YAML

  # Provide NVIDIA_API_KEY in environment if passed
  if [[ -n "$NVIDIA_API_KEY" ]]; then
    export NVIDIA_API_KEY
  fi

  log "Running nat run --config_file $TEMP_WF --input 'List five subspecies of Aardvarks' (this will be attempted in 120s timeout)..."
  set +e
  # run with a small timeout to avoid indefinite hangs (requires 'timeout' utility)
  if check_cmd timeout; then
    timeout 120 $NAT_CMD run --config_file "$TEMP_WF" --input "List five subspecies of Aardvarks" >"$LOG_DIR/nat_hello_world.log" 2>&1
  else
    $NAT_CMD run --config_file "$TEMP_WF" --input "List five subspecies of Aardvarks" >"$LOG_DIR/nat_hello_world.log" 2>&1 &
    pid=$!
    sleep 6
    if ps -p "$pid" >/dev/null 2>&1; then
      warn "nat run still running after a few seconds. Check logs: $LOG_DIR/nat_hello_world.log"
    fi
    wait "$pid" || true
  fi
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    log "Hello World nat run succeeded. Output available at $LOG_DIR/nat_hello_world.log"
  else
    warn "Hello World nat run failed or timed out. Check $LOG_DIR/nat_hello_world.log for details."
  fi

  rm -f "$TEMP_WF" || true
}

start_nat_servers() {
  # Start 'nat serve' (FastAPI) and 'nat mcp' (MCP) in background if nat is available.
  if ! check_cmd nat && ! python3 -c "import importlib,sys; importlib.import_module('nat.cli')" >/dev/null 2>&1; then
    warn "nat not available. Skipping starting nat serve/mcp."
    return 0
  fi

  # prefer nat executable
  if check_cmd nat; then
    NAT_CMD="nat"
  else
    NAT_CMD="python3 -m nat.cli"
  fi

  # Find a sensible config_file to serve. Prefer example simple_web_query config if present.
  SERVE_CONFIG=""
  if [[ -f "examples/getting_started/simple_web_query/configs/config.yml" ]]; then
    SERVE_CONFIG="examples/getting_started/simple_web_query/configs/config.yml"
  elif [[ -f "examples/documentation_guides/locally_hosted_llms/nim_config.yml" ]]; then
    SERVE_CONFIG="examples/documentation_guides/locally_hosted_llms/nim_config.yml"
  fi

  if [[ -z "$SERVE_CONFIG" ]]; then
    warn "No obvious example config found to serve. You can run 'nat serve --config_file <path>' manually."
  else
    log "Starting nat serve using $SERVE_CONFIG (logs -> $LOG_DIR/nat_serve.log)"
    nohup $NAT_CMD serve --config_file "$SERVE_CONFIG" --host 0.0.0.0 --port 8000 >"$LOG_DIR/nat_serve.log" 2>&1 &
    sleep 1
  fi

  # Start MCP server exposing an example MCP tool if available
  # Try to pick a config that includes an mcp tool (best-effort). We'll fallback to same SERVE_CONFIG.
  if [[ -n "$SERVE_CONFIG" ]]; then
    log "Starting nat mcp using $SERVE_CONFIG (logs -> $LOG_DIR/nat_mcp.log)"
    nohup $NAT_CMD mcp --config_file "$SERVE_CONFIG" --tool_names mcp_retriever_tool >"$LOG_DIR/nat_mcp.log" 2>&1 &
    sleep 1 || true
  fi

  log "nat serve and nat mcp background processes requested. Allow a few seconds for startup."
  sleep "$SLEEP_AFTER_START"
}

start_profiling_and_observability_guidance() {
  log "Profiling & Observability guidance"
  cat <<EOF

- Phoenix observability is provided as an example. If docker compose started Phoenix (examples/deploy/docker-compose.phoenix.yml),
  check logs: $LOG_DIR/docker-compose.phoenix.yml.log
- To enable profiling in workflows, use the built-in profiler tools and the 'nat' workflow configuration flags.
  See docs: docs/source/workflows/profiler.md and docs/source/workflows/observe/index.md

EOF
}

install_examples_and_workflows() {
  if [[ "$SKIP_EXAMPLES" == "true" ]]; then
    log "Skipping example installation (--skip-examples)."
    return 0
  fi

  log "Installing a curated set of example workflows (best-effort)..."
  # Attempt to pip install the examples that are friendly to 'pip install -e'
  EXAMPLES_TO_INSTALL=(
    "examples/getting_started/simple_web_query"
    "examples/memory/redis"
    "examples/HITL/por_to_jiratickets"
  )
  for ex in "${EXAMPLES_TO_INSTALL[@]}"; do
    if [[ -d "$ex" ]]; then
      log "Installing example: $ex"
      if check_cmd uv; then
        uv pip install -e "$ex" >/dev/null 2>&1 || warn "uv pip install failed for $ex"
      else
        pip install -e "$ex" >/dev/null 2>&1 || warn "pip install failed for $ex"
      fi
    else
      warn "Example not present in repo: $ex"
    fi
  done
  log "Example installation attempts complete."
}

final_summary() {
  cat <<EOF

================================================================================
NeMo Agent Toolkit Single-Click Deploy Summary
--------------------------------------------------------------------------------
Repository root: $(pwd)
Log directory:    $(pwd)/$LOG_DIR

Key services (if started):
 - Docker Compose logs: $LOG_DIR/*.log (e.g. docker-compose.redis.yml.log, docker-compose.phoenix.yml.log)
 - nat Hello World run: $LOG_DIR/nat_hello_world.log
 - nat serve: $LOG_DIR/nat_serve.log
 - nat mcp:   $LOG_DIR/nat_mcp.log

Next recommended manual steps (if you want to exercise more features):
 - Ensure NVIDIA_API_KEY is set:
     export NVIDIA_API_KEY=<your_api_key>
 - If you want local LLM servers (vLLM / NIM), follow docs in:
     docs/source/workflows/llms/using-local-llms.md
 - To run memory/redis example:
     nat run --config_file examples/memory/redis/configs/config.yml --input "my favorite flavor is strawberry"
 - To run HITL Jira example:
     export JIRA_USERID=<your_jira_id>; export JIRA_TOKEN=<your_jira_token>
     nat run --config_file examples/HITL/por_to_jiratickets/configs/config.yml --input "<your input>"
 - To serve a workflow via FastAPI and view UI:
     Visit http://localhost:8000 (if nat serve started successfully)

If anything failed, check logs in: $LOG_DIR
================================================================================

EOF
}

# MAIN FLOW
create_and_activate_venv
install_repo_and_extras
install_examples_and_workflows
start_docker_services
run_hello_world
start_nat_servers
start_profiling_and_observability_guidance
final_summary

exit 0