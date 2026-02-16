# HumHub Docker Deployment

A production‑ready Docker environment for running **HumHub** with:

- Traefik 3 reverse proxy + automatic HTTPS  
- MariaDB & Redis  
- OnlyOffice DocumentServer  
- SMTP relay  
- Automated backups  
- Dedicated Cron/Queue container  
- IPv6 support  

Includes a **fully automated host preparation script**, installation checker, and a clean installation workflow designed for stability and repeatability.

### Features
- One‑command host setup (`prepare_system.sh`)
- Safe `.env` generation with strong defaults
- Automatic creation of `installation_config.php`
- Traefik HTTPS with staging/production switching
- Minimal‑stack installation → full‑stack deployment
- Clear directory structure under `/local/humhub/data`
- OnlyOffice JWT integration

### Installation
1. Run the preparation script as root  
2. Run the installation‑checker  
3. Start the minimal services  
4. Log in as admin  
5. Start the full stack  

See the full documentation in **README.md**.
