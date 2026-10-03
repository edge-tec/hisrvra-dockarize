# Hostvra — Docker Deployment

> **Dockerized production deployment for [Hostvra](https://github.com/edge-tec/Hostvra) server management platform.**

This repository contains all Docker configuration files needed to deploy Hostvra on Ubuntu using Docker containers.

---

## 🚀 One-Command Install (Ubuntu)

SSH into your Ubuntu server (22.04 / 24.04 / 26.04) and run:

```bash
curl -fsSL https://raw.githubusercontent.com/edge-tec/hisrvra-dockarize/main/docker-install.sh | sudo bash
```

Or manually:

```bash
git clone https://github.com/edge-tec/hisrvra-dockarize.git /opt/hostvra
cd /opt/hostvra
sudo bash docker-install.sh
```

> The installer **automatically** handles: Docker installation, secure `.env` generation, image building, service startup, firewall configuration, and systemd auto-start.

---

## Architecture

```
Internet → Nginx (:80/:443)
             ├── /api/*  → Go API (:8080)
             │               ├── PostgreSQL (:5432)
             │               └── Redis (:6379)
             └── /*      → Next.js Web (:3000)
```

| Service | Container | Port | Image |
|---------|-----------|------|-------|
| **Go API** | `hostvra-api` | 8080 (internal) | Multi-stage Alpine (~20MB) |
| **Next.js Web** | `hostvra-web` | 3000 (internal) | Standalone Node.js (~80MB) |
| **PostgreSQL 16** | `hostvra-postgres` | 5432 (internal) | `postgres:16-alpine` |
| **Redis 7** | `hostvra-redis` | 6379 (internal) | `redis:7-alpine` |
| **Nginx** | `hostvra-nginx` | **80, 443** (public) | `nginx:1.27-alpine` |

---

## Files

| File | Purpose |
|------|---------|
| `apps/api/Dockerfile` | Multi-stage Go API build |
| `apps/web/Dockerfile` | Multi-stage Next.js standalone build |
| `docker-compose.prod.yml` | Full production stack (5 services) |
| `deployment/docker/nginx.conf` | Nginx reverse proxy (WebSocket support) |
| `docker-install.sh` | One-command Ubuntu installer |
| `.dockerignore` | Optimized build context |
| `.env.example` | Environment variable template |

---

## Commands

```bash
# Status
cd /opt/hostvra && docker compose -f docker-compose.prod.yml ps

# Logs
cd /opt/hostvra && docker compose -f docker-compose.prod.yml logs -f

# Restart
cd /opt/hostvra && docker compose -f docker-compose.prod.yml restart

# Stop
cd /opt/hostvra && docker compose -f docker-compose.prod.yml down

# Start
cd /opt/hostvra && docker compose -f docker-compose.prod.yml up -d
```

---

## Update

```bash
sudo hostvra-update
```

---

## Environment Configuration

```bash
sudo nano /opt/hostvra/.env
```

| Variable | Description |
|----------|-------------|
| `APP_URL` | Panel URL (e.g., `https://panel.yourdomain.com`) |
| `API_URL` | API URL (e.g., `https://panel.yourdomain.com/api`) |
| `ADMIN_EMAIL` | Admin login email |
| `ADMIN_PASSWORD` | Admin login password |
| `SMTP_HOST` | SMTP server for emails |
| `JWT_SECRET` | Auto-generated; **do not change** |
| `POSTGRES_PASSWORD` | Auto-generated; **do not change** |

---

## SSL Setup (Let's Encrypt)

```bash
sudo apt install certbot
sudo certbot certonly --standalone -d panel.yourdomain.com
sudo mkdir -p /opt/hostvra/certs
sudo cp /etc/letsencrypt/live/panel.yourdomain.com/fullchain.pem /opt/hostvra/certs/
sudo cp /etc/letsencrypt/live/panel.yourdomain.com/privkey.pem /opt/hostvra/certs/
```

Then uncomment the SSL volume mount in `docker-compose.prod.yml`.

---

## Requirements

| Item | Minimum | Recommended |
|------|---------|-------------|
| **RAM** | 1 GB | 2 GB+ |
| **CPU** | 1 vCPU | 2 vCPU+ |
| **Disk** | 10 GB | 20 GB+ |
| **OS** | Ubuntu 22.04+ | Ubuntu 24.04 LTS |
| **Arch** | x86_64 / arm64 | x86_64 |

---

## License

See [Hostvra License](https://github.com/edge-tec/Hostvra/blob/main/LICENSE).
