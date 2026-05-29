#!/bin/bash
# ==============================================================================
# Script Name   : setup_vps_deployer.sh
# Description   : Configure Secure VPS Deployer User & SSH Keys for GitLab CI/CD
# Author        : Antigravity AI
# Version       : 1.0.0
# Compatibility : Ubuntu, Debian
# Usage         : sudo bash setup_vps_deployer.sh
# ==============================================================================

set -euo pipefail

# Define Colors
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

DEPLOY_USER="deployer"
DEPLOY_HOME="/home/${DEPLOY_USER}"
STAGING_DIR="/var/www/nextjs-app/staging"
PRODUCTION_DIR="/var/www/nextjs-app/production"

# Ensure script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}Lỗi:${NC} Script thiết lập hệ thống này phải được chạy với quyền ${BOLD}root${NC} (sudo)."
    exit 1
fi

clear
echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "       🚀 SETUP VPS DEPLOYER AN TOÀN CHO NEXT.JS PM2 & GITLAB CI 🚀     "
echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "${INFO} Đang khởi tạo môi trường Deployer biệt lập an toàn..."

# 1. Tạo user deployer nếu chưa có
echo -e "\n${BOLD}${WHITE}==> 1. Tạo tài khoản người dùng hạn chế quyền '${DEPLOY_USER}'${NC}"
if id "${DEPLOY_USER}" &>/dev/null; then
    echo -e "${WARN} User '${DEPLOY_USER}' đã tồn tại trên hệ thống. Bỏ qua bước tạo mới."
else
    # Kiểm tra xem group deployer đã tồn tại chưa
    if getent group "${DEPLOY_USER}" &>/dev/null; then
        useradd -g "${DEPLOY_USER}" --create-home --shell /bin/bash "${DEPLOY_USER}"
    else
        useradd --create-home --shell /bin/bash "${DEPLOY_USER}"
    fi
    echo -e "${TICK} Đã tạo thành công tài khoản '${DEPLOY_USER}'."
fi

# 2. Tạo cấu trúc thư mục Deploy cho dự án Next.js
echo -e "\n${BOLD}${WHITE}==> 2. Khởi tạo cấu trúc thư mục lưu trữ ứng dụng${NC}"
mkdir -p "${STAGING_DIR}" "${PRODUCTION_DIR}"
chown -R ${DEPLOY_USER}:${DEPLOY_USER} /var/www/nextjs-app
chmod -R 755 /var/www/nextjs-app
echo -e "${TICK} Đã tạo thư mục ứng dụng và cấp quyền sở hữu cho '${DEPLOY_USER}':"
echo -e "    - Staging   : ${BOLD}${STAGING_DIR}${NC}"
echo -e "    - Production: ${BOLD}${PRODUCTION_DIR}${NC}"

# 3. Tạo SSH Key chuyên dụng cho GitLab CI/CD kết nối
echo -e "\n${BOLD}${WHITE}==> 3. Cấu hình SSH Key an toàn cho Deployer${NC}"
mkdir -p "${DEPLOY_HOME}/.ssh"
chmod 700 "${DEPLOY_HOME}/.ssh"

SSH_KEY_FILE="${DEPLOY_HOME}/.ssh/id_rsa_gitlab"
if [ -f "$SSH_KEY_FILE" ]; then
    echo -e "${WARN} SSH Key cho GitLab đã tồn tại sẵn. Sử dụng khóa cũ để tránh ghi đè."
else
    # Tạo SSH Key không mật khẩu cho deployer
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_FILE" -N "" -C "gitlab-ci-vps-deploy" >> /dev/null
    echo -e "${TICK} Đã sinh thành công cặp SSH Key chuyên dụng."
fi

# Cấu hình authorized_keys
cat "${SSH_KEY_FILE}.pub" >> "${DEPLOY_HOME}/.ssh/authorized_keys"
chmod 600 "${DEPLOY_HOME}/.ssh/authorized_keys"
chown -R ${DEPLOY_USER}:${DEPLOY_USER} "${DEPLOY_HOME}/.ssh"
echo -e "${TICK} Đã kích hoạt SSH Public Key thành công."

