#!/usr/bin/env bash
set -euo pipefail

# Log everything
LOG_FILE="/var/log/rag_post_install.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# post_install.sh
# Comprehensive, idempotent post-install/bootstrap script for new machines.
# Usage (recommended): run as root on the new machine:
#   PUBLIC_KEY_URL="https://example.com/keys/rag_deploy.pub" REPO_URL="https://github.com/cbwinslow/rag.git" bash -s --
# The script will:
#  - install minimal prerequisites (curl, git)
#  - install Docker, Helm, kubectl (on Debian/Ubuntu)
#  - fetch and install the provided public SSH key into the specified user's authorized_keys
#  - clone the repo into /opt/rag (if not present)
#  - run the repo's `scripts/provision/init_proxmox_setup.sh` to finish host prep
#  - install Anaconda/Miniconda for Python development
#  - set up a comprehensive development environment (Python, Node.js, Rust, Go, Neovim, tmux, etc.)
#  - optionally apply chezmoi dotfiles for configuration

PUBLIC_KEY_URL="${PUBLIC_KEY_URL:-}"
REPO_URL="${REPO_URL:-https://github.com/cbwinslow/rag.git}"
TARGET_USER="${TARGET_USER:-root}"
CHEZMOI_APPLY="${CHEZMOI_APPLY:-false}"
ARTIFACT_URL="${ARTIFACT_URL:-}"

# detect package manager
PKG_MANAGER=""
if command -v apt >/dev/null 2>&1; then
  PKG_MANAGER="apt"
elif command -v dnf >/dev/null 2>&1; then
  PKG_MANAGER="dnf"
elif command -v yum >/dev/null 2>&1; then
  PKG_MANAGER="yum"
elif command -v pacman >/dev/null 2>&1; then
  PKG_MANAGER="pacman"
fi

echo "Detected package manager: ${PKG_MANAGER:-unknown}"

show_help(){
  cat <<EOF
Usage: PUBLIC_KEY_URL=... REPO_URL=... TARGET_USER=... bash post_install.sh

Environment variables:
  PUBLIC_KEY_URL  URL to the public SSH key file to add to authorized_keys (recommended)
  REPO_URL        Git URL of the repo to clone (default: https://github.com/cbwinslow/rag.git)
  TARGET_USER     User to install the public key for (default root)
  CHEZMOI_APPLY   If true and chezmoi is installed, run 'chezmoi apply' after adding keys (default false)
  ARTIFACT_URL    URL to a tar.gz artifact to download and extract (optional)

This script will:
  - Install minimal prerequisites (curl, git, etc.)
  - Install Docker, Helm, kubectl
  - Add the provided public SSH key to authorized_keys
  - Clone the RAG repository
  - Run initial provisioning scripts
  - Install Anaconda/Miniconda
  - Set up a comprehensive development environment (Python, Node.js, Rust, Go, etc.)
  - Optionally apply chezmoi dotfiles

Example:
  curl -fsSL https://example.com/post_install.sh | sudo PUBLIC_KEY_URL=https://example.com/keys/rag_deploy.pub bash
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then show_help; exit 0; fi

if [ -z "$PUBLIC_KEY_URL" ]; then
  echo "WARNING: PUBLIC_KEY_URL not set. You can still run this script but no SSH key will be installed."
  echo "Set PUBLIC_KEY_URL to a raw URL that serves a public SSH key, e.g. https://your-site/keys/rag_deploy.pub"
  sleep 2
fi

ensure_packages(){
  case "$PKG_MANAGER" in
    apt)
      apt update -y || true
      DEBIAN_FRONTEND=noninteractive apt install -y curl git ca-certificates gnupg lsb-release software-properties-common sudo || true
      ;;
    dnf)
      dnf install -y curl git ca-certificates gnupg2 sudo || true
      ;;
    yum)
      yum install -y curl git ca-certificates gnupg2 sudo || true
      ;;
    pacman)
      pacman -Sy --noconfirm curl git ca-certificates gnupg sudo || true
      ;;
    *)
      echo "No supported package manager found; ensure curl and git are installed manually."
      ;;
  esac
}

install_docker(){
  if command -v docker >/dev/null 2>&1; then
    echo "Docker already installed"
    return
  fi
  case "$PKG_MANAGER" in
    apt)
      echo "Installing Docker Engine (apt)..."
      curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || true
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
      apt update -y || true
      apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
      systemctl enable --now docker || true
      ;;
    dnf|yum)
      echo "Installing Docker Engine (dnf/yum)..."
      dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo || true
      dnf install -y docker-ce docker-ce-cli containerd.io || true
      systemctl enable --now docker || true
      ;;
    pacman)
      pacman -S --noconfirm docker docker-compose || true
      systemctl enable --now docker || true
      ;;
    *)
      echo "Please install Docker manually for this OS"
      ;;
  esac
}

