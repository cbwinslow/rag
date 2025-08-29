#!/bin/bash
# Dynamic Infrastructure Setup Script
set -eo pipefail

# Install core dependencies
apt-get update && apt-get install -y \
    docker.io \
    podman \
    python3-pip \
    nginx \
    certbot

# Configure container orchestration
pip install docker-compose

# Create dynamic nginx config template
cat > /etc/nginx/sites-available/dynamic.conf <<EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    location / {
        proxy_pass http://127.0.0.1:\$service_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOL

# Enable required ports
ufw allow 80,443,8000-8100/tcp

# Create docker network
docker network create ai-net