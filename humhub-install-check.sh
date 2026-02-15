#!/usr/bin/env bash
set -euo pipefail

HUMHUB_DIR="/local/humhub"
DATA_DIR="$HUMHUB_DIR/data"
CONFIG_DIR="$DATA_DIR/humhub/config"
DB_DIR="$DATA_DIR/db-data"
INSTALL_CFG="$CONFIG_DIR/installation_config.php"

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; OFF="\033[0m"

ok(){    echo -e "${GREEN}[OK]${OFF} $*"; }
warn(){  echo -e "${YELLOW}[WARN]${OFF} $*"; }
fail(){  echo -e "${RED}[FAIL]${OFF} $*"; exit 1; }

echo "=============================================================="
echo " HumHub Installation Checker"
echo "=============================================================="
echo

# ---------------------------------------------------------------
# 1) Check installation_config.php
# ---------------------------------------------------------------
echo "▶ Checking: installation_config.php exists..."

if [[ ! -f "$INSTALL_CFG" ]]; then
  fail "installation_config.php is missing! Run prepare_system.sh first."
else
  ok "Found: $INSTALL_CFG"
fi

if [[ "$(stat -c %a "$INSTALL_CFG")" != "640" && "$(stat -c %a "$INSTALL_CFG")" != "644" ]]; then
  warn "Permissions of installation_config.php should be 640 or 644."
else
  ok "Permissions look good."
fi

# ---------------------------------------------------------------
# 2) Check DB directory is empty
# ---------------------------------------------------------------
echo
echo "▶ Checking: Database directory is empty..."

if [[ ! -d "$DB_DIR" ]]; then
  fail "$DB_DIR does not exist! prepare_system.sh did not create it."
fi

if [[ -n "$(ls -A "$DB_DIR")" ]]; then
  fail "Database directory is NOT empty. Installation will fail or create admin with wrong values."
else
  ok "Database directory is empty — good."
fi

# ---------------------------------------------------------------
# 3) Check config directory is OK
# ---------------------------------------------------------------
echo
echo "▶ Checking: HumHub config directory..."

if [[ ! -d "$CONFIG_DIR" ]]; then
  fail "Config directory $CONFIG_DIR does not exist."
fi

# Should ONLY contain installation_config.php on a fresh install
EXTRA_FILES=$(ls "$CONFIG_DIR" | grep -v installation_config.php || true)

if [[ -n "$EXTRA_FILES" ]]; then
  warn "Config directory contains extra files:"
  echo "$EXTRA_FILES"
  fail "This indicates a previous or partial installation. Clean before retrying."
else
  ok "Config directory is clean."
fi

# ---------------------------------------------------------------
# 4) Check humhub-cron is NOT running
# ---------------------------------------------------------------
echo
echo "▶ Checking: humhub-cron is NOT running..."

if docker ps --format '{{.Names}}' | grep -q humhub-cron; then
  fail "humhub-cron is running — stop it before installation."
else
  ok "humhub-cron is not running — good."
fi

# ---------------------------------------------------------------
# 5) Check searchdb is NOT host-mounted
# ---------------------------------------------------------------
echo
echo "▶ Checking: searchdb MUST NOT be persistent..."

if grep -q "searchdb" "$HUMHUB_DIR/docker-compose.yml"; then
  if grep -q "/protected/runtime/searchdb" "$HUMHUB_DIR/docker-compose.yml"; then
    fail "searchdb is host-mounted! Remove searchdb volume mapping to avoid installation failure."
  fi
fi

ok "searchdb is not persistent — correct."

# ---------------------------------------------------------------
# 6) Check that humhub user can run docker
# ---------------------------------------------------------------
echo
echo "▶ Checking: humhub user docker access..."

if sudo -u humhub docker ps >/dev/null 2>&1; then
  ok "humhub user can run docker commands."
else
  warn "humhub user CANNOT run docker yet."
  warn "→ This is normal right after prepare_system.sh."
  warn "→ Fix: log out and back in, or reboot."
fi

# ---------------------------------------------------------------
# 7) Check that installer is likely to work
# ---------------------------------------------------------------
echo
echo "▶ Final confirmation"

ok "All conditions for a clean HumHub installation look good."

echo
echo "=============================================================="
echo "READY TO INSTALL"
echo "Run the following to start installation:"
echo
echo "  sudo -u humhub docker compose up -d mariadb redis humhub"
echo
echo "After installation and first admin login:"
echo
echo "  sudo -u humhub docker compose up -d"
echo "=============================================================="
