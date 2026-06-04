#!/bin/bash
# ==============================================================================
# Script Name   : setup_warp_gitlab.sh
# Description   : Automates WARP install, Zero Trust register, SSH Keys setup,
#                 and routing tests for secure GitLab Local connection on VPS.
# Author        : Antigravity AI
# Version       : 1.0.0
# Compatibility : Ubuntu, Debian
# Usage         : sudo bash setup_warp_gitlab.sh
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
echo -e "      🦊 HỆ THỐNG THIẾT LẬP CLOUDFLARE WARP & GITLAB LOCAL 🦊          "
echo -e "${BOLD}${CYAN}========================================================================${NC}\n"

# ==============================================================================
# BƯỚC 1: CÀI ĐẶT CLOUDFLARE WARP
# ==============================================================================
echo -e "${BOLD}${WHITE}==> Bước 1: Kiểm tra và cài đặt Cloudflare WARP Client${NC}"

if command -v warp-cli &>/dev/null; then
    echo -e "${TICK} Cloudflare WARP Client đã được cài đặt sẵn."
    warp-cli --version
else
    echo -e "${INFO} Tiến hành cài đặt Cloudflare WARP Client..."
    apt update && apt install -y curl gnupg lsb-release
    
    # Thêm GPG Key
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    
    # Thêm APT Repository
    OS_CODENAME=$(lsb_release -cs)
    # Kiểm tra xem Cloudflare có hỗ trợ codename hiện tại không, nếu không thì fallback về noble (Ubuntu 24.04)
    if ! curl -fsSL -o /dev/null "https://pkg.cloudflareclient.com/dists/${OS_CODENAME}/Release"; then
        echo -e "${WARN} Không tìm thấy repository Cloudflare WARP cho bản phân phối '${OS_CODENAME}'."
        echo -e "${INFO} Tự động chuyển vùng cài đặt (fallback) về 'noble' (Ubuntu 24.04)..."
        OS_CODENAME="noble"
    fi
    
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${OS_CODENAME} main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    
    # Cài đặt
    apt update
    if apt install -y cloudflare-warp; then
        echo -e "${TICK} Đã cài đặt Cloudflare WARP thành công."
        systemctl enable --now warp-svc
        sleep 3
        warp-cli --version
    else
        echo -e "${CROSS} Cài đặt Cloudflare WARP thất bại. Vui lòng kiểm tra lại."
        exit 1
    fi
fi

# ==============================================================================
# BƯỚC 2: LIÊN KẾT ZERO TRUST (ENROLL TEAM)
# ==============================================================================
echo -e "\n${BOLD}${WHITE}==> Bước 2: Liên kết tài khoản Cloudflare Zero Trust Team${NC}"

# Nhập Team Name
read -p "👉 Nhập tên Cloudflare Team của bạn (Mặc định: mktsoftware): " team_name
team_name=${team_name:-"mktsoftware"}

# Kiểm tra trạng thái đăng ký hiện tại
reg_status=$(warp-cli registration show 2>/dev/null || echo "Missing registration")

if echo "$reg_status" | grep -q "Account type: Team" && echo "$reg_status" | grep -q "$team_name"; then
    echo -e "${TICK} Máy chủ đã đăng ký vào Team ${BOLD}${team_name}${NC} trước đó."
    warp-cli registration show
else
    echo -e "${INFO} Đang khởi chạy đăng ký liên kết vào Team: ${BOLD}${team_name}${NC}..."
    warp-cli registration new "$team_name"
    
    echo -e "\n${WARN} Nếu bạn đang chạy trên Server Headless (không có giao diện đồ họa) và gặp lỗi 'Missing registration':"
    read -p "❓ Bạn có cần nạp mã đăng ký Token thủ công không? (y/N): " needs_token
    needs_token=${needs_token:-"n"}
    
    if [[ "$needs_token" =~ ^[yY] ]]; then
        echo -e "\n${BOLD}${YELLOW}HƯỚNG DẪN LẤY TOKEN ĐĂNG KÝ THỦ CÔNG:${NC}"
        echo -e " 1. Truy cập liên kết đăng nhập của Team bạn qua trình duyệt."
        echo -e " 2. Đăng nhập thành công, tại trang hiển thị Success: Chuột phải -> Chọn 'Xem nguồn trang' (View Source)."
        echo -e " 3. Tìm từ khóa 'com.cloudflare.warp' và copy toàn bộ URL liên kết."
        echo -e "    (Ví dụ dạng: com.cloudflare.warp://mktsoftware.cloudflareaccess.com/auth?token=xxxxx)\n"
        
        read -p "👉 Hãy dán URL Token lấy được vào đây: " token_url
        if [[ "$token_url" =~ ^com.cloudflare.warp ]]; then
            echo -e "${INFO} Đang nạp Token đăng ký thủ công vào hệ thống..."
            if warp-cli registration token "$token_url"; then
                echo -e "${TICK} Đã liên kết tài khoản Zero Trust thành công."
            else
                echo -e "${CROSS} Nạp token thất bại. Vui lòng tạo liên kết mới và kiểm tra lại."
            fi
        else
            echo -e "${CROSS} Định dạng URL Token không hợp lệ. Bỏ qua nạp token."
        fi
    fi