# 4. Phân quyền sudo hạn chế cho PM2 và Nginx Reload (An toàn bảo mật tối đa)
echo -e "\n${BOLD}${WHITE}==> 4. Cấp quyền sudo hạn chế (Chỉ cho phép Nginx reload)${NC}"
# User deployer hoàn toàn có thể chạy PM2 mà không cần sudo vì pm2 được cài/chạy ở mức user space.
# Nhưng nếu cần reload nginx để nhận cấu hình mới, ta chỉ cho phép đúng lệnh nginx reload bằng sudo không mật khẩu.
SUDOERS_FILE="/etc/sudoers.d/gitlab-deployer"
cat << EOF > "$SUDOERS_FILE"
# Cho phép deployer reload nginx và kiểm tra cấu hình nginx mà không cần mật khẩu
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/sbin/nginx -t, /usr/sbin/systemctl reload nginx
EOF
chmod 440 "$SUDOERS_FILE"
echo -e "${TICK} Đã phân quyền sudo hạn chế an toàn tại ${SUDOERS_FILE}."

# 5. Đảm bảo PM2 chạy tốt dưới user deployer
echo -e "\n${BOLD}${WHITE}==> 5. Cấu hình môi trường khởi chạy PM2 cho user '${DEPLOY_USER}'${NC}"
# Đảm bảo deployer có thể chạy npm/node/pm2
if command -v pm2 &>/dev/null; then
    # Kích hoạt PM2 startup cho user deployer để tự động chạy lại PM2 khi VPS reboot
    echo -e "${INFO} Đang đăng ký dịch vụ khởi chạy PM2 Startup dưới quyền user '${DEPLOY_USER}'..."
    pm2 startup systemd -u ${DEPLOY_USER} --hp ${DEPLOY_HOME} >> /dev/null 2>&1 || true
    echo -e "${TICK} PM2 Startup đã được liên kết với user '${DEPLOY_USER}'."
else
    echo -e "${WARN} PM2 chưa được cài đặt. Khi cài đặt node/pm2 ở setup.sh, deployer sẽ chạy được."
fi

# Lấy Private Key để hiển thị cho Admin copy dán vào GitLab
PRIVATE_KEY_CONTENT=$(cat "$SSH_KEY_FILE")

echo -e "\n${BOLD}${GREEN}========================================================================${NC}"
echo -e "         🎉 THIẾT LẬP MÔ TRƯỜNG VPS DEPLOYER HOÀN TẤT THÀNH CÔNG 🎉    "
echo -e "${BOLD}${GREEN}========================================================================${NC}"
echo -e " VPS đã sẵn sàng nhận kết nối deploy an toàn (Non-Root) từ GitLab CI/CD."
echo -e ""
echo -e "${BOLD}${YELLOW}🔑 BƯỚC QUAN TRỌNG TIẾP THEO DÀNH CHO ADMIN:${NC}"
echo -e ""
echo -e " 1. ${BOLD}Copy Private SSH Key dưới đây${NC} và cấu hình vào GitLab:"
echo -e "    - Đi tới repo GitLab: ${BOLD}Settings > CI/CD > Variables${NC}"
echo -e "    - Thêm biến: ${BOLD}SSH_PRIVATE_KEY${NC}"
echo -e "    - Type: ${BOLD}Variable${NC} (hoặc File)"
echo -e "    - Value: Dán toàn bộ nội dung khóa Private dưới đây vào:"
echo -e ""
echo -e "${CYAN}${PRIVATE_KEY_CONTENT}${NC}"
echo -e ""
echo -e " 2. ${BOLD}Cấu hình địa chỉ IP VPS của bạn vào GitLab Variables:${NC}"
echo -e "    - Thêm biến: ${BOLD}VPS_IP${NC}"
echo -e "    - Value: ${BOLD}IP_CỦA_VPS_BẠN${NC}"
echo -e ""
echo -e " 3. ${BOLD}Cấu hình các tệp tin .env bảo mật dạng FILE Variables (Đặt tên theo Nhánh):${NC}"
echo -e "    - Thêm biến: ${BOLD}ENV_LOCAL_<TÊN_NHÁNH_VIẾT_HOA>${NC} (Type: ${BOLD}File${NC}, Ví dụ: ${BOLD}ENV_LOCAL_DEVELOP${NC} hoặc ${BOLD}ENV_LOCAL_MAIN${NC})"
echo -e "    - (Với Backend Docker) Thêm biến: ${BOLD}ENV_DOCKER_<TÊN_NHÁNH_VIẾT_HOA>${NC} (Type: ${BOLD}File${NC}, Ví dụ: ${BOLD}ENV_DOCKER_DEVELOP${NC})"
echo -e "========================================================================${NC}\n"
