#!/usr/bin/env bash
# Scan the repo and create/update the detect-secrets baseline
set -euo pipefail
pip install --quiet detect-secrets
# Create baseline (overwrites .secrets.baseline)
detect-secrets scan --update .secrets.baseline
echo "Baseline updated: .secrets.baseline"
