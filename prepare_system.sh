#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# HumHub Host Preparation Script
# Version: 1.3.0
#
# This script prepares a host to run a complete
# HumHub + OnlyOffice + Traefik Docker stack.
# It performs:
#   - Installation of required system packages
#   - Docker installation
#   - Creation of directory structure under /local/humhub/data
#   - Full .env generation with safe defaults
#   - Creation of installation_config.php
#   - Automatic ACME staging toggle in docker-compose.yml
#   - Download of installation checker script
#   - Adding the "humhub" user to the "docker" group
#   - Firewall configuration with idempotent rule checks
#
# Run this script as root.
# ==================================================

VERSION="1.3.0"

HUMHUB_USER="humhub"
HUMHUB_DIR="/local/humhub"
DATA_DIR="$HUMHUB_DIR/data"
ENV_FILE="$HUMHUB_DIR/.env"
COMPOSE_FILE="$HUMHUB_DIR/docker-compose.yml"

CONFIG_DIR="$DATA_DIR/humhub/config"
INSTALL_CFG="$CONFIG_DIR/installation_config.php"

ACME_DIR="$DATA_DIR/traefik/letsencrypt"
ACME_FILE="$ACME_DIR/acme.json"

INSTALL_CHECK_URL="https://raw.githubusercontent.com/martdj/Humhub/refs/heads/main/humhub-install-check.sh"
INSTALL_CHECK_LOCAL="$HUMHUB_DIR/humhub-install-check.sh"

COMPOSE_URL="https://raw.githubusercontent.com/martdj/Humhub/refs/heads/main/docker-compose.yml"

# --------------------------------------------------
# Colors
# --------------------------------------------------
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; DIM="\033[2m"; OFF="\033[0m"
log(){ echo -e "${GREEN}[*]${OFF} $*"; }
warn(){ echo -e "${YELLOW}[!]${OFF} $*"; }
err(){ echo -e "${RED}[x]${OFF} $*" >&2; }

timestamp(){ date +"%Y%m%d-%H%M%S"; }

# --------------------------------------------------
# Random secret generators
# --------------------------------------------------
rand_pass(){ openssl rand -base64 24 | tr -d '\n' | tr '/+=' '_-x'; }
rand_b64(){ openssl rand -base64 32 | tr -d '\n'; }

# --------------------------------------------------
# Prompts
# --------------------------------------------------
prompt(){
  local msg="$2" def="${3:-}" val=""
  if [[ -n "$def" ]]; then
    read -r -p "$msg [$def]: " val || true
    val="${val:-$def}"
  else
    read -r -p "$msg: " val || true
  fi
  printf "%s" "$val"
}

yesno(){
  local q="$1" ans=""
  read -r -p "$q [y/N]: " ans || true
  [[ "$ans" =~ ^[Yy]$ ]]
}

