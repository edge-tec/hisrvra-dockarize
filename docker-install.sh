#!/usr/bin/env bash
# ==============================================================================
# Hostvra Platform — Dockerized Installer for Ubuntu
#
# Tested on: Ubuntu 22.04, 24.04, 26.04
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/edge-tec/Hostvra/main/docker-install.sh | sudo bash
#   or: sudo bash docker-install.sh
# ==============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/hostvra"
REPO_URL="https://github.com/edge-tec/Hostvra.git"

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $1"; }
error()   { echo -e "${RED}[ERROR]${NC}   $1" >&2; }

print_banner() {
    clear
    echo -e "${PURPLE}${BOLD}"
    cat << 'EOF'
   _    _           _                    
  | |  | |         | |                   
  | |__| | ___  ___| |_ __   ___ __ __ _ 
  |  __  |/ _ \/ __| __\ \ / / '__/ _` |
  | |  | | (_) \__ \ |_ \ V /| | | (_| |
  |_|  |_|\___/|___/\__| \_/ |_|  \__,_|
EOF
    echo -e "${NC}"
    echo -e "  ${BOLD}Dockerized Production Installer${NC}"
    echo -e "  ${CYAN}https://github.com/edge-tec/Hostvra${NC}"
    echo -e "  ══════════════════════════════════════════════\n"
}

# ── Pre-flight ────────────────────────────────────────────────────────────────
preflight() {
    info "Running pre-flight checks..."

    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Use: sudo bash docker-install.sh"
        exit 1
    fi

    # OS check
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        info "Detected OS: ${PRETTY_NAME:-$ID $VERSION_ID}"
    else
        warn "Cannot detect OS. Proceeding anyway..."
    fi

    # Architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
        error "Unsupported architecture: $ARCH. Only x86_64 and aarch64 are supported."
        exit 1
    fi
    success "Architecture: $ARCH"

    # RAM check
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ $TOTAL_RAM_MB -lt 900 ]]; then
        warn "System has ${TOTAL_RAM_MB}MB RAM. Recommended minimum is 1024MB."
    else
        success "Memory: ${TOTAL_RAM_MB}MB available"
    fi

    # Disk check (need at least 2GB for Docker images)
    FREE_GB=$(df -BG /opt 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
    if [[ -n "$FREE_GB" && "$FREE_GB" -lt 2 ]]; then
        error "Insufficient disk space: ${FREE_GB}GB free. Need at least 2GB."
        exit 1
    fi
    success "Disk space: ${FREE_GB}GB free"
}


