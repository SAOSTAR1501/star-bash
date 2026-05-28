#!/bin/bash
# ==============================================================================
# Script Name   : orchestrate_fe_project.sh
# Description   : Dedicated FE Next.js Orchestrator (Clone, PM2 Cluster, Nginx,
#                 Certbot SSL, Optimized Multi-branch GitLab CI/CD).
# Author        : Antigravity AI
# Version       : 1.0.0
# Compatibility : Ubuntu, Debian
# Usage         : sudo bash orchestrate_fe_project.sh
# ==============================================================================

set -uo pipefail

# Define Colors for Terminal Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Status Icons
TICK="${GREEN}[✔]${NC}"
CROSS="${RED}[✘]${NC}"
WARN="${YELLOW}[⚠]${NC}"
INFO="${BLUE}[ℹ]${NC}"

# Ensure script is run with root/sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}Lỗi:${NC} Script này phải chạy dưới quyền ${BOLD}root${NC} (sudo)."
    exit 1
fi

clear
echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "       🚀 TRÌNH ĐIỀU PHỐI KHỞI TẠO DỰ ÁN FRONTEND (NEXT.JS / PM2) 🚀   "
echo -e "${BOLD}${CYAN}========================================================================${NC}\n"

# ==============================================================================
# BƯỚC 1: KIỂM TRA ĐIỀU KIỆN CẦN (PREREQUISITES)
# ==============================================================================
echo -e "${BOLD}${WHITE}==> Bước 1: Kiểm tra các thành phần hệ thống cần thiết${NC}"