# --------------------------------------------------
# Parse existing .env (safe; no sourcing)
# --------------------------------------------------
load_env_defaults(){
  if [[ -f "$ENV_FILE" ]]; then
    warn "Existing .env detected; defaults will be imported."
    while IFS='=' read -r key value; do
      [[ -z "$key" || "$key" =~ ^# ]] && continue
      value="${value#\"}"; value="${value%\"}"
      export "$key"="$value"
    done < "$ENV_FILE"
  fi
}

# --------------------------------------------------
# System preparation
# --------------------------------------------------
install_base(){
  log "Installing base system packages..."
  dnf install -y curl yum-utils firewalld openssl >/dev/null
}

install_docker(){
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker CE..."
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null
    dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
    systemctl enable --now docker
  else
    log "Docker already installed."
  fi
}

selinux_tune(){
  if command -v getenforce >/dev/null && [[ "$(getenforce)" != "Disabled" ]]; then
    log "Applying SELinux adjustments for container operation..."
    setsebool -P container_manage_cgroup on || true
  fi
}

ensure_user(){
  if ! id "$HUMHUB_USER" >/dev/null 2>&1; then
    log "Creating system user: $HUMHUB_USER"
    useradd "$HUMHUB_USER"
  fi
}

ensure_user_in_docker_group(){
  log "Ensuring user '$HUMHUB_USER' is a member of 'docker' group..."
  if ! getent group docker >/dev/null; then
    groupadd docker
  fi
  if ! id -nG "$HUMHUB_USER" | grep -qw docker; then
    usermod -aG docker "$HUMHUB_USER"
    warn "User must log out/in (or reboot) for docker group membership to activate."
  fi
}

check_docker_access(){
  if sudo -u "$HUMHUB_USER" docker ps >/dev/null 2>&1; then
    log "Confirmed: '$HUMHUB_USER' can run docker commands."
  else
    warn "'$HUMHUB_USER' cannot run docker yet. This will work after re-login/reboot."
  fi
}

# --------------------------------------------------
# Directory setup
# --------------------------------------------------
ensure_dirs(){
  log "Creating required directory structure..."

  mkdir -p \
    "$DATA_DIR/db-data" \
    "$DATA_DIR/humhub/config" \
    "$DATA_DIR/humhub/uploads" \
    "$DATA_DIR/humhub/modules" \
    "$DATA_DIR/humhub/logs" \
    "$DATA_DIR/humhub/themes" \
    "$DATA_DIR/onlyoffice/data" \
    "$DATA_DIR/onlyoffice/log" \
    "$DATA_DIR/backups" \
    "$DATA_DIR/traefik/letsencrypt" \
    "$DATA_DIR/redis"

  [[ -f "$ACME_FILE" ]] || touch "$ACME_FILE"

  # Single unified chmod/chown for all data
  chown -R "$HUMHUB_USER:$HUMHUB_USER" "$DATA_DIR"
  find "$DATA_DIR" -type d -exec chmod 755 {} \;
  chmod 600 "$ACME_FILE"
}

# --------------------------------------------------
# Firewall configuration (idempotent)
# --------------------------------------------------
open_firewall(){
  log "Configuring firewall rules..."
  systemctl enable --now firewalld

  if ! firewall-cmd --list-services | grep -qw http; then
    firewall-cmd --add-service=http --permanent
  fi
  if ! firewall-cmd --list-services | grep -qw https; then
    firewall-cmd --add-service=https --permanent
  fi

  firewall-cmd --reload
}

# --------------------------------------------------
# Compose file setup
# --------------------------------------------------
fetch_compose_if_missing(){
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    log "Downloading docker-compose.yml..."
    curl -fsSL "$COMPOSE_URL" -o "$COMPOSE_FILE"
  fi
}

# --------------------------------------------------
# Interactive wizard
# --------------------------------------------------
wizard(){
  load_env_defaults
  log "Starting configuration wizard..."

  LE_EMAIL=$(prompt LE_EMAIL "Let's Encrypt email" "${LE_EMAIL:-admin@example.com}")

  TZ=$(prompt TZ "Timezone (IANA)" "${TZ:-Europe/Amsterdam}")
  HUMHUB_TIMEZONE="$TZ"

  ADMIN_USERNAME=$(prompt ADMIN_USERNAME "Admin username" "${HUMHUB_ADMIN_USERNAME:-${ADMIN_USERNAME:-admin}}")
  ADMIN_EMAIL=$(prompt ADMIN_EMAIL "Admin email" "${HUMHUB_ADMIN_EMAIL:-${ADMIN_EMAIL:-admin@example.com}}")

  if [[ -n "${HUMHUB_ADMIN_PASSWORD:-}" ]]; then
    echo -n "Admin password (leave empty to keep existing): "
    read -rs TMP; echo
    ADMIN_PASS="${TMP:-$HUMHUB_ADMIN_PASSWORD}"
  else
    read -rs -p "Admin password (blank = auto): " ADMIN_PASS; echo
    [[ -z "$ADMIN_PASS" ]] && ADMIN_PASS="$(rand_pass)"
  fi

  ADMIN_DISPLAY_NAME=$(prompt ADMIN_DISPLAY_NAME "Admin display name" "${ADMIN_DISPLAY_NAME:-Administrator}")

  HUMHUB_HOST=$(prompt HUMHUB_HOST "HumHub FQDN" "${HUMHUB_HOST:-humhub.example.com}")
  ONLYOFFICE_HOST=$(prompt ONLYOFFICE_HOST "OnlyOffice FQDN" "${ONLYOFFICE_HOST:-docs.example.com}")
  HUMHUB_BASE_URL="https://${HUMHUB_HOST}"

  HUMHUB_VERSION=$(prompt HUMHUB_VERSION "HumHub version" "${HUMHUB_VERSION:-1.16}")
  ONLYOFFICE_VERSION=$(prompt ONLYOFFICE_VERSION "OnlyOffice version" "${ONLYOFFICE_VERSION:-latest}")

  NGINX_CLIENT_MAX_BODY_SIZE=$(prompt NGINX_CLIENT_MAX_BODY_SIZE "client_max_body_size" "${NGINX_CLIENT_MAX_BODY_SIZE:-20m}")
  NGINX_KEEPALIVE_TIMEOUT=$(prompt NGINX_KEEPALIVE_TIMEOUT "keepalive_timeout" "${NGINX_KEEPALIVE_TIMEOUT:-65}")

  MARIADB_DATABASE=$(prompt MARIADB_DATABASE "MariaDB database" "${MARIADB_DATABASE:-humhub}")
  MARIADB_USER=$(prompt MARIADB_USER "MariaDB user" "${MARIADB_USER:-humhub}")

  if [[ -n "${MARIADB_PASSWORD:-}" ]]; then
    echo -n "MariaDB password (empty = keep existing): "; read -rs TMP; echo
    MARIADB_PASSWORD="${TMP:-$MARIADB_PASSWORD}"
  else
    MARIADB_PASSWORD=$(prompt MARIADB_PASSWORD "MariaDB password" "$(rand_pass)")
  fi

  if [[ -n "${MARIADB_ROOT_PASSWORD:-}" ]]; then
    echo -n "MariaDB root password (empty = keep existing): "; read -rs TMP; echo
    MARIADB_ROOT_PASSWORD="${TMP:-$MARIADB_ROOT_PASSWORD}"
  else
    MARIADB_ROOT_PASSWORD=$(prompt MARIADB_ROOT_PASSWORD "MariaDB root password" "$(rand_pass)")
  fi

  if [[ -n "${REDIS_PASSWORD:-}" ]]; then
    echo -n "Redis password (empty = keep existing): "; read -rs TMP; echo
    REDIS_PASSWORD="${TMP:-$REDIS_PASSWORD}"
  else
    REDIS_PASSWORD=$(prompt REDIS_PASSWORD "Redis password" "$(rand_pass)")
  fi

  if [[ -n "${ONLYOFFICE_JWT_SECRET:-}" ]]; then
    echo -n "OnlyOffice JWT secret (empty = keep existing): "; read -rs TMP; echo
    ONLYOFFICE_JWT_SECRET="${TMP:-$ONLYOFFICE_JWT_SECRET}"
  else
    ONLYOFFICE_JWT_SECRET=$(prompt ONLYOFFICE_JWT_SECRET "OnlyOffice JWT secret" "$(rand_b64)")
  fi

  SMTP_RELAY_HOST=$(prompt SMTP_RELAY_HOST "SMTP relay host" "${SMTP_RELAY_HOST:-smtp.eu.mailgun.org}")
  SMTP_RELAY_PORT=$(prompt SMTP_RELAY_PORT "SMTP port" "${SMTP_RELAY_PORT:-587}")
  SMTP_RELAY_USER=$(prompt SMTP_RELAY_USER "SMTP username" "${SMTP_RELAY_USER:-postmaster@example.com}")

  if [[ -n "${SMTP_RELAY_PASSWORD:-}" ]]; then
    echo -n "SMTP password (empty = keep existing): "; read -rs TMP; echo
    SMTP_RELAY_PASSWORD="${TMP:-$SMTP_RELAY_PASSWORD}"
  else
    read -rs -p "SMTP password: " SMTP_RELAY_PASSWORD; echo
  fi

  SMTP_HELO_NAME=$(prompt SMTP_HELO_NAME "SMTP HELO name" "${SMTP_HELO_NAME:-$(hostname -f)}")

  BACKUP_SCHEDULE=$(prompt BACKUP_SCHEDULE "Backup cron schedule" "${BACKUP_SCHEDULE:-0 3 * * *}")

  if yesno "Use Let's Encrypt staging?"; then
    LE_USE_STAGING="true"
    LE_CASERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
  else
    LE_USE_STAGING="false"
    LE_CASERVER=""
  fi
}

# --------------------------------------------------
# Generate .env
# --------------------------------------------------
write_env(){
  [[ -f "$ENV_FILE" ]] && cp "$ENV_FILE" "$ENV_FILE.bak.$(timestamp)"

  cat >"$ENV_FILE" <<EOF
# Generated $(date -Iseconds)
TZ=${TZ}
LE_EMAIL=${LE_EMAIL}
LE_USE_STAGING=${LE_USE_STAGING}
LE_CASERVER=${LE_CASERVER}

HUMHUB_VERSION=${HUMHUB_VERSION}
HUMHUB_HOST=${HUMHUB_HOST}
HUMHUB_BASE_URL=${HUMHUB_BASE_URL}

NGINX_CLIENT_MAX_BODY_SIZE=${NGINX_CLIENT_MAX_BODY_SIZE}
NGINX_KEEPALIVE_TIMEOUT=${NGINX_KEEPALIVE_TIMEOUT}

MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}
MARIADB_DATABASE=${MARIADB_DATABASE}
MARIADB_USER=${MARIADB_USER}
MARIADB_PASSWORD=${MARIADB_PASSWORD}

REDIS_PASSWORD=${REDIS_PASSWORD}

ONLYOFFICE_VERSION=${ONLYOFFICE_VERSION}
ONLYOFFICE_HOST=${ONLYOFFICE_HOST}
ONLYOFFICE_JWT_SECRET=${ONLYOFFICE_JWT_SECRET}

SMTP_RELAY_HOST=${SMTP_RELAY_HOST}
SMTP_RELAY_PORT=${SMTP_RELAY_PORT}
SMTP_RELAY_USER=${SMTP_RELAY_USER}
SMTP_RELAY_PASSWORD=${SMTP_RELAY_PASSWORD}
SMTP_HELO_NAME=${SMTP_HELO_NAME}

BACKUP_SCHEDULE=${BACKUP_SCHEDULE}

HUMHUB_ADMIN_USERNAME=${ADMIN_USERNAME}
HUMHUB_ADMIN_EMAIL=${ADMIN_EMAIL}
HUMHUB_ADMIN_PASSWORD=${ADMIN_PASS}
EOF

  chmod 640 "$ENV_FILE"
  chown "$HUMHUB_USER:$HUMHUB_USER" "$ENV_FILE"
  log ".env created"
}

# --------------------------------------------------
# Generate installation_config.php
# --------------------------------------------------
write_install_cfg(){
  [[ -f "$INSTALL_CFG" ]] && cp "$INSTALL_CFG" "$INSTALL_CFG.bak.$(timestamp)"
  mkdir -p "$CONFIG_DIR"

  cat >"$INSTALL_CFG" <<EOF
<?php
return [
  'database' => [
    'connection' => 'mysql',
    'hostname'   => 'mariadb',
    'port'       => '3306',
    'database'   => '${MARIADB_DATABASE}',
    'username'   => '${MARIADB_USER}',
    'password'   => '${MARIADB_PASSWORD}',
  ],
  'admin' => [
    'username'    => '${ADMIN_USERNAME}',
    'email'       => '${ADMIN_EMAIL}',
    'password'    => '${ADMIN_PASS}',
    'displayName' => '${ADMIN_DISPLAY_NAME}',
  ],
  'settings' => [
    'name'      => 'HumHub',
    'baseUrl'   => '${HUMHUB_BASE_URL}',
    'timeZone'  => '${HUMHUB_TIMEZONE}',
  ],
];
EOF

  chmod 640 "$INSTALL_CFG"
  chown "$HUMHUB_USER:$HUMHUB_USER" "$INSTALL_CFG"
  log "installation_config.php created"
}

# --------------------------------------------------
# ACME staging toggle in compose
# --------------------------------------------------
update_compose(){
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    warn "docker-compose.yml not found; ACME update skipped."
    return
  fi

  if [[ "$LE_USE_STAGING" == "true" ]]; then
    sed -i \
      's|#\s*- --certificatesresolvers\.letsencrypt\.acme\.caserver=.*$|- --certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory|' \
      "$COMPOSE_FILE"
  else
    sed -i \
      's|- --certificatesresolvers\.letsencrypt\.acme\.caserver=.*$|# - --certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory|' \
      "$COMPOSE_FILE"
  fi
}

# --------------------------------------------------
# Install checker script
# --------------------------------------------------
install_checker(){
  log "Downloading installation checker..."
  curl -fsSL "$INSTALL_CHECK_URL" -o "$INSTALL_CHECK_LOCAL"
  chmod +x "$INSTALL_CHECK_LOCAL"
  log "Checker available: $INSTALL_CHECK_LOCAL"
}

# --------------------------------------------------
# Final instructions
# --------------------------------------------------
finish_message(){
  echo
  echo "=================================================="
  echo " HumHub Preparation Complete (v$VERSION)"
  echo
  echo "Recommended next step:"
  echo "  $INSTALL_CHECK_LOCAL"
  echo
  echo "Initial installation (one-time):"
  echo "  sudo -u $HUMHUB_USER docker compose up -d traefik mariadb redis humhub"
  echo "  sudo -u $HUMHUB_USER docker compose logs -f humhub"
  echo "  Then open: https://${HUMHUB_HOST}"
  echo
  echo "After installation is confirmed and admin login works:"
  echo "  sudo -u $HUMHUB_USER docker compose up -d"
  echo
  echo "If '$HUMHUB_USER' was just added to the docker group,"
  echo "log out and back in or reboot the system."
  echo "=================================================="
}

# --------------------------------------------------
# Main
# --------------------------------------------------
main(){
  echo "=================================================="
  echo " HumHub Host Preparation Script v$VERSION"
  echo "=================================================="

  install_base
  install_docker
  selinux_tune
  ensure_user
  ensure_user_in_docker_group
  ensure_dirs
  open_firewall
  fetch_compose_if_missing
  check_docker_access

  wizard
  write_env
  write_install_cfg
  update_compose
  install_checker

  finish_message
}

main "$@"
