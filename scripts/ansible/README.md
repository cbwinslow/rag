Ansible playbook to deploy NVIDIA RAG Blueprint to a remote host

This directory contains a minimal Ansible playbook and inventory template to copy the repository to a remote host and run the included launcher script there.

Prerequisites:
- Ansible installed locally
- SSH access to remote host with key or passwordless sudo (recommended)
- Docker & docker-compose installed on remote host (see repo README quickstart)

Usage example:

1. Edit `inventory.ini` and set your remote host or pass -i.

2. Run the playbook:

```bash
ansible-playbook -i scripts/ansible/inventory.ini scripts/ansible/deploy.yaml --extra-vars "remote_path=/opt/rag deploy_profile=accuracy"
```

Supported extra-vars:
- remote_user (default: current user)
- remote_path (where to copy the repo)
- deploy_profile (accuracy|perf|none)
- ngc_api_key (NGC API key to export on remote)
