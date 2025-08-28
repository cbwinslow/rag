Launch helper scripts for NVIDIA RAG Blueprint

This folder contains a convenience script to configure environment variables and launch the repository using Docker Compose.

Files:
- `launch.sh` - Interactive launcher that sources `deploy/compose/.env`, allows optional profiles (`accuracy` or `perf`), and starts services in the recommended order. It can also stop services started by the script.
 - `configure_disk.sh` - Interactive script to plan and apply disk configuration (LVM/PV/LV or direct filesystem), supports remote execution via SSH. Dry-run by default; requires `--apply` to execute.
 - `spread_ssh_keys.sh` - Copy your SSH public key to many hosts, creating `~/.ssh/authorized_keys` entries for passwordless access.

Basic usage examples:

1) Start with default on-prem configuration:
   ./scripts/launch.sh

2) Start with accuracy profile applied:
   ./scripts/launch.sh --profile accuracy

3) Use NVIDIA-hosted models (cloud endpoints):
   ./scripts/launch.sh --mode cloud

4) Stop services started by the script:
   ./scripts/launch.sh --stop

See `./scripts/launch.sh -h` for full options.
