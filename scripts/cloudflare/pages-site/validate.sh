#!/usr/bin/env bash
set -euo pipefail

# validate_post_install.sh
# Validate the post-install script for syntax and basic functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/post_install.sh"

echo "Validating post-install script: $SCRIPT_PATH"

# Check if script exists
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "❌ Script not found: $SCRIPT_PATH"
    exit 1
fi

# Check if script is executable
if [ ! -x "$SCRIPT_PATH" ]; then
    echo "⚠️  Script is not executable, making it executable..."
    chmod +x "$SCRIPT_PATH"
fi

# Basic syntax check
echo "🔍 Checking bash syntax..."
if bash -n "$SCRIPT_PATH"; then
    echo "✅ Syntax check passed"
else
    echo "❌ Syntax check failed"
    exit 1
fi

# Check for required functions
echo "🔍 Checking for required functions..."
required_functions=("ensure_packages" "install_docker" "install_helm_kubectl" "add_public_key" "ensure_user" "clone_repo" "run_init_provision" "main")
for func in "${required_functions[@]}"; do
    if grep -q "^${func}()" "$SCRIPT_PATH"; then
        echo "✅ Function found: $func"
    else
        echo "❌ Function missing: $func"
        exit 1
    fi
done

# Check for required variables
echo "🔍 Checking for required variables..."
required_vars=("PUBLIC_KEY_URL" "REPO_URL" "TARGET_USER" "CHEZMOI_APPLY" "ARTIFACT_URL")
for var in "${required_vars[@]}"; do
    if grep -q "${var}=" "$SCRIPT_PATH"; then
        echo "✅ Variable found: $var"
    else
        echo "❌ Variable missing: $var"
        exit 1
    fi
done

# Test help output
echo "🔍 Testing help output..."
if "$SCRIPT_PATH" -h >/dev/null 2>&1; then
    echo "✅ Help output works"
else
    echo "❌ Help output failed"
    exit 1
fi

# Check script size
script_size=$(wc -l < "$SCRIPT_PATH")
if [ "$script_size" -gt 50 ]; then
    echo "✅ Script size looks good ($script_size lines)"
else
    echo "⚠️  Script seems small ($script_size lines), check if complete"
fi

echo ""
echo "🎉 Post-install script validation complete!"
echo ""
echo "To test the script locally (dry-run):"
echo "  bash $SCRIPT_PATH --help"
echo ""
echo "To deploy to Cloudflare Pages:"
echo "  1. Set up CF_API_TOKEN and CF_ACCOUNT_ID in ~/.bash_secrets"
echo "  2. Run: wrangler login (or use API token)"
echo "  3. Run: ./scripts/cloudflare/deploy_remote.sh --publish-pages"
echo ""
echo "Installation URLs after deployment:"
echo "  Web interface: https://rag-install.pages.dev"
echo "  Direct script: https://rag-install.pages.dev/post_install.sh"
echo "  Public key:    https://rag-install.pages.dev/keys/rag_deploy.pub"
