#!/bin/bash
# ==============================================================================
# Script Name   : interactive_setup_site.sh
# Description   : Step-by-Step Interactive FE Deployer (Nginx + PM2 + SSL Certbot)
# Author        : Antigravity AI
# Version       : 1.0.0
# Usage         : sudo bash interactive_setup_site.sh
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

clear
echo -e "${BOLD}${CYAN}"
echo "========================================================================"
echo "    🌟 STAR-BASH INTERACTIVE FE SITE DEPLOYER & HARDENER 🌟              "
echo "========================================================================"
echo -e "${NC}"

# 1. Ask for Domain
while true; do
    read -p "👉 Nhập tên miền của bạn (ví dụ: vsoftware.vn): " DOMAIN
    if [ -n "$DOMAIN" ] && [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        echo -e "${CROSS} Tên miền không hợp lệ! Vui lòng thử lại."
    fi
done

# 2. Ask for Port
while true; do
    read -p "👉 Nhập cổng (Port) ứng dụng Node/FE (ví dụ: 3008): " PORT
    if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -gt 0 ] && [ "$PORT" -le 65535 ]; then
        break
    else
        echo -e "${CROSS} Cổng không hợp lệ! Vui lòng nhập số từ 1 đến 65535."
    fi
done

# 3. Intelligent Directory Chooser
echo -e "\n${BOLD}${YELLOW}📂 Đang quét các thư mục khả dụng để triển khai...${NC}"
AVAILABLE_DIRS=()
INDEX=1

# Default auto-create option
echo -e " [${INDEX}] Thư mục mặc định: ${BOLD}/var/www/${DOMAIN}${NC} (Tự tạo mới)"
AVAILABLE_DIRS+=("/var/www/${DOMAIN}")
INDEX=$((INDEX + 1))

# Current directory
CURRENT_DIR=$(pwd)
echo -e " [${INDEX}] Thư mục hiện tại: ${BOLD}${CURRENT_DIR}${NC}"
AVAILABLE_DIRS+=("${CURRENT_DIR}")
INDEX=$((INDEX + 1))

# Search for folders in current directory
for d in */ ; do
    if [ -d "$d" ]; then
        full_path=$(realpath "$d")
        # Prevent listing system directories or massive duplicates
        if [ "$full_path" != "/var/www" ] && [ "$full_path" != "/home" ]; then
            echo -e " [${INDEX}] Thư mục con hiện tại: ${BOLD}${full_path}${NC}"
            AVAILABLE_DIRS+=("${full_path}")
            INDEX=$((INDEX + 1))
        fi
    fi
done

