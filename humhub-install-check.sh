#!/usr/bin/env bash
set -euo pipefail

HUMHUB_DIR="/local/humhub"
DATA_DIR="$HUMHUB_DIR/data"
CONFIG_DIR="$DATA_DIR/humhub/config"
DB_DIR="$DATA_DIR/db-data"
INSTALL_CFG="$CONFIG_DIR/installation_config.php"

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; OFF="\033[0m"

ok(){ echo -e "${GREEN}[OK]${OFF} $*"; }
fail(){ echo -e "${RED}[FAIL]${OFF} $*"; exit 1; }

echo "=============================================================="
echo " HumHub Installation Checker"
echo "=============================================================="
echo

# ---------------------------------------------------------------
# 1) installation_config.php must exist and have correct mode
# ---------------------------------------------------------------
echo "▶ Checking installation_config.php..."

if [[ ! -f "$INSTALL_CFG" ]]; then
  fail "installation_config.php is missing. Run prepare_system.sh first."
fi
ok "Found: $INSTALL_CFG"

perm=$(stat -c %a "$INSTALL_CFG")
if [[ "$perm" != "640" && "$perm" != "644" ]]; then
  fail "installation_config.php must be mode 640 or 644 (current: $perm)."
fi
ok "Permissions are correct."

# ---------------------------------------------------------------
# 2) DB directory must exist and be empty
# ---------------------------------------------------------------
echo
echo "▶ Checking database directory..."

if [[ ! -d "$DB_DIR" ]]; then
  fail "$DB_DIR does not exist. prepare_system.sh did not complete successfully."
fi

if [[ -n "$(ls -A "$DB_DIR")" ]]; then
  fail "Database directory is NOT empty. A clean installation is not possible."
fi
ok "Database directory is empty."

# ---------------------------------------------------------------
# 3) Config directory must contain ONLY installation_config.php
# ---------------------------------------------------------------
echo
echo "▶ Checking HumHub config directory..."

if [[ ! -d "$CONFIG_DIR" ]]; then
  fail "Config directory $CONFIG_DIR does not exist."
fi

extra=$(ls "$CONFIG_DIR" | grep -v installation_config.php || true)
if [[ -n "$extra" ]]; then
  fail "Config directory contains extra files. Remove them before installation."
fi
ok "Config directory is clean."

# ---------------------------------------------------------------
# 4) humhub user must be able to run docker
# ---------------------------------------------------------------
echo
echo "▶ Checking docker permissions for humhub user..."

if sudo -u humhub docker ps >/dev/null 2>&1; then
  ok "humhub user can run docker."
else
  fail "humhub user cannot run docker. Log out/in or reboot after prepare_system.sh."
fi

# ---------------------------------------------------------------
# 5) Everything ready
# ---------------------------------------------------------------
echo
echo "=============================================================="
echo " All checks passed. HumHub is ready for installation."
echo
echo "Start the minimal installation stack:"
echo "  sudo -u humhub docker compose up -d traefik mariadb redis humhub"
echo
echo "Watch logs:"
echo "  sudo -u humhub docker compose logs -f humhub"
echo
echo "Then open HumHub in your browser:"
echo "  https://<your-humhub-host>"
echo "=============================================================="