fi

# Hiển thị lại kết quả đăng ký
echo -e "\n${INFO} Trạng thái đăng ký hiện tại:"
warp-cli registration show || true

# ==============================================================================
# BƯỚC 3: BẬT KẾT NỐI WARP AN TOÀN (FAILSAFE CONNECT)
# ==============================================================================
echo -e "\n${BOLD}${WHITE}==> Bước 3: Bật kết nối Cloudflare WARP (Chế độ Failsafe)${NC}"

# Tạo Failsafe disconnect đề phòng tự khóa SSH ngoài server
echo -e "${INFO} Đang khởi tạo luồng tự động ngắt kết nối an toàn phòng ngừa (Failsafe 120s)..."
nohup sh -c 'sleep 120; warp-cli disconnect' >/tmp/warp-failsafe.log 2>&1 &
FAILSAFE_PID=$!
echo $FAILSAFE_PID > /tmp/warp-failsafe.pid

echo -e "${INFO} Đang thực hiện lệnh kết nối WARP..."
warp-cli connect
sleep 6

warp_status=$(warp-cli status 2>/dev/null | grep -i "status" || echo "Status update: Unknown")
echo -e "${INFO} Trạng thái kết nối WARP: ${BOLD}${warp_status}${NC}"

echo -e "\n${WARN} KHẨN CẤP: Nếu bạn không bị mất kết nối SSH và vẫn đang tương tác được bình thường:"
read -p "👉 Vui lòng nhấn [Enter] để xác nhận kết nối an toàn và HỦY chế độ Failsafe ngắt kết nối tự động: " confirm_ssh

if [ -f /tmp/warp-failsafe.pid ]; then
    kill $(cat /tmp/warp-failsafe.pid) 2>/dev/null || true
    rm -f /tmp/warp-failsafe.pid
    echo -e "${TICK} Đã xác nhận SSH an toàn. Đã hủy tiến trình tự động ngắt kết nối."
fi

# ==============================================================================
# BƯỚC 4: THỬ NGHIỆM ĐỊNH TUYẾN MẠNG ĐẾN GITLAB LOCAL
# ==============================================================================
echo -e "\n${BOLD}${WHITE}==> Bước 4: Thử nghiệm mạng và định tuyến tới GitLab Local (192.168.1.138)${NC}"

echo "=== Kiểm tra định tuyến Route ==="
ip route get 192.168.1.138 || true
echo ""

echo "=== Kiểm tra cổng Web GitLab (Cổng 80) ==="
if curl -I --connect-timeout 5 http://192.168.1.138 &>/dev/null; then
    echo -e "${TICK} Kết nối thành công đến Web GitLab (Cổng 80)."
else
    echo -e "${CROSS} Không thể kết nối tới Web GitLab (Cổng 80). Cảnh báo Split Tunnel hoặc Device Policy."
fi
echo ""

echo "=== Kiểm tra cổng SSH GitLab (Cổng 2222) ==="
if nc -vz -w 5 192.168.1.138 2222 &>/dev/null; then
    echo -e "${TICK} Kết nối thành công tới cổng SSH GitLab (Cổng 2222)."
else
    echo -e "${CROSS} Không thể kết nối tới SSH GitLab (Cổng 2222). Hãy kiểm tra Split Tunnel."
fi

# ==============================================================================
# BƯỚC 5: TẠO SSH KEY VÀ CONFIG RIÊNG BIỆT CHO GITLAB LOCAL
# ==============================================================================
echo -e "\n${BOLD}${WHITE}==> Bước 5: Cấu hình SSH Keys riêng biệt cho GitLab Local${NC}"

