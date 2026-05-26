#!/bin/bash
# ==============================================================================
# Script Name   : quick_setup_site.sh
# Description   : Automated FE Deployer (Nginx Reverse Proxy + PM2 + SSL Certbot)
# Author        : Antigravity AI
# Version       : 1.0.0
# Usage         : sudo bash quick_setup_site.sh <domain> <port> <yes-eco|no-eco>
# ==============================================================================

# Define Colors for Terminal Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Status Icons
TICK="${GREEN}[✔]${NC}"
CROSS="${RED}[✘]${NC}"
WARN="${YELLOW}[⚠]${NC}"
INFO="${BLUE}[ℹ]${NC}"

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}Error:${NC} This script must be run as ${BOLD}root${NC} (or with sudo)."
    exit 1
fi

# Check arguments
if [ "$#" -ne 3 ]; then
    echo -e "${RED}${BOLD}Error:${NC} Invalid number of arguments."
    echo -e "Usage: sudo bash quick_setup_site.sh <domain> <port> <yes-eco|no-eco>"
    echo -e "Example: sudo bash quick_setup_site.sh vsoftware.vn 3008 yes-eco"
    exit 1
fi

DOMAIN=$1
PORT=$2
CREATE_ECO=$3

PROJECT_PATH="/var/www/$DOMAIN"

echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "${BOLD}${WHITE}    🚀 STAR-BASH QUICK FE SITE DEPLOYER (Strict Params) 🚀             ${NC}"
echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "${INFO} Domain      : ${BOLD}${DOMAIN}${NC}"
echo -e "${INFO} Port        : ${BOLD}${PORT}${NC}"
echo -e "${INFO} PM2 Eco     : ${BOLD}${CREATE_ECO}${NC}"
echo -e "${INFO} Target Path : ${BOLD}${PROJECT_PATH}${NC}"
echo -e "${BOLD}${CYAN}========================================================================${NC}\n"

# 1. Create project directory if not exists
if [ ! -d "$PROJECT_PATH" ]; then
    echo -e "${INFO} Creating project folder at ${PROJECT_PATH}..."
    mkdir -p "$PROJECT_PATH"
    chown -R www-data:www-data "$PROJECT_PATH"
    echo -e "${TICK} Project folder created."
else
    echo -e "${WARN} Project folder ${PROJECT_PATH} already exists."
fi

# 2. Generate PM2 ecosystem.config.js if requested
if [ "$CREATE_ECO" = "yes-eco" ]; then
    echo -e "${INFO} Generating ecosystem.config.js..."
    cat <<EOF > "$PROJECT_PATH/ecosystem.config.js"
module.exports = {
  apps: [
    {
      name: "${DOMAIN}-fe",
      script: "npm",
      args: "start",
      env: {
        PORT: ${PORT},
        NODE_ENV: "production"
      }
    }
  ]
};
EOF
    echo -e "${TICK} PM2 file generated at ${BOLD}${PROJECT_PATH}/ecosystem.config.js${NC}"
else
    echo -e "${WARN} PM2 ecosystem.config.js generation skipped."
fi

# 3. Create Nginx config site file
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}"
echo -e "${INFO} Generating Nginx site configuration..."

cat <<EOF > "$NGINX_CONF"
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable Nginx configuration
ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/${DOMAIN}"
echo -e "${TICK} Nginx configuration created at ${BOLD}${NGINX_CONF}${NC}"

# Test and reload Nginx
if nginx -t &>/dev/null; then
    systemctl reload nginx
    echo -e "${TICK} Nginx reloaded successfully."
else
    echo -e "${CROSS} ${RED}Nginx configuration test failed! Please check manually.${NC}"
    exit 1
fi

# 4. Get SSL Certificate using Certbot
echo -e "${INFO} Checking Certbot for SSL Certificate installation..."
if command -v certbot &>/dev/null; then
    echo -e "${INFO} Running Certbot to generate and configure SSL for ${DOMAIN} & www.${DOMAIN}..."
    
    # Run certbot non-interactively
    if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect; then
        echo -e "${TICK} ${GREEN}SSL certificate successfully configured with auto-redirect to HTTPS!${NC}"
    else
        echo -e "${WARN} Certbot failed to generate SSL. Trying without www subdomain..."
        if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect; then
            echo -e "${TICK} ${GREEN}SSL certificate successfully configured for ${DOMAIN} only!${NC}"
        else
            echo -e "${CROSS} ${RED}Certbot failed. Please verify DNS records are pointing to this server's IP.${NC}"
        fi
    fi
else
    echo -e "${WARN} 'certbot' command not found! Skipping SSL certificate generation."
    echo -e "You can install it manually by running: ${BOLD}sudo apt install certbot python3-certbot-nginx -y${NC}"
fi

echo -e "\n${BOLD}${GREEN}========================================================================${NC}"
echo -e "${BOLD}${GREEN} 🎉 SETUP COMPLETE FOR ${DOMAIN}!${NC}"
echo -e "${BOLD}${GREEN}========================================================================${NC}"
echo -e " - Project Directory : ${PROJECT_PATH}"
if [ "$CREATE_ECO" = "yes-eco" ]; then
    echo -e " - PM2 Config File  : ${PROJECT_PATH}/ecosystem.config.js"
fi
echo -e " - Nginx Config      : ${NGINX_CONF}"
echo -e " - Port reverse proxy: ${PORT}"
echo -e " - Status            : Active & Proxying."
echo -e "${BOLD}${GREEN}========================================================================${NC}\n"
