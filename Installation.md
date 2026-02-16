# HumHub Docker Deployment (with OnlyOffice & Traefik 3)

This repository provides a complete production‑ready Docker setup for running **HumHub**, including:

- Traefik 3 reverse proxy with automatic HTTPS (Let's Encrypt)
- MariaDB
- Redis for cache and queue processing
- OnlyOffice DocumentServer
- SMTP relay support
- Automated MySQL backups
- A dedicated cron/queue runner container
- Automated host preparation script
- Installation checker for guaranteed clean deployments

Everything is designed for stability, reproducibility, IPv6 support, and a predictable installation workflow.

---

## Features

### ✓ Automated host preparation
`prepare_system.sh` configures the entire host:

- Installs Docker CE + compose
- Configures firewalld (idempotent)
- Applies SELinux adjustments
- Creates full directory structure under `/local/humhub/data`
- Adds the `humhub` user to the `docker` group
- Generates a secure `.env` file
- Creates `installation_config.php`
- Adjusts ACME staging in docker‑compose.yml
- Downloads an installation‑checker script

### ✓ Clean installation workflow
To avoid race conditions and ensure a stable HumHub installation, the workflow separates installation from normal operation:

1. Start minimal set of containers  
2. Wait for database migrations  
3. Log in as admin  
4. Start full stack  

### ✓ Traefik 3 reverse proxy
Fully IPv6‑ready and supports:

- Automatic HTTPS via Let's Encrypt
- Secure headers
- Compression middleware
- HTTP→HTTPS redirect middleware
- Staging/production ACME toggle

### ✓ OnlyOffice integration
Fully configured OnlyOffice DocumentServer with:

- JWT authentication
- Separate persistent storage
- Traefik routing for HTTP‑01 challenges and HTTPS access

### ✓ Persistent storage layout
All volumes live under `/local/humhub/data`:
db-data/              # MariaDB
humhub/config/        # config files including installation_config.php
humhub/uploads/       # user uploaded files
humhub/modules/       # installed modules
humhub/logs/          # application logs
humhub/themes/        # custom themes
onlyoffice/data/      # OnlyOffice persistent data
onlyoffice/log/       # logs for OnlyOffice
redis/                # Redis AOF persistence
traefik/letsencrypt/  # SSL certificate storage
backups/              # automatic database backups
---

## Requirements

- Clean Linux host with root access  
- Port 80 and 443 accessible from the internet  
- Correct DNS records for:
  - `HUMHUB_HOST`
  - `ONLYOFFICE_HOST`  
- Recommended: 2+ CPU cores, 4GB+ RAM

---

# Installation Guide

## 1. Prepare the host

Run as **root**:

```bash
chmod +x prepare_system.sh
./prepare_system.sh
This script will:

Ask configuration questions (admin account, SMTP, hostnames, etc.)
Generate .env
Generate installation_config.php
Configure Docker, firewall, directory structure, and permissions
Download humhub-install-check.sh

2. Verify the installation environment
./humhub-install-check.sh

This confirms:

Database directory is empty
Config directory contains only installation_config.php
No partial installation is present
The humhub user can run docker commands
3. Start the minimal installation stack
This avoids interference during HumHub’s migration and initialization:
sudo -u humhub docker compose up -d traefik mariadb redis humhub
``
Follow logs:
sudo -u humhub docker compose logs -f humhub
Proceed once you see:
Migrated up successfully.
Installation complete.


4. Log into HumHub
Open:
https://<your-humhub-host>/

Log in with the admin credentials chosen during the preparation script.

5. Start the full production stack
Once HumHub loads correctly and admin login works:
sudo -u humhub docker compose up -d
``
This starts:

OnlyOffice
Cron runner
SMTP relay
Backups
Static Traefik middlewares

Your deployment is now fully operational.
Updating the System
To update containers:
sudo -u humhub docker compose pull
sudo -u humhub docker compose up -d
To update configuration, rerun:
./prepare_system.sh
and review the generated .env and installation_config.php.

Directory Structure
/local/humhub
  ├── prepare_system.sh
  ├── humhub-install-check.sh
  ├── docker-compose.yml
  ├── .env
  ├── data/
      ├── db-data/
      ├── humhub/
      │   ├── config/
      │   ├── uploads/
      │   ├── modules/
      │   ├── logs/
      │   ├── themes/
      ├── onlyoffice/
      ├── traefik/
      ├── backups/
      ├── redis/


Best Practices

Always run docker compose commands as the humhub user
Keep acme.json set to mode 600
Never persist HumHub’s search index
Ensure DNS records exist before running Traefik
Prefer pinned Traefik version (traefik:v3.6) for stability


License
This repository uses the license provided in the root directory.
HumHub, OnlyOffice, Traefik, Redis, and MariaDB retain their own licenses.
