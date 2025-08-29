#!/usr/bin/env bash
set -euo pipefail

# generate_supabase_env.sh
# Generates a .env.supabase file with required secrets for the local docker-compose supabase stack.

OUTFILE=".env.supabase"
echo "Generating $OUTFILE"

function write_env() {
  key="$1"
  val="$2"
  echo "$key=$val" >> "$OUTFILE"
}

if [ -f "$OUTFILE" ]; then
  echo "$OUTFILE already exists. Backing up to ${OUTFILE}.$(date +%s)"
  mv "$OUTFILE" "${OUTFILE}.$(date +%s)"
fi

touch "$OUTFILE"


BW_AVAILABLE=false
if command -v bw >/dev/null 2>&1; then
  BW_AVAILABLE=true
fi

echo "# Generated Supabase env for local docker-compose" > "$OUTFILE"

if [ "$BW_AVAILABLE" = true ]; then
  echo "Bitwarden CLI detected. Attempting to read secrets from your vault (interactive)."
  echo "Make sure you are logged in (bw login) and have an active session (eval \"$(bw unlock --raw)\")."

  read -rp "Enter Bitwarden item id or name that contains supabase secrets (or leave blank to skip): " BW_ITEM

  if [ -n "$BW_ITEM" ]; then
    # Try to fetch fields by common names; fall back to interactive prompts
    fetch_field() {
      field_name="$1"
      val=""
      if bw get item "$BW_ITEM" >/dev/null 2>&1; then
        val=$(bw get item "$BW_ITEM" | jq -r '.fields[]? | select(.name=="'"$field_name"'") | .value' 2>/dev/null || true)
      fi
      echo "$val"
    }

  POSTGRES_PASSWORD_VAL=$(fetch_field "POSTGRES_PASSWORD")
  JWT_SECRET_VAL=$(fetch_field "JWT_SECRET")
  SUPABASE_ANON_KEY_VAL=$(fetch_field "SUPABASE_ANON_KEY")
  SUPABASE_SERVICE_ROLE_KEY_VAL=$(fetch_field "SUPABASE_SERVICE_ROLE_KEY")
  fi
fi

prompt_if_empty() {
  varname="$1"
  curval="$2"
  prompt="$3"
  if [ -n "$curval" ]; then
    echo "$varname already set"
    echo "$varname=$curval" >> "$OUTFILE"
  else
    # If running non-interactively (no TTY), don't prompt — generate a random value
    if [ -t 0 ]; then
      read -rp "$prompt: " val || val=""
    else
      val=""
    fi
    if [ -z "$val" ]; then
      echo "No value provided. Generating a random value for $varname."
      val=$(openssl rand -hex 32)
    fi
    echo "$varname=$val" >> "$OUTFILE"
  fi
}


# Prefer environment variables if provided, then Bitwarden values, then prompt/generate
prompt_if_empty "POSTGRES_PASSWORD" "${POSTGRES_PASSWORD:-${POSTGRES_PASSWORD_VAL:-}}" "Postgres password"
prompt_if_empty "JWT_SECRET" "${JWT_SECRET:-${JWT_SECRET_VAL:-}}" "JWT secret (used by PostgREST/Gotrue)"
prompt_if_empty "SUPABASE_ANON_KEY" "${SUPABASE_ANON_KEY:-${SUPABASE_ANON_KEY_VAL:-}}" "Supabase anon key (public)"
prompt_if_empty "SUPABASE_SERVICE_ROLE_KEY" "${SUPABASE_SERVICE_ROLE_KEY:-${SUPABASE_SERVICE_ROLE_KEY_VAL:-}}" "Supabase service role key (private)"

# Determine a host port for Postgres (allow overriding via POSTGRES_HOST_PORT). If 5432 is free, use it; otherwise pick next free port.
find_free_port() {
  start=${1:-5432}
  for p in $(seq $start $((start+1000))); do
    if ! ss -ltn "sport = :$p" 2>/dev/null | grep -q LISTEN; then
      echo $p
      return
    fi
  done
  echo "$start"
}

if [ -z "${POSTGRES_HOST_PORT:-}" ]; then
  free_port=$(find_free_port 5432)
  echo "POSTGRES_HOST_PORT=$free_port" >> "$OUTFILE"
else
  echo "POSTGRES_HOST_PORT=${POSTGRES_HOST_PORT}" >> "$OUTFILE"
fi

echo "# Default DB settings" >> "$OUTFILE"
echo "POSTGRES_USER=postgres" >> "$OUTFILE"
echo "POSTGRES_DB=postgres" >> "$OUTFILE"

echo "Wrote $OUTFILE. Keep it safe and add to .gitignore if needed."