# Search for folders in /var/www if it exists and has child folders
if [ -d "/var/www" ]; then
    for d in /var/www/*/ ; do
        if [ -d "$d" ]; then
            full_path=$(realpath "$d")
            # Don't duplicate the default option
            if [ "$full_path" != "/var/www/${DOMAIN}" ]; then
                echo -e " [${INDEX}] Thư mục tại /var/www: ${BOLD}${full_path}${NC}"
                AVAILABLE_DIRS+=("${full_path}")
                INDEX=$((INDEX + 1))
            fi
        fi
    done
fi

echo -e " [${INDEX}] 📝 ${BOLD}Nhập đường dẫn thủ công tùy ý${NC}"

# Get folder choice
while true; do
    read -p "👉 Vui lòng chọn thư mục dự án [1-${INDEX}]: " dir_choice
    if [[ "$dir_choice" =~ ^[0-9]+$ ]] && [ "$dir_choice" -gt 0 ] && [ "$dir_choice" -le "$INDEX" ]; then
        break
    else
        echo -e "${CROSS} Lựa chọn không hợp lệ! Hãy chọn số từ 1 đến ${INDEX}."
    fi
done

if [ "$dir_choice" -eq "$INDEX" ]; then
    # Custom input
    while true; do
        read -p "👉 Nhập đường dẫn thư mục dự án đầy đủ: " PROJECT_PATH
        if [ -n "$PROJECT_PATH" ]; then
            break
        else
            echo -e "${CROSS} Đường dẫn không được để trống!"
        fi
    done
else
    # Resolved from scanner
    arr_idx=$((dir_choice - 1))
    PROJECT_PATH="${AVAILABLE_DIRS[$arr_idx]}"
fi

echo -e "${TICK} Đã chọn thư mục dự án: ${BOLD}${PROJECT_PATH}${NC}"

# 4. Ask for PM2 ecosystem file
read -p "👉 Bạn có muốn tạo file ecosystem.config.js cho PM2 không? (y/N): " choice_eco
case "$choice_eco" in
    [yY][eE][sS]|[yY]) CREATE_ECO="yes" ;;
    *) CREATE_ECO="no" ;;
esac

# 5. Ask for SSL
read -p "👉 Bạn có muốn cài đặt chứng chỉ bảo mật SSL bằng Certbot không? (y/N): " choice_ssl
case "$choice_ssl" in
    [yY][eE][sS]|[yY]) ACTIVATE_SSL="yes" ;;
    *) ACTIVATE_SSL="no" ;;
esac

# ==============================================================================
# CONFIRMATION & EXECUTION
# ==============================================================================
echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
echo -e "${BOLD}${WHITE}               🛠️  TÓM TẮT CẤU HÌNH SẼ TRIỂN KHAI                     ${NC}"
echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e " 🚀 Domain        : ${BOLD}${DOMAIN}${NC}"
echo -e " 🔌 Port Proxy    : http://127.0.0.1:${BOLD}${PORT}${NC}"
echo -e " 📂 Thư mục dự án : ${BOLD}${PROJECT_PATH}${NC}"
echo -e " 📦 Ecosystem PM2 : $([ "$CREATE_ECO" = "yes" ] && echo -e "${GREEN}CÓ${NC}" || echo -e "${RED}KHÔNG${NC}")"
echo -e " 🔒 Cấp SSL       : $([ "$ACTIVATE_SSL" = "yes" ] && echo -e "${GREEN}CÓ${NC}" || echo -e "${RED}KHÔNG${NC}")"
echo -e "${BOLD}${CYAN}========================================================================${NC}"
read -p "Tiến hành triển khai ngay? (Y/n): " confirm_deploy
case "$confirm_deploy" in
    [nN][oO]|[nN])
        echo -e "${WARN} Triển khai đã bị hủy bởi người dùng."
        exit 0
        ;;
esac

# 1. Create project folder if not exists
if [ ! -d "$PROJECT_PATH" ]; then
    echo -e "\n${INFO} Đang tạo thư mục dự án..."
    mkdir -p "$PROJECT_PATH"
    chown -R www-data:www-data "$PROJECT_PATH" 2>/dev/null
    echo -e "${TICK} Tạo thư mục dự án thành công."
fi

# 2. Write ecosystem.config.js
if [ "$CREATE_ECO" = "yes" ]; then
    echo -e "${INFO} Đang sinh file ecosystem.config.js..."
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
    echo -e "${TICK} Đã sinh file tại: ${BOLD}${PROJECT_PATH}/ecosystem.config.js${NC}"
fi

# 3. Create Nginx Site
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}"
echo -e "${INFO} Đang khởi tạo tệp cấu hình Nginx..."

cat <<EOF > "$NGINX_CONF"
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

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

# Activate in Nginx
ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/${DOMAIN}"
echo -e "${TICK} Tạo cấu hình Nginx thành công tại: ${BOLD}${NGINX_CONF}${NC}"

# Reload Nginx
if nginx -t &>/dev/null; then
    systemctl reload nginx
    echo -e "${TICK} Nginx đã được nạp lại cấu hình thành công."
else
    echo -e "${CROSS} ${RED}Kiểm tra cấu hình Nginx phát hiện lỗi! Vui lòng kiểm tra lại thủ công.${NC}"
    exit 1
fi

# 4. Handle SSL
if [ "$ACTIVATE_SSL" = "yes" ]; then
    echo -e "${INFO} Đang kiểm tra Certbot để cấp chứng chỉ SSL..."
    if command -v certbot &>/dev/null; then
        echo -e "${INFO} Đang xin cấp chứng chỉ bảo mật cho ${DOMAIN}..."
        if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect; then
            echo -e "${TICK} ${GREEN}Đã cấu hình SSL cho ${DOMAIN} thành công!${NC}"
        else
            echo -e "${CROSS} ${RED}Gặp lỗi khi tạo chứng chỉ SSL. Hãy đảm bảo tên miền đã được trỏ IP về VPS này.${NC}"
        fi
    else
        echo -e "${WARN} Không tìm thấy 'certbot'! Bỏ qua bước cấp SSL."
        echo -e "Bạn có thể cài đặt bằng lệnh: ${BOLD}sudo apt install certbot python3-certbot-nginx -y${NC}"
    fi
fi

echo -e "\n${BOLD}${GREEN}========================================================================${NC}"
echo -e "${BOLD}${GREEN} 🎉 QUÁ TRÌNH TRIỂN KHAI HOÀN TẤT THÀNH CÔNG!${NC}"
echo -e "${BOLD}${GREEN}========================================================================${NC}"
echo -e " 📂 Thư mục dự án: ${PROJECT_PATH}"
if [ "$CREATE_ECO" = "yes" ]; then
    echo -e " 📦 Cấu hình PM2 : ${PROJECT_PATH}/ecosystem.config.js"
fi
echo -e " ⚙️ Cấu hình Nginx: ${NGINX_CONF}"
echo -e " 🔌 Reverse Proxy: Cổng ${PORT}"
echo -e "${BOLD}${GREEN}========================================================================${NC}\n"
