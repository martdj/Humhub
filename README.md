# Humhub
Scripts and docker compose files for installing Humhub

# HumHub Host Preparation Script

This repository provides a system preparation script for running **HumHub with Docker Compose** on a RHEL-based system (CentOS / Rocky / Alma).

The script installs Docker, prepares the required directory structure, configures the firewall and SELinux, and downloads the required configuration files.

---

## Quick start

Run the following command on a fresh system:

```bash
curl -fsSL https://raw.githubusercontent.com/martdj/Humhub/refs/heads/main/prepare_system.env | sudo bash
```
Or using wget:
```bash
wget -qO- https://raw.githubusercontent.com/martdj/Humhub/refs/heads/main/prepare_system.env | sudo bash
```
What the script does

Installs Docker and Docker Compose (if not already installed)

Enables and starts the Docker service

Configures SELinux for container usage (if enabled)

Creates a dedicated humhub system user

Creates all required data directories under /local/humhub

Downloads:
- .env
- docker-compose.yml
- Sets correct ownership and permissions
- Opens HTTP and HTTPS in the firewall
- Pulls all Docker images (does not start the stack)
- Warns if existing database data is detected

After running the script
1. Edit the .env file

Adjust the environment configuration to your needs (domains, passwords, mail settings, etc.):
```bash
cd /local/humhub
nano .env
```
Use any text editor you prefer (nano, vi, vim, micro, etc.).

2. Start the stack

Once the .env file is configured, start the HumHub stack:
```bash
sudo -u humhub docker compose up -d
```
Notes

The script is idempotent and can safely be run multiple times.
Existing data is never overwritten automatically.
Docker images are pulled in advance to speed up deployment.
SELinux and firewalld are supported out of the box.

Requirements
- RHEL-based Linux distribution (CentOS, Rocky Linux, AlmaLinux)
- Internet access
- Root or sudo privileges
