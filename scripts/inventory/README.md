Inventory collector
-------------------

This small tool collects Cloudflare and Proxmox assets into `data/assets_inventory.json` using environment variables for credentials.

Requirements:
- Node.js (v16+)
- Set `CF_API_TOKEN` and `CF_ACCOUNT_ID` for Cloudflare
- Set `PROXMOX_HOST` and either `PROXMOX_API_TOKEN` or `PROXMOX_USER`/`PROXMOX_PASS` for Proxmox

Run:

```bash
export CF_API_TOKEN=... CF_ACCOUNT_ID=... PROXMOX_HOST=... PROXMOX_API_TOKEN=...
scripts/inventory/run_inventory.sh
```