# ── Sync System Clock ─────────────────────────────────────────────────────────
sync_clock() {
    info "Synchronizing system clock (fixes apt release file errors)..."

    # Temporarily disable pipefail and errexit so time sync failures never abort the installer
    set +eo pipefail

    # Method 1: systemd-timesyncd (preferred)
    if command -v timedatectl &>/dev/null; then
        timedatectl set-ntp true 2>/dev/null
        systemctl restart systemd-timesyncd 2>/dev/null
        sleep 1
    fi

    # Method 2: ntpdate fallback
    if command -v ntpdate &>/dev/null; then
        ntpdate -u pool.ntp.org 2>/dev/null || ntpdate -u time.google.com 2>/dev/null
    fi

    # Method 3: HTTP date header sync as fallback
    REMOTE_DATE=$(curl -sI --max-time 5 https://google.com 2>/dev/null | grep -i "^date:" | sed -e 's/^[dD]ate: //' -e 's/\r//')
    if [[ -n "${REMOTE_DATE:-}" ]]; then
        date -s "$REMOTE_DATE" 2>/dev/null
    fi

    # Re-enable pipefail and errexit
    set -eo pipefail

    success "System clock synced: $(date)"
}

# ── Install Docker ────────────────────────────────────────────────────────────
install_docker() {
    if command -v docker &>/dev/null; then
        DOCKER_VERSION=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        success "Docker already installed: v${DOCKER_VERSION}"
    else
        info "Installing Docker Engine..."
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null

        # Docker official GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        # Docker repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null

        # Start and enable Docker
        systemctl enable docker --now

        success "Docker installed and started"
    fi

    # Verify docker compose plugin
    if ! docker compose version &>/dev/null; then
        error "Docker Compose plugin not found. Install it with: apt-get install docker-compose-plugin"
        exit 1
    fi
    success "Docker Compose: $(docker compose version --short)"
}

# ── Install Git ───────────────────────────────────────────────────────────────
install_git() {
    if ! command -v git &>/dev/null; then
        info "Installing Git..."
        apt-get install -y -qq git >/dev/null
    fi
    success "Git: $(git --version | awk '{print $3}')"
}

# ── Clone / Update Repository ────────────────────────────────────────────────
setup_repository() {
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        info "Existing installation found. Ensuring repository origin and pulling latest code..."
        cd "$INSTALL_DIR"

        # Backup existing .env to preserve generated secrets and admin credentials
        if [[ -f .env ]]; then
            cp .env /tmp/hostvra.env.bak 2>/dev/null || true
        fi

        # Ensure remote origin points to the full Hostvra repository
        git remote set-url origin "$REPO_URL" 2>/dev/null || git remote add origin "$REPO_URL"
        git fetch origin main
        git checkout -B main origin/main
        git reset --hard origin/main

        # Restore .env if it was removed
        if [[ -f /tmp/hostvra.env.bak && ! -f .env ]]; then
            cp /tmp/hostvra.env.bak .env
        fi

        success "Repository updated to latest commit from $REPO_URL"
    else
        info "Cloning Hostvra repository..."
        git clone "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        success "Repository cloned to $INSTALL_DIR"
    fi
}

# ── Configure Environment ────────────────────────────────────────────────────
configure_env() {
    cd "$INSTALL_DIR"

    if [[ -f .env ]]; then
        warn ".env already exists — preserving existing configuration"
        return
    fi

    info "Generating production .env file..."
    cp .env.example .env

    # Generate secure random values
    JWT_SECRET=$(openssl rand -hex 64)
    POSTGRES_PASSWORD=$(openssl rand -hex 24)
    DOMAIN_ENCRYPTION_SECRET=$(openssl rand -hex 16)
    ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d '=+/')

    # Detect local and public IP
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    PUBLIC_IP=$(curl -sf -m 2 https://api.ipify.org 2>/dev/null || echo "$LOCAL_IP")

    if [[ "$LOCAL_IP" =~ ^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]]; then
        SERVER_IP="$LOCAL_IP"
    else
        SERVER_IP="$PUBLIC_IP"
    fi

    # Apply generated values
    sed -i "s|JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" .env
    sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|" .env
    sed -i "s|DOMAIN_ENCRYPTION_SECRET=.*|DOMAIN_ENCRYPTION_SECRET=${DOMAIN_ENCRYPTION_SECRET}|" .env
    sed -i "s|ADMIN_PASSWORD=.*|ADMIN_PASSWORD=${ADMIN_PASSWORD}|" .env
    sed -i "s|APP_URL=.*|APP_URL=http://${SERVER_IP}|" .env
    sed -i "s|API_URL=.*|API_URL=http://${SERVER_IP}/api|" .env
    sed -i "s|CORS_ALLOWED_ORIGINS=.*|CORS_ALLOWED_ORIGINS=http://${LOCAL_IP},http://${PUBLIC_IP},http://localhost,https://${LOCAL_IP},https://${PUBLIC_IP},https://localhost|" .env
    sed -i "s|ADMIN_EMAIL=.*|ADMIN_EMAIL=admin@${SERVER_IP}|" .env

    # Fix DATABASE_URL to use the generated password
    sed -i "s|DATABASE_URL=.*|DATABASE_URL=postgres://hostvra:${POSTGRES_PASSWORD}@postgres:5432/hostvra?sslmode=disable|" .env

    success "Environment configured with secure random secrets"
    echo ""
    echo -e "  ${BOLD}Admin Credentials:${NC}"
    echo -e "  ${CYAN}Email:${NC}    admin@${SERVER_IP}"
    echo -e "  ${CYAN}Password:${NC} ${ADMIN_PASSWORD}"
    echo -e ""
    echo -e "  ${YELLOW}⚠ Save these credentials now! They are only shown once.${NC}"
    echo ""
}

# ── Configure Firewall ───────────────────────────────────────────────────────
configure_firewall() {
    if command -v ufw &>/dev/null; then
        info "Configuring UFW firewall..."
        ufw allow 22/tcp   >/dev/null 2>&1 || true  # SSH
        ufw allow 80/tcp   >/dev/null 2>&1 || true  # HTTP
        ufw allow 443/tcp  >/dev/null 2>&1 || true  # HTTPS
        ufw --force enable >/dev/null 2>&1 || true
        success "Firewall configured (ports 22, 80, 443 open)"
    else
        warn "UFW not found. Please configure your firewall manually to allow ports 80/443."
    fi
}

# ── Build & Start ────────────────────────────────────────────────────────────
deploy() {
    cd "$INSTALL_DIR"

    info "Building Docker images (this may take 3-5 minutes on first run)..."
    docker compose -f docker-compose.prod.yml build --no-cache 2>&1 | \
        while IFS= read -r line; do
            echo -e "  ${CYAN}│${NC} $line"
        done

    info "Starting Hostvra platform..."
    docker compose -f docker-compose.prod.yml up -d

    # Wait for health checks
    info "Waiting for services to become healthy..."
    local retries=0
    local max_retries=30
    while [[ $retries -lt $max_retries ]]; do
        if docker compose -f docker-compose.prod.yml ps --format json 2>/dev/null | \
           grep -q '"Health":"healthy"' || \
           curl -sf http://localhost/health >/dev/null 2>&1; then
            break
        fi
        retries=$((retries + 1))
        sleep 2
    done

    if [[ $retries -ge $max_retries ]]; then
        warn "Health checks timed out. Services may still be starting..."
        docker compose -f docker-compose.prod.yml ps
    else
        success "All services are running and healthy!"
    fi
}

# ── Create systemd service for auto-start on boot ────────────────────────────
create_systemd_service() {
    info "Creating systemd service for auto-start on boot..."

    cat > /etc/systemd/system/hostvra.service << EOF
[Unit]
Description=Hostvra Server Management Platform
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose -f docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.prod.yml down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hostvra.service >/dev/null 2>&1
    success "Systemd service created and enabled"
}

# ── Create update helper ─────────────────────────────────────────────────────
create_update_command() {
    cat > /usr/local/bin/hostvra-update << 'UPDATESCRIPT'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="/opt/hostvra"
cd "$INSTALL_DIR"

# Ensure DNS is working
if ! getent hosts github.com >/dev/null 2>&1; then
    echo "[WARN] DNS resolution issue detected, applying fallback DNS..."
    echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf 2>/dev/null || true
fi

echo "[INFO] Pulling latest code..."
git fetch origin main
git reset --hard origin/main
echo "[INFO] Rebuilding Docker images..."
docker compose -f docker-compose.prod.yml build
echo "[INFO] Restarting services (zero-downtime)..."
docker compose -f docker-compose.prod.yml up -d --remove-orphans
echo "[INFO] Cleaning old images..."
docker image prune -f
echo "[SUCCESS] Hostvra updated successfully!"
docker compose -f docker-compose.prod.yml ps
UPDATESCRIPT

    chmod +x /usr/local/bin/hostvra-update
    success "Update command installed: hostvra-update"
}

# ── Print Summary ────────────────────────────────────────────────────────────
print_summary() {
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    PUBLIC_IP=$(curl -sf -m 2 https://api.ipify.org 2>/dev/null || echo "$LOCAL_IP")

    if [[ "$LOCAL_IP" =~ ^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]]; then
        PRIMARY_IP="$LOCAL_IP"
    else
        PRIMARY_IP="$PUBLIC_IP"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}   Hostvra Platform — Installed Successfully!${NC}"
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Panel URL (LAN/VM):${NC}  http://${LOCAL_IP}"
    if [[ "$PUBLIC_IP" != "$LOCAL_IP" ]]; then
        echo -e "  ${BOLD}Public WAN URL:${NC}      http://${PUBLIC_IP} (requires router port 80 forwarding)"
    fi
    echo -e "  ${BOLD}API Health:${NC}          http://${LOCAL_IP}/health"
    echo -e "  ${BOLD}Install Dir:${NC}         ${INSTALL_DIR}"
    echo ""
    echo -e "  ${BOLD}Useful Commands:${NC}"
    echo -e "  ${CYAN}hostvra-update${NC}                              — Update to latest version"
    echo -e "  ${CYAN}cd ${INSTALL_DIR} && docker compose -f docker-compose.prod.yml ps${NC}     — Status"
    echo -e "  ${CYAN}cd ${INSTALL_DIR} && docker compose -f docker-compose.prod.yml logs -f${NC} — Logs"
    echo -e "  ${CYAN}cd ${INSTALL_DIR} && docker compose -f docker-compose.prod.yml down${NC}   — Stop"
    echo -e "  ${CYAN}cd ${INSTALL_DIR} && docker compose -f docker-compose.prod.yml up -d${NC}  — Start"
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    echo -e "  1. Point your domain DNS A record to ${PRIMARY_IP}"
    echo -e "  2. Edit ${INSTALL_DIR}/.env with your domain & SMTP settings"
    echo -e "  3. Run ${CYAN}hostvra-update${NC} to apply changes"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    print_banner
    preflight
    sync_clock
    install_docker
    install_git
    setup_repository
    configure_env
    configure_firewall
    deploy
    create_systemd_service
    create_update_command
    print_summary
}

main "$@"
