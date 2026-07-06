#!/bin/bash
# ==============================================================================
# Script Name   : v3_setup.sh
# Description   : DevOps Suite v3 — New Server Quick-Setup & Hardening
# Author        : Antigravity AI
# Version       : 3.0.0
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/../../run-util.sh" 2>/dev/null || true

# Redefine fallback styles if run-util.sh is not loaded
RED=${RED:-$'\033[0;31m'}; GREEN=${GREEN:-$'\033[0;32m'}; YELLOW=${YELLOW:-$'\033[1;33m'}
BLUE=${BLUE:-$'\033[0;34m'}; CYAN=${CYAN:-$'\033[0;36m'}; BOLD=${BOLD:-$'\033[1m'}; NC=${NC:-$'\033[0m'}
OK=${OK:-"${GREEN}[✔]${NC}"}; FAIL=${FAIL:-"${RED}[✘]${NC}"}; WARN=${WARN:-"${YELLOW}[⚠]${NC}"}; INFO=${INFO:-"${BLUE}[ℹ]${NC}"}

install_docker() {
    clear
    echo -e "${BOLD}${CYAN}========================================================================${NC}"
    echo -e " 🐳  ${BOLD}${WHITE}CÀI ĐẶT DOCKER ENGINE & DOCKER COMPOSE PLUGIN${NC} 🐳"
    echo -e "${BOLD}${CYAN}========================================================================${NC}\n"

    echo -e "${INFO} Đang dọn dẹp các phiên bản Docker cũ nếu có..."
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        apt-get remove -y $pkg 2>/dev/null || true
    done

    echo -e "${INFO} Cập nhật danh sách gói và cài đặt dependencies..."
    apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release

    echo -e "${INFO} Thêm Docker GPG Key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo -e "${INFO} Cấu hình Docker Apt Repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo -e "${INFO} Tiến hành cài đặt Docker CE & Docker Compose..."
    apt-get update
    if apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        systemctl enable --now docker
        echo -e "${OK} Cài đặt Docker thành công!"
    else
        echo -e "${FAIL} Cài đặt Docker thất bại."
        read -r -p "👉 Nhấn Enter để tiếp tục..." _
        return 1
    fi

    echo -e "\n${INFO} Cấu hình Insecure Registry (192.168.1.138:5050) & Giới hạn log size..."
    mkdir -p /etc/docker
    cat <<EOF > /etc/docker/daemon.json
{
  "insecure-registries": ["192.168.1.138:5050"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

    echo -e "${INFO} Khởi động lại dịch vụ Docker Daemon..."
    systemctl restart docker
    echo -e "${OK} Thiết lập Docker Daemon hoàn tất!"
    read -r -p "👉 Nhấn Enter để tiếp tục..." _
}

setup_warp() {
    clear
    echo -e "${BOLD}${CYAN}========================================================================${NC}"
    echo -e " 🌀  ${BOLD}${WHITE}CÀI ĐẶT & KẾT NỐI CLOUDFLARE WARP ZERO TRUST${NC} 🌀"
    echo -e "${BOLD}${CYAN}========================================================================${NC}\n"

    echo -e "${INFO} Cài đặt GPG Key và Repository cho Cloudflare Warp..."
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

    echo -e "${INFO} Cài đặt Cloudflare WARP Client..."
    apt-get update && apt-get install -y cloudflare-warp
    systemctl enable --now warp-svc

    echo -e "\n${INFO} Bắt đầu đăng ký tài khoản Zero Trust Team..."
    warp-cli registration new mktsoftware

    echo -e "\n${WARN} Vui lòng truy cập đường link xác thực trên trình duyệt."
    echo -e "Sau khi xác thực thành công, copy link dạng ${BOLD}com.cloudflare.warp://...${NC}"
    read -p "👉 Dán liên kết xác thực vào đây: " warp_token
    warp_token=$(echo "$warp_token" | tr -d '[:space:]')

    if [ -n "$warp_token" ]; then
        if warp-cli registration token "$warp_token"; then
            echo -e "${OK} Đăng ký Zero Trust Team thành công!"
            
            # Setup Failsafe 120s để tránh bị lockout SSH nếu rớt mạng
            echo -e "${INFO} Thiết lập Failsafe tự động ngắt kết nối WARP sau 120s phòng ngừa rớt SSH..."
            nohup sh -c 'sleep 120; warp-cli disconnect' >/tmp/warp-failsafe.log 2>&1 & echo $! >/tmp/warp-failsafe.pid
            
            echo -e "${INFO} Đang kết nối Warp..."
            warp-cli connect
            sleep 8
            
            if warp-cli status | grep -qi "Connected"; then
                echo -e "${OK} ${GREEN}KẾT NỐI WARP ZERO TRUST THÀNH CÔNG!${NC}"
                # Hủy failsafe
                kill $(cat /tmp/warp-failsafe.pid) 2>/dev/null || true
                rm -f /tmp/warp-failsafe.pid
            else
                echo -e "${FAIL} Kết nối thất bại. Đang ngắt kết nối..."
                warp-cli disconnect
            fi
        else
            echo -e "${FAIL} Đăng ký token xác thực thất bại."
        fi
    else
        echo -e "${FAIL} Không có token nào được dán."
    fi
    read -r -p "👉 Nhấn Enter để tiếp tục..." _
}

install_runner() {
    clear
    echo -e "${BOLD}${CYAN}========================================================================${NC}"
    echo -e " 🦊  ${BOLD}${WHITE}CÀI ĐẶT & ĐĂNG KÝ GITLAB RUNNER CHUYÊN BIỆT${NC} 🦊"
    echo -e "${BOLD}${CYAN}========================================================================${NC}\n"

    echo -e "${INFO} Đang tải gói cài đặt .deb chính thức của GitLab Runner..."
    curl -LJO "https://gitlab-runner-downloads.s3.amazonaws.com/latest/deb/gitlab-runner_amd64.deb"

    echo -e "${INFO} Tiến hành cài đặt gitlab-runner..."
    dpkg -i gitlab-runner_amd64.deb
    rm -f gitlab-runner_amd64.deb
    systemctl enable --now gitlab-runner

    echo -e "\n${INFO} CẤP QUYỀN: Thêm user gitlab-runner vào nhóm docker..."
    usermod -aG docker gitlab-runner
    systemctl restart gitlab-runner
    echo -e "${OK} Đã cấu hình quyền docker cho gitlab-runner thành công!"

    echo -e "\n${INFO} Bắt đầu quy trình Đăng ký Runner với GitLab Server..."
    read -p "👉 Nhập GitLab Registration/Runner Token: " gitlab_token
    gitlab_token=$(echo "$gitlab_token" | tr -d '[:space:]')

    if [ -z "$gitlab_token" ]; then
        echo -e "${FAIL} Token không được bỏ trống."
        read -r -p "👉 Nhấn Enter để quay lại..." _
        return 1
    fi

    read -p "👉 Nhập Tags cho Runner (Ví dụ: deploy-vps-main hoặc deploy-vps-vi-ai): " runner_tags
    runner_tags=${runner_tags:-"deploy-vps-main"}

    default_desc="Secure Shell Runner on $(hostname)"
    read -p "👉 Nhập mô tả cho Runner (Mặc định: '$default_desc'): " runner_desc
    runner_desc=${runner_desc:-"$default_desc"}

    if gitlab-runner register \
        --non-interactive \
        --config "/etc/gitlab-runner/config.toml" \
        --url "http://192.168.1.138" \
        --registration-token "$gitlab_token" \
        --executor "shell" \
        --shell "bash" \
        --description "$runner_desc" \
        --tag-list "$runner_tags"; then
        
        # Cấu hình concurrent = 1 trong config.toml
        sed -i 's/^concurrent =.*/concurrent = 1/' /etc/gitlab-runner/config.toml
        
        systemctl restart gitlab-runner
        echo -e "\n${OK} ${GREEN}ĐĂNG KÝ GITLAB RUNNER THÀNH CÔNG!${NC}"
    else
        echo -e "\n${FAIL} Đăng ký Runner thất bại. Vui lòng kiểm tra lại token và kết nối mạng."
    fi
    read -r -p "👉 Nhấn Enter để tiếp tục..." _
}

setup_project() {
    clear
    echo -e "${BOLD}${CYAN}========================================================================${NC}"
    echo -e " 📁  ${BOLD}${WHITE}KHỞI TẠO THƯ MỤC DỰ ÁN & CẤP QUYỀN GIỚI HẠN (DOMAIN)${NC} 📁"
    echo -e "${BOLD}${CYAN}========================================================================${NC}\n"

    local domain=""
    while [ -z "$domain" ]; do
        read -p "👉 Nhập tên miền (Domain) dự án (Ví dụ: vilearn.vitechgroup.vn): " domain
        domain=$(echo "$domain" | tr -d '[:space:]')
        if [ -z "$domain" ]; then
            echo -e "${FAIL} Tên miền không được để trống."
        fi
    done

    local deploy_dir="/home/$domain"
    echo -e "\n${INFO} Tạo thư mục triển khai..."
    mkdir -p "$deploy_dir"

    echo -e "${INFO} Tiến hành phân quyền thư mục cho user 'gitlab-runner'..."
    if id "gitlab-runner" &>/dev/null; then
        chown -R gitlab-runner:gitlab-runner "$deploy_dir"
        chmod -R 775 "$deploy_dir"
        
        # Thêm thư mục an toàn vào Git cấu hình cho gitlab-runner
        sudo -u gitlab-runner git config --global --add safe.directory "$deploy_dir" 2>/dev/null || true
        sudo -u gitlab-runner git config --global --add safe.directory "$deploy_dir/docker" 2>/dev/null || true
        
        echo -e "\n${OK} ${GREEN}KHỞI TẠO THƯ MỤC THÀNH CÔNG!${NC}"
        echo -e " 🔹 Đường dẫn: ${BOLD}$deploy_dir${NC}"
        echo -e " 🔹 Quyền sở hữu: ${BOLD}gitlab-runner:gitlab-runner${NC}"
        echo -e " 🔹 Chế độ phân quyền: ${BOLD}775 (Đọc/Ghi/Thực thi)${NC}"
    else
        echo -e "${FAIL} Lỗi: Không tìm thấy user 'gitlab-runner' trên hệ thống. Vui lòng chạy mục [3] trước."
    fi
    read -r -p "\n👉 Nhấn Enter để tiếp tục..." _
}

setup_swap() {
    clear
    echo -e "${BOLD}${CYAN}========================================================================${NC}"
    echo -e " 💾  ${BOLD}${WHITE}CẤU HÌNH SWAP MEMORY (PHÒNG NGỪA OOM CRASH)${NC} 💾"
    echo -e "${BOLD}${CYAN}========================================================================${NC}\n"

    # Kiểm tra xem swapfile đã tồn tại chưa
    if [ -f /swapfile ]; then
        echo -e "${WARN} Tệp tin /swapfile đã tồn tại trên VPS."
        read -p "👉 Bạn có muốn xoá swapfile cũ và tạo lại mới? (y/N): " swap_confirm
        if [[ ! "$swap_confirm" =~ ^[yY] ]]; then
            echo -e "${INFO} Đã huỷ thao tác cấu hình swap."
            read -r -p "👉 Nhấn Enter để tiếp tục..." _
            return 0
        fi
        echo -e "${INFO} Đang tắt swap cũ..."
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
    fi

    local swap_gb=""
    while true; do
        read -p "👉 Nhập dung lượng Swap muốn tạo (Đơn vị: GB, Mặc định: 2): " swap_gb
        swap_gb=${swap_gb:-"2"}
        if [[ "$swap_gb" =~ ^[0-9]+$ ]] && [ "$swap_gb" -gt 0 ]; then
            break
        else
            echo -e "${FAIL} Dung lượng Swap phải là một số nguyên dương."
        fi
    done

    echo -e "\n${INFO} Đang khởi tạo tệp tin swap dung lượng ${swap_gb}GB tại /swapfile..."
    if ! fallocate -l "${swap_gb}G" /swapfile 2>/dev/null; then
        echo -e "${INFO} fallocate không được hỗ trợ trên phân vùng này, đang tạo bằng dd..."
        dd if=/dev/zero of=/swapfile bs=1M count=$((swap_gb * 1024)) status=progress
    fi

    echo -e "${INFO} Thiết lập quyền bảo mật cho file swap (chmod 600)..."
    chmod 600 /swapfile

    echo -e "${INFO} Định dạng tệp tin swap..."
    mkswap /swapfile

    echo -e "${INFO} Kích hoạt Swap..."
    if swapon /swapfile; then
        # Thêm vào /etc/fstab để tự động kích hoạt khi reboot
        if ! grep -q "/swapfile" /etc/fstab; then
            echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab >/dev/null
        fi
        echo -e "\n${OK} ${GREEN}KÍCH HOẠT SWAP MEMORY THÀNH CÔNG!${NC}"
        echo -e "$DASH"
        free -h
        echo -e "$DASH"
    else
        echo -e "\n${FAIL} Kích hoạt swap thất bại."
    fi
    read -r -p "👉 Nhấn Enter để tiếp tục..." _
}

# ─── MAIN CONTROL LOOP ────────────────────────────────────────────────────────
while true; do
    clear
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    print_border_line "        🌟 ${BOLD}${WHITE}DEVOPS SUITE V3 — NEW VPS QUICK-SETUP WORKFLOW${NC} 🌟"
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    print_border_line "  [1] Cài đặt Docker Engine & Docker Compose Plugin (daemon.json)"
    print_border_line "  [2] Cài đặt & Kết nối Cloudflare WARP Client (Zero Trust)"
    print_border_line "  [3] Cài đặt & Đăng ký GitLab Runner (Tự động cấp quyền Docker)"
    print_border_line "  [4] Khởi tạo thư mục và phân quyền dự án (Nhập tên miền)"
    print_border_line "  [5] Cấu hình Swap Memory (Phòng ngừa OOM Crash)"
    print_border_line "  [0] Quay lại Menu chính"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"

    read -r -p "👉 Chọn chức năng cài đặt nhanh [0-5]: " v3_choice
    v3_choice="${v3_choice// /}"

    case "$v3_choice" in
        0|"") break ;;
        1) install_docker ;;
        2) setup_warp ;;
        3) install_runner ;;
        4) setup_project ;;
        5) setup_swap ;;
        *)
            echo -e "${FAIL} Lựa chọn không hợp lệ."
            sleep 1
            ;;
    esac
done
