# Cloudflare Pages Deployment Guide

## Overview

Your RAG post-install script has been successfully prepared for Cloudflare Pages deployment. The script is validated and ready to be hosted as a web page that can be piped directly to bash.

## What's Been Created

### 📁 Pages Site Structure
```
scripts/cloudflare/pages-site/
├── index.html              # Web interface with installation instructions
├── post_install.sh         # Raw bash script for piping to bash
├── keys/
│   └── rag_deploy.pub      # Example public SSH key
├── wrangler.toml           # Cloudflare Pages configuration
├── validate.sh             # Script validation tool
└── README.md              # Documentation
```

### 🔧 Deployment Scripts
- `scripts/cloudflare/deploy_remote.sh` - Deploy Pages and Workers
- `scripts/cloudflare/auto_setup.sh` - Setup secrets and deployment

## Deployment Steps

### 1. Set Up Cloudflare Credentials

Add these lines to your `~/.bash_secrets` file:

```bash
export CF_API_TOKEN='gKob2mQisfZo4JlzOmNct1VR9IEK0rn2rTFM4hH0'
export CF_ACCOUNT_ID='968ff4ee9f5e59bc6c72758269d6b9d6'
export GOVINFO_API_KEY='your_govinfo_api_key_here'
export AUTORAG_API_KEY='your_autorag_api_key_here'
export REPO='cbwinslow/rag'
```

### 2. Authenticate Wrangler

```bash
cd /home/cbwinslow/rag
source ~/.bash_secrets
wrangler login
```

### 3. Deploy the Pages Site

```bash
# Deploy just the Pages site
./scripts/cloudflare/deploy_remote.sh --publish-pages

# Or deploy everything (Workers + Pages)
./scripts/cloudflare/deploy_remote.sh --publish-worker --publish-pages
```

## Usage After Deployment

### Direct Script Installation
```bash
# Basic installation
curl -fsSL https://rag-install.pages.dev/post_install.sh | sudo bash

# With SSH key setup
curl -fsSL https://rag-install.pages.dev/post_install.sh | sudo PUBLIC_KEY_URL=https://rag-install.pages.dev/keys/rag_deploy.pub bash

# Custom configuration
curl -fsSL https://rag-install.pages.dev/post_install.sh | sudo \
  PUBLIC_KEY_URL=https://rag-install.pages.dev/keys/rag_deploy.pub \
  REPO_URL=https://github.com/your-org/your-repo.git \
  TARGET_USER=youruser \
  bash
```

### Web Interface
Visit `https://rag-install.pages.dev` for:
- Installation instructions
- Script preview
- Copy-to-clipboard functionality
- Security notes

## Script Features

✅ **Idempotent** - Safe to run multiple times
✅ **Multi-platform** - Supports apt, dnf, yum, pacman
✅ **Comprehensive** - Installs Docker, Helm, kubectl
✅ **Secure** - SSH key management with proper permissions
✅ **Logged** - All actions logged to `/var/log/rag_post_install.log`
✅ **Configurable** - Environment variable driven

## Validation Results

- ✅ Bash syntax check passed
- ✅ All required functions present
- ✅ All required variables present
- ✅ Help output functional
- ✅ Script size appropriate (230 lines)

## Next Steps

1. **Add your real SSH public key** to `scripts/cloudflare/pages-site/keys/rag_deploy.pub`
2. **Update the repository URL** in `wrangler.toml` if different
3. **Deploy to Cloudflare** using the commands above
4. **Test the installation** on a new machine
5. **Customize the web interface** styling/colors as needed

## Troubleshooting

### If deployment fails:
```bash
# Check wrangler authentication
wrangler whoami

# Check your credentials
source ~/.bash_secrets && echo "Token: ${CF_API_TOKEN:0:10}..." && echo "Account: $CF_ACCOUNT_ID"
```

### If script doesn't work:
```bash
# Test locally first
cd scripts/cloudflare/pages-site
bash post_install.sh --help

# Validate script
./validate.sh
```

## Security Considerations

- The script requires root/sudo access for system installations
- Review script content before running on production systems
- SSH keys are appended to `authorized_keys` (idempotent operation)
- All installations are logged for audit purposes
- No sensitive data is exposed in the hosted script

## Integration with RAG System

This installation script complements your existing RAG deployment by:
- Preparing machines for Docker-based deployments
- Setting up Kubernetes tooling (Helm, kubectl)
- Installing SSH keys for remote access
- Cloning your RAG repository
- Running your provisioning scripts

The script works seamlessly with your existing `scripts/provision/init_proxmox_setup.sh` and other automation tools.
