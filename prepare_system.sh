#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# HumHub Host Preparation Script
# Version: 1.3.1
#
# This script prepares a host to run a complete
# HumHub + OnlyOffice + Traefik Docker stack.
# It performs:
#   - OS detection (RHEL-like vs Debian-like)
#   - Installation of system packages & Docker
#   - Firewall configuration (firewalld or ufw when applicable)
#   - Creation of directory structure under /local/humhub/data
#   - Generation of .env and installation_config.php
#   - Automatic ACME staging toggle in docker-compose.yml
#   - Download of installation checker script
#   - Adding the "humhub" user to the "docker" group
#
# Run this script as root.
# ==================================================

VERSION="1.3.1"

# Paths & files
HUMHUB_USER="humhub"
HUMHUB_DIR="/local/humhub"
DATA_DIR="$HUMHUB_DIR/data"
ENV_FILE="$HUMHUB_DIR/.env"
COMPOSE_FILE="$HUMHUB_DIR/docker-compose.yml"
CONFIG_DIR="$DATA_DIR/humhub/config"
INSTALL_CFG="$CONFIG_DIR/installation_config.php"
ACME_DIR="$DATA_DIR/traefik/letsencrypt"
ACME_FILE="$ACME_DIR/acme.json"

# Remote resources (raw URLs without refs/heads)
REPO_BASE="https://raw.githubusercontent.com/martdj/Humhub/main"
INSTALL_CHECK_URL="$REPO_BASE/humhub-install-check.sh"
INSTALL_CHECK_LOCAL="$HUMHUB_DIR/humhub-install-check.sh"
COMPOSE_URL="$REPO_BASE/docker-compose.yml"

# Colors
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; OFF="\033[0m"
log(){ echo -e "${GREEN}[*]${OFF} $*"; }
warn(){ echo -e "${YELLOW}[!]${OFF} $*"; }
err(){ echo -e "${RED}[x]${OFF} $*" >&2; }

timestamp(){ date +"%Y%m%d-%H%M%S"; }

# --------------------------------------------------
# Secret generators
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
# Safe .env parser (no sourcing)
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
# OS detection
# --------------------------------------------------
OS_FAMILY=""   # "rhel" or "debian"
OS_ID=""       # e.g., "rhel", "centos", "rocky", "almalinux", "debian", "ubuntu"
detect_os(){
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    local like="${ID_LIKE:-}"
    if [[ "$OS_ID" =~ (rhel|centos|rocky|almalinux|fedora) ]] || [[ "$like" =~ (rhel|fedora) ]]; then
      OS_FAMILY="rhel"
    elif [[ "$OS_ID" =~ (debian|ubuntu|raspbian) ]] || [[ "$like" =~ (debian|ubuntu) ]]; then
      OS_FAMILY="debian"
    fi
  fi
  if [[ -z "$OS_FAMILY" ]]; then
    err "Unsupported or undetected Linux distribution. /etc/os-release not recognized."
    exit 1
  fi
  log "Detected OS family: $OS_FAMILY (id: ${OS_ID:-unknown})"
}

# --------------------------------------------------
# Package installation (base dependencies)
# --------------------------------------------------
install_base_rhel(){
  log "Installing base packages via dnf..."
  dnf -y install curl yum-utils firewalld openssl >/dev/null
}

install_base_debian(){
  log "Installing base packages via apt-get..."
  apt-get update -y >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl gnupg lsb-release openssl >/dev/null
  # ufw is optional; install if present or desired later
  if ! command -v ufw >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y ufw >/dev/null || true
  fi
}

# --------------------------------------------------
# Docker installation
# --------------------------------------------------
install_docker_rhel(){
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker CE on RHEL-like..."
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null
    dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
    systemctl enable --now docker
  else
    log "Docker already installed."
  fi
}

install_docker_debian(){
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker CE on Debian-like..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    local codename=""
    if [[ -r /etc/os-release ]]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      codename="${VERSION_CODENAME:-}"
    fi
    if [[ -z "$codename" ]] && command -v lsb_release >/dev/null 2>&1; then
      codename="$(lsb_release -cs)"
    fi
    if [[ -z "$codename" ]]; then
      err "Could not determine Debian/Ubuntu codename."
      exit 1
    fi

    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} ${codename} stable" \
      | tee /etc/apt/sources.list.d/docker.list >/dev/null

    apt-get update -y >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
    systemctl enable --now docker
  else
    log "Docker already installed."
  fi
}

# --------------------------------------------------
# SELinux tuning (RHEL-like only)
# --------------------------------------------------
selinux_tune_rhel(){
  if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != "Disabled" ]]; then
    log "Applying SELinux adjustments for container operation..."
    setsebool -P container_manage_cgroup on || true
  fi
}

# --------------------------------------------------
# User and docker group
# --------------------------------------------------
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

  chown -R "$HUMHUB_USER:$HUMHUB_USER" "$DATA_DIR"
  find "$DATA_DIR" -type d -exec chmod 755 {} \;
  chmod 600 "$ACME_FILE"
}

# --------------------------------------------------
# Firewall configuration (firewalld for RHEL-like, ufw for Debian-like)
# --------------------------------------------------
open_firewall_rhel(){
  log "Configuring firewalld (HTTP/HTTPS)..."
  systemctl enable --now firewalld
  if ! firewall-cmd --list-services | grep -qw http; then
    firewall-cmd --add-service=http --permanent
  fi
  if ! firewall-cmd --list-services | grep -qw https; then
    firewall-cmd --add-service=https --permanent
  fi
  firewall-cmd --reload
}

open_firewall_debian(){
  if command -v ufw >/dev/null 2>&1; then
    # Only set rules if ufw is available; do not auto-enable to avoid surprises
    log "Configuring ufw rules (HTTP/HTTPS) if ufw is active..."
    local active="inactive"
    active="$(ufw status | awk 'NR==1{print $2}')" || true
    if [[ "$active" == "active" ]]; then
      # Add rules idempotently
      ufw status | grep -qw "80/tcp" || ufw allow 80/tcp >/dev/null
      ufw status | grep -qw "443/tcp" || ufw allow 443/tcp >/dev/null
      log "ufw rules for 80/tcp and 443/tcp verified."
    else
      warn "ufw is installed but not active. Skipping ufw rule changes."
    fi
  else
    warn "ufw is not installed; skipping firewall configuration on Debian-like system."
  fi
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
      "$COMPOSE_FILE" || true
  else
    sed -i \
      's|- --certificatesresolvers\.letsencrypt\.acme\.caserver=.*$|# - --certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory|' \
      "$COMPOSE_FILE" || true
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
  echo " HumHub Host Preparation Script"
  echo " Version: $VERSION"
  echo "=================================================="

  detect_os

  if [[ "$OS_FAMILY" == "rhel" ]]; then
    install_base_rhel
    install_docker_rhel
    selinux_tune_rhel
  elif [[ "$OS_FAMILY" == "debian" ]]; then
    install_base_debian
    install_docker_debian
  fi

  ensure_user
  ensure_user_in_docker_group
  ensure_dirs

  if [[ "$OS_FAMILY" == "rhel" ]]; then
    open_firewall_rhel
  else
    open_firewall_debian
  fi

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