# 1. Kiểm tra user 'deployer'
if ! getent passwd deployer &>/dev/null; then
    echo -e "${WARN} Không tìm thấy user hạn chế '${BOLD}deployer${NC}' trên VPS."
    read -p "❓ Bạn có muốn chạy script cấu hình user 'deployer' ngay bây giờ không? (Y/n): " run_setup_deployer
    run_setup_deployer=${run_setup_deployer:-"y"}
    if [[ "$run_setup_deployer" =~ ^[yY] ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
        if [ -f "$SCRIPT_DIR/setup_vps_deployer.sh" ]; then
            bash "$SCRIPT_DIR/setup_vps_deployer.sh"
        else
            echo -e "${CROSS} Không tìm thấy file script setup_vps_deployer.sh."
            exit 1
        fi
    else
        echo -e "${CROSS} Huỷ bỏ thiết lập. User deployer là bắt buộc để quản lý phân quyền an toàn."
        exit 1
    fi
else
    echo -e "${TICK} User '${BOLD}deployer${NC}' đã tồn tại sẵn."
fi

# 2. Kiểm tra GitLab Runner
if ! command -v gitlab-runner &>/dev/null; then
    echo -e "${WARN} Không tìm thấy '${BOLD}gitlab-runner${NC}' được cài đặt trên VPS."
    read -p "❓ Bạn có muốn cài đặt và cấu hình GitLab Runner an toàn ngay không? (y/N): " run_setup_runner
    run_setup_runner=${run_setup_runner:-"n"}
    if [[ "$run_setup_runner" =~ ^[yY] ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
        if [ -f "$SCRIPT_DIR/setup_gitlab_runner.sh" ]; then
            bash "$SCRIPT_DIR/setup_gitlab_runner.sh"
        else
            echo -e "${CROSS} Không tìm thấy file script setup_gitlab_runner.sh."
            exit 1
        fi
    fi
else
    echo -e "${TICK} GitLab Runner đã được cài đặt sẵn."
fi

# ==============================================================================
# BƯỚC 2: THU THẬP THÔNG TIN TƯƠNG TÁC
# ==============================================================================
echo -e "\n${BOLD}${WHITE}==> Bước 2: Nhập thông tin dự án Frontend mới${NC}"

# 1. Nhập Domain
while true; do
    read -p "👉 Nhập tên miền chạy dự án FE (Ví dụ: vitech.vn): " domain
    domain=$(echo "$domain" | tr -d '[:space:]')
    if [ -n "$domain" ]; then
        break
    else
        echo -e "${CROSS} Tên miền không được để trống."
    fi
done

APP_PATH="/home/${domain}"

# 2. Nhập GitLab Remote URL
while true; do
    read -p "👉 Nhập đường dẫn Git Remote SSH (Ví dụ: gitlab-local:vitechgroup/my-app.git): " git_url
    git_url=$(echo "$git_url" | tr -d '[:space:]')
    if [ -n "$git_url" ]; then
        break
    else
        echo -e "${CROSS} Git Remote URL không được để trống."
    fi
done

# 3. Nhập Cổng dịch vụ (Port) và Kiểm tra trùng lặp
port=""
while true; do
    read -p "👉 Nhập cổng chạy Node.js cho Frontend (Ví dụ: 3000): " port
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 1024 ] && [ "$port" -lt 65535 ]; then
        # Kiểm tra trùng lặp cổng
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            echo -e "${WARN} Cảnh báo: Cổng ${BOLD}${port}${NC} hiện đang bị chiếm giữ bởi dịch vụ khác."
            read -p "❓ Bạn có muốn bỏ qua cảnh báo và tiếp tục sử dụng cổng này? (y/N): " ignore_port
            ignore_port=${ignore_port:-"n"}
            if [[ "$ignore_port" =~ ^[yY] ]]; then
                break
            fi
        else
            echo -e "${TICK} Cổng ${BOLD}${port}${NC} khả dụng."
            break
        fi
    else
        echo -e "${CROSS} Cổng không hợp lệ. Vui lòng nhập số từ 1024 đến 65535."
    fi
done

# ==============================================================================
# BƯỚC 3: CLONE MÃ NGUỒN AN TOÀN
# ==============================================================================
echo -e "\n${BOLD}${WHITE}==> Bước 3: Thực hiện tải mã nguồn (Clone Repo) dưới quyền deployer${NC}"

if [ -d "$APP_PATH" ]; then
    echo -e "${WARN} Phát hiện thư mục ${BOLD}${APP_PATH}${NC} đã tồn tại trên hệ thống."
    echo -e "  [1] Xóa thư mục cũ và clone mới lại từ đầu"
    echo -e "  [2] Giữ nguyên thư mục cũ và tiếp tục cấu hình"
    echo -e "  [3] Hủy bỏ tiến trình"
    read -p "Lựa chọn của bạn [1-3]: " dir_choice
    if [ "$dir_choice" = "1" ]; then
        echo -e "${INFO} Đang xóa thư mục cũ..."
        rm -rf "$APP_PATH"
    elif [ "$dir_choice" = "3" ]; then
        echo -e "${CROSS} Tiến trình bị hủy."
        exit 0
    fi
fi

if [ ! -d "$APP_PATH" ]; then
    echo -e "${INFO} Đang clone mã nguồn từ GitLab bằng quyền user '${BOLD}deployer${NC}'..."
    if sudo -u deployer git clone "$git_url" "$APP_PATH"; then
        echo -e "${TICK} Clone mã nguồn thành công về thư mục: ${BOLD}${APP_PATH}${NC}"
    else
        echo -e "${CROSS} Lỗi: Clone mã nguồn thất bại."
        exit 1
    fi
else
    echo -e "${TICK} Sử dụng thư mục dự án đang có sẵn."
fi

# ==============================================================================
# BƯỚC 4: SINH CẤU HÌNH PM2 ECOSYSTEM CLUSTER MODE
# ==============================================================================
echo -e "\n${BOLD}${WHITE}==> Bước 4: Thiết lập file cấu hình PM2 Cluster Mode cho Frontend${NC}"
ECO_FILE="${APP_PATH}/ecosystem.config.js"
write_eco="y"

if [ -f "$ECO_FILE" ]; then
    echo -e "${WARN} File ${BOLD}ecosystem.config.js${NC} đã tồn tại trong dự án."
    read -p "❓ Bạn có muốn ghi đè bằng cấu hình tối ưu mới không? (y/N): " overwrite_eco
    overwrite_eco=${overwrite_eco:-"n"}
    if [[ ! "$overwrite_eco" =~ ^[yY] ]]; then
        write_eco="n"
    fi
fi

if [ "$write_eco" = "y" ]; then
    cat <<EOF > "$ECO_FILE"
module.exports = {
  apps: [
    {
      name: "${domain}",
      script: "node_modules/next/dist/bin/next",
      args: "start",
      instances: "max",        // Chạy tối đa số nhân CPU để đạt hiệu năng cao
      exec_mode: "cluster",    // Chế độ Cluster giúp reload zero-downtime
      watch: false,
      max_memory_restart: "1G",
      env: {
        NODE_ENV: "production",
        PORT: ${port}
      }
    }
  ]
};
EOF
    chown deployer:deployer "$ECO_FILE"
    echo -e "${TICK} Đã tạo tệp cấu hình PM2 Cluster Mode thành công."
else
    echo -e "${TICK} Giữ nguyên tệp cấu hình PM2 hiện tại."
fi

# ==============================================================================
# BƯỚC 5: CẤU HÌNH NGINX REVERSE PROXY & SSL CERTBOT
# ==============================================================================
echo -e "\n${BOLD}${WHITE}==> Bước 5: Cấu hình Nginx Reverse Proxy & SSL HTTPS${NC}"

NGINX_CONF="/etc/nginx/sites-available/${domain}"
echo -e "${INFO} Đang tạo cấu hình Nginx..."

cat <<EOF > "$NGINX_CONF"
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    access_log /var/log/nginx/${domain}.access.log;
    error_log /var/log/nginx/${domain}.error.log;

    location / {
        proxy_pass http://127.0.0.1:${port};
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

# Kích hoạt site
ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/${domain}"

# Reload Nginx
if nginx -t &>/dev/null; then
    systemctl reload nginx
    echo -e "${TICK} Đã cấu hình và khởi động lại Nginx."
else
    echo -e "${CROSS} Kiểm tra cú pháp Nginx lỗi. Hãy kiểm tra lại file: ${NGINX_CONF}"
    exit 1
fi

# Đăng ký SSL Certbot
if command -v certbot &>/dev/null; then
    echo -e "${INFO} Đang chạy Certbot tự động cấu hình SSL HTTPS..."
    if certbot --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email --redirect; then
        echo -e "${TICK} SSL đã được cài đặt thành công cho ${domain}."
    else
        echo -e "${CROSS} Certbot cấp SSL thất bại. Hãy chắc chắn bạn đã cấu hình DNS trỏ về IP của VPS."
    fi
else
    echo -e "${WARN} Không tìm thấy Certbot trên VPS. Bỏ qua bước thiết lập SSL HTTPS tự động."
fi

# ==============================================================================
# BƯỚC 6: SINH FILE CẤU HÌNH GITLAB CI/CD ĐA CHI NHÁNH ĐỘNG
# ==============================================================================
echo -e "\n${BOLD}${WHITE}==> Bước 6: Cấu hình GitLab CI/CD Pipeline động theo chi nhánh (Branches)${NC}"

CI_FILE="${APP_PATH}/.gitlab-ci.yml"
write_ci="y"

if [ -f "$CI_FILE" ]; then
    echo -e "${WARN} Phát hiện tệp tin ${BOLD}.gitlab-ci.yml${NC} đã tồn tại sẵn trong dự án."
    read -p "❓ Bạn có muốn ghi đè bằng cấu hình pipeline tối ưu động mới không? (y/N): " overwrite_ci
    overwrite_ci=${overwrite_ci:-"n"}
    if [[ ! "$overwrite_ci" =~ ^[yY] ]]; then
        write_ci="n"
    fi
fi

if [ "$write_ci" = "y" ]; then
    # Nhập danh sách branches
    while true; do
        read -p "👉 Nhập các chi nhánh muốn cấu hình CI/CD, cách nhau bằng dấu phẩy (Ví dụ: develop,main): " branch_input
        branch_input=$(echo "$branch_input" | tr -d '[:space:]')
        if [ -n "$branch_input" ]; then
            break
        else
            echo -e "${CROSS} Danh sách chi nhánh không được để trống."
        fi
    done

    # Tách chuỗi thành mảng
    IFS=',' read -r -a BRANCHES <<< "$branch_input"

    # Bắt đầu dựng nội dung tệp tin .gitlab-ci.yml
    cat <<EOF > "$CI_FILE"
# ==============================================================================
# GitLab CI/CD Pipeline for Next.js - Auto-Generated by Star-Bash Suite
# Project: ${domain}
# Type: Frontend (Next.js / PM2)
# Method: Dynamic Multi-branch optimized pipeline
# ==============================================================================

stages:
  - build
  - deploy

default:
  cache:
    key:
      files:
        - package-lock.json
    paths:
      - .npm/
EOF

    # Lặp qua từng chi nhánh để chèn cấu hình
    for br in "${BRANCHES[@]}"; do
        br_upper=$(echo "$br" | tr '[:lower:]' '[:upper:]' | tr '-' '_' | tr '/' '_')
        echo -e "\n--- Cấu hình Pipeline cho chi nhánh: ${BOLD}${br}${NC} ---"
        
        # Chọn chế độ: Build Only hay Build & Deploy
        mode_choice=""
        while true; do
            echo -e "👉 Chọn chế độ hoạt động cho chi nhánh ${BOLD}${br}${NC}:"
            echo -e "  [1] Chỉ Biên dịch (Build Only - Chỉ kiểm tra lỗi biên dịch, không deploy lên VPS)"
            echo -e "  [2] Biên dịch & Deploy lên VPS (Build & Deploy)"
            read -p "Lựa chọn của bạn [1-2]: " mode_choice
            if [ "$mode_choice" = "1" ] || [ "$mode_choice" = "2" ]; then
                break
            else
                echo -e "${CROSS} Lựa chọn không hợp lệ. Vui lòng chọn 1 hoặc 2."
            fi
        done
        
        # Ghi Job Build vào tệp tin
        cat <<EOF >> "$CI_FILE"

# --- BUILD JOB CHO CHI NHÁNH: ${br} ---
build-${br}:
  stage: build
  image: node:20-alpine
  rules:
    - if: \$CI_COMMIT_BRANCH == "${br}"
  variables:
    ENV_FILE: \$ENV_LOCAL_${br_upper}
  script:
    - echo "==> Khởi tạo môi trường cho chi nhánh ${br}..."
    - cp "\$ENV_FILE" .env.local
    - npm install --cache .npm --prefer-offline
    - npm run build
    - echo "==> Dọn dẹp cache biên dịch để giảm kích thước tệp nén..."
    - rm -rf .next/cache
  artifacts:
    name: "${br}-build-\$CI_COMMIT_REF_SLUG"
    expire_in: 3 days
    paths:
      - .next/
      - public/
      - package.json
      - package-lock.json
      - ecosystem.config.js
      - .env.local
EOF

        # Nếu chọn Build & Deploy, ghi thêm Job Deploy vào tệp tin
        if [ "$mode_choice" = "2" ]; then
            # Thư mục deploy mặc định
            default_deploy_dir="/home/${domain}"
            if [ "$br" != "main" ] && [ "$br" != "master" ]; then
                default_deploy_dir="/home/${domain}-${br}"
            fi
            
            read -p "👉 Nhập thư mục deploy trên VPS cho chi nhánh [${br}] (Mặc định: ${default_deploy_dir}): " deploy_dir
            deploy_dir=${deploy_dir:-"$default_deploy_dir"}
            
            # Đảm bảo thư mục deploy tồn tại trên VPS và thuộc sở hữu của deployer
            mkdir -p "${deploy_dir}"
            chown -R deployer:deployer "${deploy_dir}"
            chmod 755 "${deploy_dir}"
            
            cat <<EOF >> "$CI_FILE"

# --- DEPLOY JOB CHO CHI NHÁNH: ${br} ---
deploy-${br}:
  stage: deploy
  image: alpine:latest
  rules:
    - if: \$CI_COMMIT_BRANCH == "${br}"
  dependencies:
    - build-${br}
  before_script:
    - apk add --no-cache openssh-client tar
    - mkdir -p ~/.ssh
    - eval \$(ssh-agent -s)
    - echo "\$SSH_PRIVATE_KEY" | tr -d '\r' | ssh-add -
    - echo -e "Host *\n\tStrictHostKeyChecking no\n\n" > ~/.ssh/config
  script:
    - echo "==> Bắt đầu đóng gói tệp tin đã biên dịch..."
    - tar -czf build.tar.gz .next public package.json package-lock.json ecosystem.config.js .env.local
    
    - echo "==> Đang tải gói build lên thư mục deploy trên VPS..."
    - scp build.tar.gz deployer@\$VPS_IP:${deploy_dir}/
    
    - echo "==> Giải nén, cài đặt thư viện production và ra lệnh PM2 khởi động lại..."
    - ssh deployer@\$VPS_IP "
        cd ${deploy_dir}/ &&
        tar -xzf build.tar.gz &&
        rm -f build.tar.gz &&
        export PATH=\\\$PATH:/usr/bin:/usr/local/bin &&
        npm install --omit=dev --prefer-offline --no-audit --ignore-scripts &&
        pm2 reload ecosystem.config.js || pm2 start ecosystem.config.js
      "
    - echo "✅ Deploy thành công lên thư mục ${deploy_dir}."
EOF
        fi
    done

    chown deployer:deployer "$CI_FILE"
    echo -e "${TICK} Đã tạo tệp cấu hình GitLab CI/CD đa chi nhánh động thành công."
else
    echo -e "${TICK} Giữ nguyên tệp cấu hình GitLab CI/CD cũ của dự án."
fi

# ==============================================================================
# BƯỚC 7: THIẾT LẬP PHÂN QUYỀN CUỐI CÙNG
# ==============================================================================
echo -e "\n${BOLD}${WHITE}==> Bước 7: Phân quyền tệp tin hệ thống an toàn${NC}"
chown -R deployer:deployer "$APP_PATH"
chmod -R 755 "$APP_PATH"
echo -e "${TICK} Toàn bộ quyền sở hữu thư mục dự án đã chuyển giao cho user ${BOLD}deployer${NC}."

echo -e "\n${BOLD}${GREEN}========================================================================${NC}"
echo -e "       🎉 THIẾT LẬP THÀNH CÔNG DỰ ÁN FRONTEND: ${domain} 🎉"
echo -e "========================================================================${NC}"
echo -e " 1. Thư mục chạy dự án  : ${BOLD}${APP_PATH}${NC}"
echo -e " 2. Cổng dịch vụ        : ${BOLD}${port}${NC}"
echo -e " 3. Tên miền truy cập   : ${GREEN}https://${domain}${NC} (Đã kích hoạt SSL)"
echo -e " 4. PM2 Config          : ${BOLD}${APP_PATH}/ecosystem.config.js${NC}"
echo -e " 5. GitLab CI Config    : ${BOLD}${APP_PATH}/.gitlab-ci.yml${NC}"
echo -e ""
echo -e " 👉 LƯU Ý KHI CHẠY DỰ ÁN LẦN ĐẦU TIÊN:"
echo -e "    Hãy chạy các lệnh sau dưới quyền deployer để ứng dụng được khởi chạy ban đầu:"
echo -e "    ${BOLD}su - deployer${NC}"
echo -e "    ${BOLD}cd ${APP_PATH} && pm2 start ecosystem.config.js && pm2 save${NC}"
echo -e "${BOLD}${GREEN}========================================================================${NC}\n"
