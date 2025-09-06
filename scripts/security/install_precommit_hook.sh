#!/usr/bin/env bash
# Simple installer to wire the pre-commit secret scan into .git/hooks/pre-commit
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_PATH="$REPO_ROOT/.git/hooks/pre-commit"
SCRIPT_PATH="$REPO_ROOT/scripts/security/precommit_secret_scan.sh"

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "precommit scanner not found at $SCRIPT_PATH"
  exit 1
fi

cat > "$HOOK_PATH" <<'HOOK'
#!/usr/bin/env bash
# Auto-generated pre-commit hook to run the secret scanner
"$(dirname "$0")/../../scripts/security/precommit_secret_scan.sh"
RESULT=$?
if [ $RESULT -ne 0 ]; then
  echo "pre-commit secret scan failed; aborting commit"
  exit 1
fi
exit 0
HOOK

chmod +x "$HOOK_PATH"
echo "Installed pre-commit hook at $HOOK_PATH"
