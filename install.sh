#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/local/humhub"
REPO_BASE="https://raw.githubusercontent.com/martdj/Humhub/main"

FILES=(
  "prepare_system.sh"
  "docker-compose.yml"
  "humhub-install-check.sh"
)

echo "========================================================="
echo " HumHub Bootstrap Installer"
echo "========================================================="
echo

echo "[*] Creating base directory at: $BASE_DIR"
mkdir -p "$BASE_DIR"

echo "[*] Downloading required files..."
for f in "${FILES[@]}"; do
  echo "    - $f"
  curl -fsSL "$REPO_BASE/$f" -o "$BASE_DIR/$f"
done

echo "[*] Setting executable permissions..."
chmod +x "$BASE_DIR/prepare_system.sh"
chmod +x "$BASE_DIR/humhub-install-check.sh"

echo
echo "========================================================="
echo " Bootstrap complete!"
echo
echo "Next steps:"
echo "  1. Run the preparation script (interactive):"
echo "       sudo $BASE_DIR/prepare_system.sh"
echo
echo "  2. After preparation completes, verify installation readiness:"
echo "       $BASE_DIR/humhub-install-check.sh"
echo
echo "  3. Proceed with minimal installation:"
echo "       sudo -u humhub docker compose up -d traefik mariadb redis humhub"
echo
echo "Files installed:"
printf "  - %s\n" "${FILES[@]}"
echo
echo "========================================================="
