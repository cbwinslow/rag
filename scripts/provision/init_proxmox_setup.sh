#!/usr/bin/env bash
set -euo pipefail

# init_proxmox_setup.sh
# Install prerequisites on a Debian/Ubuntu-based Proxmox host to run containers and K8s tooling.
# This script is idempotent and safe to re-run.

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo" >&2
  exit 1
fi

apt update
apt install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common git unzip wget

# Install Docker Engine using official repository
if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker..."
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
else
  echo "Docker already installed"
fi

# Add current user to docker group if not root
if [ -n "$SUDO_USER" ]; then
  usermod -aG docker "$SUDO_USER" || true
fi

# Install helm
if ! command -v helm >/dev/null 2>&1; then
  echo "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "Helm already installed"
fi

# Install kubectl
if ! command -v kubectl >/dev/null 2>&1; then
  echo "Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
else
  echo "kubectl already installed"
fi

echo "Prerequisites installed. You may need to log out and back in to refresh group membership for docker access."

exit 0
