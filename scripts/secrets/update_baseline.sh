#!/usr/bin/env bash
# Run detect-secrets and show new findings compared to baseline
set -euo pipefail
pip install --quiet detect-secrets
detect-secrets audit .secrets.baseline || true
