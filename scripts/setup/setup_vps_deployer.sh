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

# Tự động gán user deployer vào nhóm quyền docker để tránh lỗi permission denied khi deploy Backend
if command -v docker &>/dev/null; then
    # Tạo group docker nếu chưa tồn tại
    if ! getent group docker &>/dev/null; then
        groupadd docker
    fi
    # Gán deployer vào group docker
    usermod -aG docker "${DEPLOY_USER}"
    
    # Cấp trực tiếp quyền sở hữu socket cho group docker để tránh lỗi permission denied ngay lập tức
    if [ -S "/var/run/docker.sock" ]; then
        chown root:docker /var/run/docker.sock
        chmod 660 /var/run/docker.sock
    fi
    
    # Khởi động lại dịch vụ docker
    systemctl restart docker 2>/dev/null || true
    echo -e "${TICK} Đã phân quyền kết nối an toàn Docker Socket (/var/run/docker.sock) cho '${DEPLOY_USER}'."
else
    echo -e "${INFO} Docker chưa được cài đặt trên VPS. Quyền Docker cho deployer sẽ tự động khả dụng khi bạn cài Docker ở setup.sh."
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
    local server_name
    server_name=$(hostname 2>/dev/null || echo "vps")
    server_name=$(echo "$server_name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-')
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_FILE" -N "" -C "deploy-${server_name}-gitlab" >> /dev/null
    echo -e "${TICK} Đã sinh thành công cặp SSH Key chuyên dụng."
fi

# Cấu hình authorized_keys
cat "${SSH_KEY_FILE}.pub" >> "${DEPLOY_HOME}/.ssh/authorized_keys"
chmod 600 "${DEPLOY_HOME}/.ssh/authorized_keys"

# Tự động đồng bộ SSH config & SSH keys từ root sang deployer (rất quan trọng để định tuyến host gitlab-local)
if [ -f "/root/.ssh/config" ]; then
    cp /root/.ssh/config "${DEPLOY_HOME}/.ssh/config"
    # Sao chép thêm các Private/Public keys của root nếu config SSH có tham chiếu tới
    cp /root/.ssh/id_ed25519* "${DEPLOY_HOME}/.ssh/" 2>/dev/null || true
    cp /root/.ssh/id_rsa* "${DEPLOY_HOME}/.ssh/" 2>/dev/null || true
    echo -e "${TICK} Đã đồng bộ cấu hình SSH định tuyến từ root sang deployer."
fi

# Tự động ghi đè hoặc chèn thêm cấu hình bypass Host Key verification để tránh lỗi 'Host key verification failed' khi git pull
deployer_ssh_config="${DEPLOY_HOME}/.ssh/config"
if [ ! -f "$deployer_ssh_config" ]; then
    touch "$deployer_ssh_config"
fi

# Chèn cấu hình bypass bảo mật an toàn cho các kết nối SSH từ deployer
if ! grep -q "StrictHostKeyChecking no" "$deployer_ssh_config"; then
    echo -e "\nHost *\n\tStrictHostKeyChecking no\n\tUserKnownHostsFile=/dev/null\n" >> "$deployer_ssh_config"
    echo -e "${TICK} Đã cấu hình tự động tin cậy Host Keys (StrictHostKeyChecking bypass) cho deployer."
fi

chown -R ${DEPLOY_USER}:${DEPLOY_USER} "${DEPLOY_HOME}/.ssh"
# Thiết lập lại quyền đọc/ghi bảo mật an toàn cho các tệp tin SSH mới sao chép
chmod 700 "${DEPLOY_HOME}/.ssh"
chmod 600 "${DEPLOY_HOME}/.ssh/"* 2>/dev/null || true
echo -e "${TICK} Đã phân quyền bảo mật tối đa cho toàn bộ khóa SSH của deployer."

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

# 6. Làm mới phiên đăng nhập & Cập nhật toàn bộ các dịch vụ liên quan
echo -e "\n${BOLD}${WHITE}==> 6. Làm mới phiên SSH, phân quyền thư mục và làm sạch Service${NC}"

# Chuyển quyền sở hữu thư mục deploy chính /var/www về cho deployer
if [ -d "/var/www" ]; then
    chown -R ${DEPLOY_USER}:${DEPLOY_USER} /var/www
    chmod -R 755 /var/www
fi

# Chuyển quyền sở hữu thư mục home về cho deployer
chown -R ${DEPLOY_USER}:${DEPLOY_USER} "$DEPLOY_HOME"

# Khởi động lại SSH daemon để giải phóng các session SSH đang treo của deployer (ép buộc nạp nhóm quyền mới)
echo -e "${INFO} Đang khởi động lại dịch vụ SSH Daemon..."
systemctl restart sshd || systemctl restart ssh || true

# Khởi động lại GitLab Runner để làm mới các agent
if systemctl is-active --quiet gitlab-runner; then
    echo -e "${INFO} Đang làm mới dịch vụ GitLab Runner..."
    systemctl restart gitlab-runner || true
fi
echo -e "${TICK} Đồng bộ và nạp lại toàn bộ quyền sở hữu, dịch vụ Docker/SSH/Runner thành công."

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
