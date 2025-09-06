#!/usr/bin/env bash
# Install a git template directory that contains a pre-commit hook to block likely secrets.
set -euo pipefail
TEMPLATE_DIR="$HOME/.git-templates"
mkdir -p "$TEMPLATE_DIR/hooks"
cp "$(dirname "$0")/pre-commit" "$TEMPLATE_DIR/hooks/pre-commit"
chmod +x "$TEMPLATE_DIR/hooks/pre-commit"
# Configure git to use the template for new repositories
git config --global init.templateDir "$TEMPLATE_DIR"
cat <<'EOF'
Installed global git template with pre-commit hook.
New repositories created with `git init` will include the hook.
To apply to an existing repo, run:
  git init
EOF
