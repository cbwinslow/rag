#!/usr/bin/env bash
set -euo pipefail
cat <<'EOF'
Wrangler secret setup helper (local guidance)

Use this script as a reminder. Do not store your tokens in the repo.

1) Create a Cloudflare API token scoped for Workers & Pages.
2) Save it in GitHub repo secrets: CF_API_TOKEN and CF_ACCOUNT_ID
3) To set a secret for wrangler locally, run:
   wrangler secret put GOVINFO_API_KEY

EOF