setup_ssh_for_user() {
    local username=$1
    local home_dir=$2
    local key_path="${home_dir}/.ssh/id_ed25519_gitlab_local"
    local config_path="${home_dir}/.ssh/config"
    
    echo -e "${INFO} Đang cấu hình SSH cho user: ${BOLD}${username}${NC}..."
    
    # Tạo thư mục .ssh
    mkdir -p "${home_dir}/.ssh"
    
    # Tạo SSH Key nếu chưa tồn tại
    if [ ! -f "$key_path" ]; then
        ssh-keygen -t ed25519 -C "${username}-gitlab-local" -f "$key_path" -N "" >/dev/null
        echo -e "  ${TICK} Đã sinh khóa SSH mới tại: ${key_path}"
    else
        echo -e "  ${WARN} Khóa SSH đã tồn tại sẵn tại: ${key_path}"
    fi
    
    # Cấu hình SSH Config
    if [ -f "$config_path" ] && grep -q "Host gitlab-local" "$config_path"; then
        echo -e "  ${WARN} Cấu hình Host 'gitlab-local' đã tồn tại sẵn trong SSH config."
    else
        cat <<EOF >> "$config_path"

Host gitlab-local 192.168.1.138
  HostName 192.168.1.138
  User git
  Port 2222
  IdentityFile ${key_path}
  IdentitiesOnly yes
EOF
        echo -e "  ${TICK} Đã ghi cấu hình alias 'gitlab-local' vào SSH config."
    fi
    
    # Phân quyền chuẩn bảo mật hệ thống
    chmod 700 "${home_dir}/.ssh"
    chmod 600 "$config_path"
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"
    
    if [ "$username" != "root" ]; then
        chown -R "${username}:${username}" "${home_dir}/.ssh"
    fi
}

# 1. Cấu hình cho user root
setup_ssh_for_user "root" "/root"

# 2. Cấu hình cho user deployer (nếu có)
if getent passwd deployer &>/dev/null; then
    setup_ssh_for_user "deployer" "/home/deployer"
else
    echo -e "${WARN} Không phát hiện user 'deployer'. Vui lòng chạy thiết lập deployer sau."
fi

# ==============================================================================
# BƯỚC 6: XÁC THỰC VÀ KIỂM TRA SSH VÀO GITLAB
# ==============================================================================
echo -e "\n${BOLD}${WHITE}==> Bước 6: Đăng ký SSH Public Key lên GitLab UI và Kiểm tra xác thực${NC}"

echo -e "${BOLD}${YELLOW}------------------------------------------------------------------------${NC}"
echo -e "👉 BƯỚC CẦN LÀM: Sao chép khóa công khai (Public Key) dưới đây và dán vào"
echo -e "   tài khoản GitLab của bạn (Preferences -> SSH Keys -> Add New Key):\n"

if [ -f /home/deployer/.ssh/id_ed25519_gitlab_local.pub ]; then
    echo -e "${BOLD}${WHITE}[KHÓA CỦA USER DEPLOYER - DÙNG CHO DEPLOY TỰ ĐỘNG]:${NC}"
    cat /home/deployer/.ssh/id_ed25519_gitlab_local.pub
    echo ""
fi

echo -e "${BOLD}${WHITE}[KHÓA CỦA USER ROOT - DÙNG CHO CÁC TÁC VỤ QUẢN TRỊ]:${NC}"
cat /root/.ssh/id_ed25519_gitlab_local.pub
echo -e "${BOLD}${YELLOW}------------------------------------------------------------------------${NC}"

read -p "👉 Hãy đăng nhập và dán khóa trên lên GitLab. Nhấn [Enter] sau khi đã dán xong để TEST kết nối: " confirm_key

echo -e "\n${INFO} Kiểm tra kết nối SSH cho user root..."
ssh -T gitlab-local || true

if getent passwd deployer &>/dev/null; then
    echo -e "\n${INFO} Kiểm tra kết nối SSH cho user deployer..."
    sudo -u deployer ssh -T gitlab-local || true
fi

echo -e "\n${BOLD}${GREEN}========================================================================${NC}"
echo -e " 🎉 HOÀN THÀNH THIẾT LẬP KẾT NỐI CLOUDFLARE WARP & GITLAB LOCAL 🎉"
echo -e "${BOLD}${GREEN}========================================================================${NC}"
echo -e " 1. WARP Client    : ${GREEN}Đang hoạt động & Connected${NC}"
echo -e " 2. GitLab Local   : Định tuyến IP ${BOLD}192.168.1.138${NC} qua Tunnel"
echo -e " 3. SSH Alias      : Bạn có thể sử dụng ${BOLD}gitlab-local${NC} làm máy chủ để git clone"
echo -e "                     (Ví dụ: git clone gitlab-local:vitechgroup/repo.git)"
echo -e "========================================================================${NC}\n"