install_helm_kubectl(){
  if ! command -v helm >/dev/null 2>&1; then
    echo "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash || true
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "Installing kubectl..."
    KUBE_REL=$(curl -L -s https://dl.k8s.io/release/stable.txt || echo "")
    if [ -n "$KUBE_REL" ]; then
      curl -LO "https://dl.k8s.io/release/${KUBE_REL}/bin/linux/amd64/kubectl" || true
      install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl || true
      rm -f kubectl || true
    fi
  fi
}

add_public_key(){
  if [ -z "$PUBLIC_KEY_URL" ]; then
    echo "No PUBLIC_KEY_URL provided; skipping SSH key installation."; return
  fi
  echo "Fetching public key from $PUBLIC_KEY_URL"
  if [ "$TARGET_USER" = "root" ]; then
    SSH_DIR="/root/.ssh"
  else
    SSH_DIR="/home/$TARGET_USER/.ssh"
  fi
  mkdir -p "$SSH_DIR"
  # Fetch then ensure idempotent append: only append if key not present
  TMPKEY=$(mktemp)
  if ! curl -fsSL "$PUBLIC_KEY_URL" -o "$TMPKEY"; then
    echo "Failed to fetch public key from $PUBLIC_KEY_URL"; rm -f "$TMPKEY"; return 1
  fi
  if ! grep -Fxf "$TMPKEY" "$SSH_DIR/authorized_keys" >/dev/null 2>&1; then
    cat "$TMPKEY" >> "$SSH_DIR/authorized_keys"
    echo "Appended public key to $SSH_DIR/authorized_keys"
  else
    echo "Public key already present in $SSH_DIR/authorized_keys"
  fi
  rm -f "$TMPKEY"
  chmod 700 "$SSH_DIR"
  chmod 600 "$SSH_DIR/authorized_keys"
  if [ "$TARGET_USER" != "root" ]; then
    chown -R "$TARGET_USER":"$TARGET_USER" "$SSH_DIR"
  fi
}

ensure_user(){
  if [ "$TARGET_USER" = "root" ]; then return; fi
  if id -u "$TARGET_USER" >/dev/null 2>&1; then
    echo "User $TARGET_USER exists"
  else
    echo "Creating user $TARGET_USER and adding to sudo"
    case "$PKG_MANAGER" in
      pacman)
        useradd -m -s /bin/bash "$TARGET_USER" || true
        ;;
      *)
        adduser --disabled-password --gecos "" "$TARGET_USER" || useradd -m -s /bin/bash "$TARGET_USER" || true
        ;;
    esac
    usermod -aG sudo "$TARGET_USER" || true
  fi
}

clone_repo(){
  if [ -z "$REPO_URL" ]; then return; fi
  if [ ! -d /opt/rag ]; then
    git clone "$REPO_URL" /opt/rag || true
  else
    echo "/opt/rag already exists; skipping clone"
    # optionally pull
    (cd /opt/rag && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git pull --ff-only) || true
  fi
}

run_init_provision(){
  if [ -f /opt/rag/scripts/provision/init_proxmox_setup.sh ]; then
    bash /opt/rag/scripts/provision/init_proxmox_setup.sh || true
  fi
}

install_anaconda(){
  if [ -f /opt/rag/scripts/installer/install_anaconda.sh ]; then
    echo "Installing Anaconda..."
    bash /opt/rag/scripts/installer/install_anaconda.sh || true
  fi
}

setup_dev_environment(){
  if [ -f /opt/rag/scripts/installer/setup_dev_environment.sh ]; then
    echo "Setting up development environment..."
    bash /opt/rag/scripts/installer/setup_dev_environment.sh || true
  fi
}

fetch_artifact(){
  if [ -z "$ARTIFACT_URL" ]; then return; fi
  echo "Fetching artifact from $ARTIFACT_URL"
  TMPA=$(mktemp -d)
  pushd "$TMPA" >/dev/null || return
  if curl -fsSL "$ARTIFACT_URL" -o artifact.tar.gz; then
    tar xzf artifact.tar.gz || true
    echo "Extracted artifact to $TMPA"
    # If artifact contains an install.sh, run it as root (careful)
    if [ -f install.sh ]; then
      chmod +x install.sh
      ./install.sh || true
    fi
  else
    echo "Failed to download artifact from $ARTIFACT_URL"
  fi
  popd >/dev/null || true
}

main(){
  ensure_packages
  ensure_user
  install_docker
  install_helm_kubectl
  add_public_key
  fetch_artifact
  clone_repo
  run_init_provision
  install_anaconda
  setup_dev_environment
  if [ "$CHEZMOI_APPLY" = "true" ] && command -v chezmoi >/dev/null 2>&1; then
    echo "Running chezmoi apply"
    chezmoi apply || true
  fi
  echo "Bootstrap complete. Review /opt/rag and logs at $LOG_FILE for next steps."
}

main "$@"
