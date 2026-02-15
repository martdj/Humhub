#!/bin/bash

# Target directory for the volume-mounted HumHub config folder
TARGET_DIR="/local/humhub/data/humhub/config"
TARGET_FILE="$TARGET_DIR/installation_config.php"

echo "------------------------------------------------------"
echo " HumHub Installation Configuration Generator (Host)"
echo "------------------------------------------------------"
echo ""
echo "This script will generate:"
echo "  $TARGET_FILE"
echo ""
echo "Press ENTER to accept defaults shown in [brackets]."
echo ""

# Ensure target directory exists
mkdir -p "$TARGET_DIR"

# --- Ask questions ---------------------------------------------------------

read -p "Admin email [admin@example.com]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.com}

read -p "Admin password (min 8 chars) [Admin123!]: " ADMIN_PASSWORD
ADMIN_PASSWORD=${ADMIN_PASSWORD:-Admin123!}

read -p "Site name [HumHub Community]: " SITE_NAME
SITE_NAME=${SITE_NAME:-HumHub Community}

read -p "Base URL (incl. https://) [https://example.com]: " BASE_URL
BASE_URL=${BASE_URL:-https://example.com}

read -p "Timezone [Europe/Amsterdam]: " TIMEZONE
TIMEZONE=${TIMEZONE:-Europe/Amsterdam}

# Database host/user/pass will typically match your Docker compose
echo ""
echo "Database settings (from Docker environment):"
read -p "Database host [mariadb]: " DB_HOST
DB_HOST=${DB_HOST:-mariadb}

read -p "Database port [3306]: " DB_PORT
DB_PORT=${DB_PORT:-3306}

read -p "Database name [humhub]: " DB_NAME
DB_NAME=${DB_NAME:-humhub}

read -p "Database username [humhub]: " DB_USER
DB_USER=${DB_USER:-humhub}

read -p "Database password [ChangeMeDB!]: " DB_PASSWORD
DB_PASSWORD=${DB_PASSWORD:-ChangeMeDB!}

echo ""
echo "------------------------------------------------------"
echo " Writing installation configuration..."
echo "------------------------------------------------------"
echo ""

# --- Generate PHP installation config --------------------------------------

cat > "$TARGET_FILE" <<EOF
<?php
return [
    'database' => [
        'connection' => 'mysql',
        'hostname'   => '$DB_HOST',
        'port'       => '$DB_PORT',
        'database'   => '$DB_NAME',
        'username'   => '$DB_USER',
        'password'   => '$DB_PASSWORD',
    ],
    'admin' => [
        'email'    => '$ADMIN_EMAIL',
        'password' => '$ADMIN_PASSWORD',
    ],
    'settings' => [
        'name'     => '$SITE_NAME',
        'baseUrl'  => '$BASE_URL',
        'timeZone' => '$TIMEZONE',
    ],
];
EOF

echo "Installation config created successfully at:"
echo "  $TARGET_FILE"
echo ""
echo "Now start HumHub to auto-install using this config:"
echo "  docker compose up -d humhub"
echo ""
echo "------------------------------------------------------"
echo " Done!"
echo "------------------------------------------------------"
