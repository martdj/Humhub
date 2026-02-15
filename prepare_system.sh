#!/bin/bash
set -e

# ==================================================
# HumHub Docker Host Preparation Script
# Version: 1.0.0
#
# This script prepares a RHEL-based system to run
# HumHub using Docker Compose.
#
# Supported OS:
#   - CentOS
#   - Rocky Linux
#   - AlmaLinux
#
# Author: martdj
# ==================================================

VERSION="1.0.1"

HUMHUB_USER="humhub"
HUMHUB_DIR="/local/humhub"
DATA_DIR="$HUMHUB_DIR/data"

ENV_URL="https://raw.githubusercontent.com/martdj/Humhub/refs/heads/main/.env"
COMPOSE_URL="https://raw.githubusercontent.com/martdj/Humhub/refs/heads/main/docker-compose.yml"
SCRIPT_URL="https://raw.githubusercontent.com/martdj/Humhub/refs/heads/main/prepare_system.env"
SCRIPT_PATH="$HUMHUB_DIR/prepare_system.sh"

echo "=================================================="
echo " HumHub Host Preparation Script"
echo " Version: $VERSION"
echo "=================================================="
echo

# --------------------------------------------------
# Base requirements
# --------------------------------------------------
dnf install -y curl yum-utils firewalld

# --------------------------------------------------
# Docker check & installation
# --------------------------------------------------
if ! command -v docker &>/dev/null; then
    echo "Docker not found, installing..."
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    systemctl enable --now docker
else
    echo "Docker is already installed"
fi

# --------------------------------------------------
# SELinux configuration (if enabled)
# --------------------------------------------------
if command -v getenforce &>/dev/null && [ "$(getenforce)" != "Disabled" ]; then
    echo "Configuring SELinux for containers"
    setsebool -P container_manage_cgroup on
fi

# --------------------------------------------------
# System user
# --------------------------------------------------
if ! id "$HUMHUB_USER" &>/dev/null; then
    echo "Creating user: $HUMHUB_USER"
    useradd "$HUMHUB_USER"
fi

# --------------------------------------------------
# Directory structure
# --------------------------------------------------
echo "Creating directory structure"

mkdir -p \
  $DATA_DIR/db-data \
  $DATA_DIR/humhub/{config,uploads,modules,logs,searchdb,themes} \
  $DATA_DIR/onlyoffice/{data,log} \
  $DATA_DIR/backups \
  $DATA_DIR/traefik/letsencrypt

touch $DATA_DIR/traefik/letsencrypt/acme.json
chmod 600 $DATA_DIR/traefik/letsencrypt/acme.json


# --------------------------------------------------
# Safety check for existing database data
# --------------------------------------------------
if [ -d "$DATA_DIR/db-data" ] && [ "$(ls -A "$DATA_DIR/db-data")" ]; then
    echo "⚠ WARNING: Database directory is not empty:"
    echo "  $DATA_DIR/db-data"
fi

# --------------------------------------------------
# Download configuration files
# --------------------------------------------------
cd "$HUMHUB_DIR"

if [ ! -f .env ]; then
    echo "Downloading .env"
    curl -fsSL "$ENV_URL" -o .env
fi

if [ ! -f docker-compose.yml ]; then
    echo "Downloading docker-compose.yml"
    curl -fsSL "$COMPOSE_URL" -o docker-compose.yml
fi

# Validate downloads
[ -s .env ] || { echo "ERROR: .env file is empty"; exit 1; }
[ -s docker-compose.yml ] || { echo "ERROR: docker-compose.yml is empty"; exit 1; }

# --------------------------------------------------
# Save provisioning script locally
# --------------------------------------------------
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Saving provisioning script to $SCRIPT_PATH"
    curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
fi

# --------------------------------------------------
# Permissions
# --------------------------------------------------
chown -R $HUMHUB_USER:$HUMHUB_USER "$HUMHUB_DIR"
chmod -R 755 "$DATA_DIR"
chmod 600 $DATA_DIR/traefik/letsencrypt/acme.json

# --------------------------------------------------
# Firewall configuration
# --------------------------------------------------
echo "Configuring firewall"
systemctl enable --now firewalld

firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --reload

# --------------------------------------------------
# Pull Docker images (do not start stack)
# --------------------------------------------------
echo "Pulling Docker images"
docker compose pull

# --------------------------------------------------
# Optional interactive .env editing
# --------------------------------------------------
echo
echo "=================================================="
echo "Edit the .env file to match your environment"
echo "=================================================="

if [ -t 0 ]; then
    cd "$HUMHUB_DIR"
    if command -v nano &>/dev/null; then
        nano .env
    elif command -v vi &>/dev/null; then
        vi .env
    else
        echo "No text editor found (nano or vi)"
    fi
else
    echo "No interactive terminal detected."
    echo "Please edit the file manually:"
    echo "  $HUMHUB_DIR/.env"
fi

# --------------------------------------------------
# Final message
# --------------------------------------------------
echo
echo "=================================================="
echo "Provisioning completed successfully"
echo
echo "Next steps:"
echo "  1. Review and adjust: $HUMHUB_DIR/.env"
echo "  2. Start the stack:"
echo "     sudo -u $HUMHUB_USER docker compose up -d"
echo
echo "Provisioning script saved as:"
echo "  $SCRIPT_PATH"
echo "=================================================="
