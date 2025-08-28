# RAG Install Pages Site

This Cloudflare Pages site hosts the post-install script and related resources for bootstrapping new RAG deployment machines.

## Files

- `index.html` - Main web page with installation instructions and script preview
- `post_install.sh` - Raw bash script for piping to bash
- `keys/rag_deploy.pub` - Example public SSH key
- `wrangler.toml` - Cloudflare Pages configuration

## Usage

### Direct Script Installation

```bash
# Install on a new machine
curl -fsSL https://rag-install.pages.dev/post_install.sh | sudo bash
```

### With Public Key

```bash
# Install with SSH key setup
curl -fsSL https://rag-install.pages.dev/post_install.sh | sudo PUBLIC_KEY_URL=https://rag-install.pages.dev/keys/rag_deploy.pub bash
```

### Advanced Options

```bash
# Custom repository and user
curl -fsSL https://rag-install.pages.dev/post_install.sh | sudo \
  PUBLIC_KEY_URL=https://rag-install.pages.dev/keys/rag_deploy.pub \
  REPO_URL=https://github.com/your-org/your-repo.git \
  TARGET_USER=youruser \
  bash
```

## What the Script Does

1. **Package Installation**: Installs curl, git, and other prerequisites
2. **Docker Setup**: Installs Docker Engine and Docker Compose
3. **Kubernetes Tools**: Installs Helm and kubectl
4. **SSH Key Management**: Downloads and installs public SSH keys
5. **User Management**: Creates specified users with sudo access
6. **Repository Cloning**: Clones the RAG repository to `/opt/rag`
7. **Provisioning**: Runs additional setup scripts from the cloned repo

## Deployment

### Local Development

```bash
cd scripts/cloudflare/pages-site
wrangler pages dev
```

### Production Deployment

```bash
# From project root
./scripts/cloudflare/deploy_remote.sh --publish-pages
```

## Environment Variables

The script supports these environment variables:

- `PUBLIC_KEY_URL` - URL to download public SSH key
- `REPO_URL` - Git repository to clone (default: cbwinslow/rag)
- `TARGET_USER` - User to create/install keys for (default: root)
- `CHEZMOI_APPLY` - Run chezmoi apply if available (default: false)
- `ARTIFACT_URL` - URL to download additional artifacts

## Security Notes

- The script requires root/sudo access for system installations
- Review the script content before running on production systems
- SSH keys are appended to `authorized_keys` (idempotent)
- All actions are logged to `/var/log/rag_post_install.log`

## Customization

To customize for your environment:

1. Update the public key in `keys/rag_deploy.pub`
2. Modify the default `REPO_URL` in `wrangler.toml` vars section
3. Update the installation instructions in `index.html`
4. Add additional resources or documentation as needed
