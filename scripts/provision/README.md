Proxmox provisioning helpers

This folder contains helper scripts to prepare a Proxmox (Debian-based) host to run containers and to launch a set of self-hosted applications.

Scripts:
- `init_proxmox_setup.sh` -- install Docker, Helm, kubectl
- `provision_apps.sh` -- create a simple `deploy/host-compose.yml`, clone a few external repos and provide a starting point for deploying services like Nextcloud, LocalAI, Flowise, Supabase, etc.

Notes and next steps:
- The compose file is a minimal template. You should review and harden credentials before running in production.
- Many of the services (AnythingLLM, OpenWebUI, LocalAI, Flowise) have specific install instructions; this repo's scripts provide a starting point only.
- For more robust deployments, consider using Kubernetes with the Helm charts for each project and managing secrets via Vault or Kubernetes Secrets.
