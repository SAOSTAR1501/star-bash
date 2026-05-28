#!/bin/bash
# ==============================================================================
# Script Name   : run.sh
# Description   : Central Orchestrator & Dashboard for Star-Bash VPS Toolkit
# Author        : Antigravity AI
# Version       : 1.0.0
# Usage         : sudo bash run.sh
# ==============================================================================

# Define Colors for Terminal Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Status Icons
TICK="${GREEN}[✔]${NC}"
CROSS="${RED}[✘]${NC}"
WARN="${YELLOW}[⚠]${NC}"
INFO="${BLUE}[ℹ]${NC}"

# Resolve the absolute path of the directory containing this run.sh script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}Error:${NC} This orchestrator must be run as ${BOLD}root${NC} (or with sudo)."
    exit 1
fi

WARP_STATUS_LABEL=""
DEPLOYER_STATUS_LABEL=""
RUNNER_STATUS_LABEL=""

REC_WARP=""
REC_DEPLOYER=""
REC_RUNNER=""

check_system_status() {
    # 1. Check Cloudflare WARP & GitLab Connection
    if ! command -v warp-cli &>/dev/null; then
        WARP_STATUS_LABEL="${RED}[Chưa cài WARP]${NC}"
        REC_WARP="${RED}[ĐỀ XUẤT CHẠY]${NC}"
    else
        local reg_show
        reg_show=$(warp-cli registration show 2>/dev/null || echo "Missing registration")
        if ! echo "$reg_show" | grep -q "Account type: Team"; then
            WARP_STATUS_LABEL="${RED}[WARP Chưa Liên Kết Zero Trust]${NC}"
            REC_WARP="${RED}[ĐỀ XUẤT CHẠY]${NC}"
        else
            local status_show
            status_show=$(warp-cli status 2>/dev/null | grep -i "status" || echo "")
            if ! echo "$status_show" | grep -q "Connected"; then
                WARP_STATUS_LABEL="${YELLOW}[WARP Chưa Kết Nối]${NC}"
                REC_WARP="${RED}[ĐỀ XUẤT CHẠY]${NC}"
            else
                if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes -T gitlab-local 2>&1 | grep -q "Welcome to GitLab"; then
                    WARP_STATUS_LABEL="${GREEN}[Connected & SSH OK]${NC}"
                    REC_WARP=""
                else
                    if nc -vz -w 2 192.168.1.138 2222 &>/dev/null; then
                        WARP_STATUS_LABEL="${YELLOW}[Connected, SSH Key Chưa Add]${NC}"
                        REC_WARP="${YELLOW}[CẦN ADD SSH KEY]${NC}"
                    else
                        WARP_STATUS_LABEL="${RED}[WARP Kết Nối Lỗi Mạng]${NC}"
                        REC_WARP="${RED}[ĐỀ XUẤT CHẠY]${NC}"
                    fi
                fi
            fi
        fi
    fi

    # 2. Check deployer user
    if getent passwd deployer &>/dev/null; then
        DEPLOYER_STATUS_LABEL="${GREEN}[Đã có user deployer]${NC}"
        REC_DEPLOYER=""
    else
        DEPLOYER_STATUS_LABEL="${RED}[Chưa cấu hình user deployer]${NC}"
        REC_DEPLOYER="${RED}[ĐỀ XUẤT CHẠY]${NC}"
    fi

    # 3. Check gitlab-runner
    if command -v gitlab-runner &>/dev/null; then
        RUNNER_STATUS_LABEL="${GREEN}[Đã cài đặt GitLab Runner]${NC}"
        REC_RUNNER=""
    else
        RUNNER_STATUS_LABEL="${RED}[Chưa cài đặt GitLab Runner]${NC}"
        REC_RUNNER="${RED}[ĐỀ XUẤT CHẠY]${NC}"
    fi
}

show_banner() {
    clear
    check_system_status
    echo -e "${BOLD}${CYAN}"
    echo "========================================================================"
    echo "    🌟 STAR-BASH VPS ORCHESTRATOR & DEPLOYMENT HUB 🌟                 "
    echo "========================================================================"
    echo -e "${NC}"
    echo -e "${BOLD}${WHITE}Hệ điều hành  :${NC} $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 || echo "Linux")"
    echo -e "${BOLD}${WHITE}Uptime        :${NC} $(uptime -p)"
    echo -e "${BOLD}${WHITE}Thư mục gốc   :${NC} ${SCRIPT_DIR}"
    echo -e "${BOLD}${CYAN}------------------------------------------------------------------------${NC}"
    echo -e "${BOLD}${WHITE}[TRẠNG THÁI HỆ THỐNG]:${NC}"
    echo -e " 🦊 Kết nối WARP & GitLab : ${WARP_STATUS_LABEL}"
    echo -e " 🔑 VPS Deployer User     : ${DEPLOYER_STATUS_LABEL}"
    echo -e " ⚙️  GitLab Runner         : ${RUNNER_STATUS_LABEL}"
    echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
}

run_quick_setup_wrapper() {
    echo -e "\n${BOLD}${YELLOW}--- KHỞI CHẠY TRIỂN KHAI NHANH QUA THAM SỐ (QUICK SETUP) ---${NC}"
    echo -e "Lưu ý: Bạn cần điền đầy đủ 3 thông tin để khởi chạy tự động."
    echo -e ""
    read -p "👉 Nhập tên miền (Domain) (Ví dụ: vsoftware.vn): " q_domain
    if [ -z "$q_domain" ]; then
        echo -e "${CROSS} Tên miền không được để trống!"
        return 1
    fi

    read -p "👉 Nhập cổng ứng dụng (Port) (Ví dụ: 3008): " q_port
    if ! [[ "$q_port" =~ ^[0-9]+$ ]]; then
        echo -e "${CROSS} Cổng phải là số!"
        return 1
    fi

    read -p "👉 Tạo file ecosystem.config.js cho PM2 không? (yes-eco/no-eco): " q_eco
    if [ "$q_eco" != "yes-eco" ] && [ "$q_eco" != "no-eco" ]; then
        echo -e "${WARN} Lựa chọn sai. Mặc định chọn yes-eco."
        q_eco="yes-eco"
    fi

    # Trigger script
    bash "$SCRIPT_DIR/deploy-fe/quick_setup_site.sh" "$q_domain" "$q_port" "$q_eco"
}

run_setup_monitor_menu() {
    local choice
    while true; do
        clear
        echo -e "${BOLD}${CYAN}"
        echo "========================================================================"
        echo "    ⚙️  VPS SETUP & SYSTEM MONITORING SUITE ⚙️                         "
        echo "========================================================================"
        echo -e "${NC}"
        echo -e "${BOLD}${WHITE}Vui lòng chọn một chức năng:${NC}"
        echo -e " [1] 🚀 ${BOLD}VPS Tool Auto-Installer (setup.sh)${NC}"
        echo -e "      (Cài đặt nhanh: Node, NPM, Yarn, PM2, Docker, Nginx, Certbot)"
        echo -e ""
        echo -e " [2] 📊 ${BOLD}Real-time VPS Resource Dashboard (sys_monitor.sh)${NC}"
        echo -e "      (Theo dõi realtime CPU, RAM, Disk, Mạng)"
        echo -e ""
        echo -e " [3] ⚙️  ${BOLD}Configure Telegram Alert (sys_monitor.sh config)${NC}"
        echo -e "      (Cài đặt Token Bot & Chat ID cảnh báo quá tải)"
        echo -e ""
        echo -e " [4] 🔔 ${BOLD}Run Instant Resource Check & Test Alert${NC}"
        echo -e "      (Kiểm tra nhanh tài nguyên một lần & test gửi cảnh báo)"
        echo -e ""
        echo -e " [5] 🦊 ${BOLD}GitLab Runner Secure Installer (setup_gitlab_runner.sh)${NC}"
        echo -e "      (Cài đặt và thiết lập GitLab Runner Non-Root, Sandbox an toàn)"
        echo -e ""
        echo -e " [6] 🔑 ${BOLD}VPS Deployer & SSH Setup for Next.js (setup_vps_deployer.sh)${NC}"
        echo -e "      (Cài đặt deployer user & SSH Key bảo mật cao cho CI/CD)"
        echo -e ""
        echo -e " [7] 🦊 ${BOLD}Auto-generate GitLab CI/CD & PM2 (gen_gitlab_ci.sh)${NC}"
        echo -e "      (Tự động tạo tệp .gitlab-ci.yml và ecosystem.config.js riêng cho từng dự án)"
        echo -e ""
        echo -e " [0] 🔙 ${BOLD}Quay lại Menu chính${NC}"
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        read -p "Nhập lựa chọn của bạn [0-7]: " choice

        case "$choice" in
            1)
                if [ -f "$SCRIPT_DIR/setup/setup.sh" ]; then
                    bash "$SCRIPT_DIR/setup/setup.sh"
                else
                    echo -e "${CROSS} Không tìm thấy file script setup tại $SCRIPT_DIR/setup/setup.sh"
                fi
                ;;
            2)
                if [ -f "$SCRIPT_DIR/setup/sys_monitor.sh" ]; then
                    bash "$SCRIPT_DIR/setup/sys_monitor.sh" dashboard
                else
                    echo -e "${CROSS} Không tìm thấy file script monitor tại $SCRIPT_DIR/setup/sys_monitor.sh"
                fi
                ;;
            3)
                if [ -f "$SCRIPT_DIR/setup/sys_monitor.sh" ]; then
                    bash "$SCRIPT_DIR/setup/sys_monitor.sh" config
                else
                    echo -e "${CROSS} Không tìm thấy file script monitor tại $SCRIPT_DIR/setup/sys_monitor.sh"
                fi
                ;;
            4)
                if [ -f "$SCRIPT_DIR/setup/sys_monitor.sh" ]; then
                    bash "$SCRIPT_DIR/setup/sys_monitor.sh" check
                else
                    echo -e "${CROSS} Không tìm thấy file script monitor tại $SCRIPT_DIR/setup/sys_monitor.sh"
                fi
                ;;
            5)
                if [ -f "$SCRIPT_DIR/setup/setup_gitlab_runner.sh" ]; then
                    bash "$SCRIPT_DIR/setup/setup_gitlab_runner.sh"
                else
                    echo -e "${CROSS} Không tìm thấy file script gitlab-runner tại $SCRIPT_DIR/setup/setup_gitlab_runner.sh"
                fi
                ;;
            6)
                if [ -f "$SCRIPT_DIR/setup/setup_vps_deployer.sh" ]; then
                    bash "$SCRIPT_DIR/setup/setup_vps_deployer.sh"
                else
                    echo -e "${CROSS} Không tìm thấy file script vps-deployer tại $SCRIPT_DIR/setup/setup_vps_deployer.sh"
                fi
                ;;
            7)
                if [ -f "$SCRIPT_DIR/setup/gen_gitlab_ci.sh" ]; then
                    bash "$SCRIPT_DIR/setup/gen_gitlab_ci.sh"
                else
                    echo -e "${CROSS} Không tìm thấy file script gen-gitlab-ci tại $SCRIPT_DIR/setup/gen_gitlab_ci.sh"
                fi
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${CROSS} Lựa chọn không hợp lệ. Vui lòng nhập từ 0 đến 7."
                ;;
        esac
        echo -e "\n${INFO} Nhấn Enter để quay lại Menu công cụ..."
        read -r temp
    done
}

show_guidelines() {
    clear
    echo -e "${BOLD}${CYAN}========================================================================${NC}"
    echo -e "       📖 CẨM NANG HƯỚNG DẪN QUY TRÌNH CHUẨN - STAR-BASH SUITE 📖       "
    echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
    
    echo -e "${BOLD}${WHITE}1. QUY TRÌNH THIẾT LẬP SERVER MỚI (CHỈ LÀM 1 LẦN BAN ĐẦU)${NC}"
    echo -e "   Để setup một VPS mới có thể lấy code từ GitLab local qua WARP:"
    echo -e "   👉 ${BOLD}Bước A:${NC} Chạy mục ${BOLD}[8]${NC} để cài đặt Cloudflare WARP client."
    echo -e "          - Đăng nhập Zero Trust Team (mktsoftware) bằng link hiển thị."
    echo -e "          - Nạp token thủ công nếu chạy trên VPS headless."
    echo -e "          - Sao chép khóa SSH Public Key hiển thị trên màn hình và dán vào GitLab UI."
    echo -e "   👉 ${BOLD}Bước B:${NC} Chạy mục ${BOLD}[6]${NC} để tạo user ${BOLD}deployer${NC} hạn chế quyền."
    echo -e "          - User này dùng để chạy PM2 và nhận code an toàn."
    echo -e "   👉 ${BOLD}Bước C:${NC} Chạy mục ${BOLD}[7]${NC} để cài đặt & đăng ký ${BOLD}GitLab Runner${NC}."
    echo -e "          - Runner chạy chế độ bảo mật không root (user gitlab-runner)."
    echo -e ""
    
    echo -e "${BOLD}${WHITE}2. QUY TRÌNH KHỞI TẠO MỘT DỰ ÁN MỚI (FE/BE)${NC}"
    echo -e "   Khi muốn đưa một website mới chạy live trên VPS:"
    echo -e "   👉 ${BOLD}Bước 1:${NC} Chạy mục ${BOLD}[5]${NC} (FE/BE Orchestrator)."
    echo -e "          - Nhập tên miền (domain) làm tên thư mục (Ví dụ: newapp.vn)."
    echo -e "          - Nhập Git URL dạng: gitlab-local:vitechgroup/repo.git."
    echo -e "          - Nhập loại dự án FE/BE và cổng chạy (Ví dụ: 3005)."
    echo -e "          - Script tự động clone bằng user deployer, sinh config PM2 (cho FE),"
    echo -e "            tạo cấu hình Nginx Reverse Proxy, kích hoạt site và đăng ký SSL Certbot HTTPS."
    echo -e "   👉 ${BOLD}Bước 2:${NC} Đăng nhập vào user deployer: ${BOLD}su - deployer${NC}"
    echo -e "   👉 ${BOLD}Bước 3:${NC} Di chuyển vào thư mục dự án và chạy ứng dụng lần đầu bằng PM2:"
    echo -e "          - Đối với FE: ${BOLD}cd /home/newapp.vn && pm2 start ecosystem.config.js && pm2 save${NC}"
    echo -e "          - Đối với BE: ${BOLD}cd /home/newapp.vn && pm2 start app.js --name \"newapp.vn\" && pm2 save${NC}"
    echo -e ""
    
    echo -e "${BOLD}${WHITE}3. QUY TRÌNH ĐỂ THIẾT LẬP TỰ ĐỘNG HÓA CI/CD LÊN GITLAB${NC}"
    echo -e "   Để mỗi lần push code lên develop/main tự động build và deploy lên VPS:"
    echo -e "   👉 ${BOLD}Bước 1:${NC} Vào GitLab Repository -> Settings -> CI/CD -> Variables."
    echo -e "   👉 ${BOLD}Bước 2:${NC} Nạp 4 biến môi trường cốt lõi:"
    echo -e "          - ${BOLD}VPS_IP${NC} (Variable): IP của VPS này."
    echo -e "          - ${BOLD}SSH_PRIVATE_KEY${NC} (Variable): Khóa Private Key của user deployer."
    echo -e "          - ${BOLD}ENV_LOCAL_STAGING${NC} (File): Nội dung tệp .env.local môi trường develop."
    echo -e "          - ${BOLD}ENV_LOCAL_PRODUCTION${NC} (File): Nội dung tệp .env.local môi trường main."
    echo -e "   👉 ${BOLD}Bước 3:${NC} Commit file ${BOLD}.gitlab-ci.yml${NC} (đã sinh tự động ở mục [5]) lên repo."
    echo -e "          - Mỗi lần bạn push code, GitLab Runner sẽ tự động biên dịch và cập nhật lên VPS live."
    echo -e ""
    echo -e "${BOLD}${CYAN}========================================================================${NC}"
}

main_menu() {
    local choice
    while true; do
        show_banner
        echo -e "${BOLD}${WHITE}Vui lòng chọn một công cụ để khởi chạy:${NC}"
        echo -e " [1] 🛡️  ${BOLD}VPS Security Audit & Hardening Menu${NC}"
        echo -e "      (Quét lỗi cấu hình, phát hiện brute-force, malware & vá lỗi bảo mật)"
        echo -e ""
        echo -e " [2] 🚀 ${BOLD}Interactive FE Site Deployer (Step-by-Step)${NC}"
        echo -e "      (Hướng dẫn từng bước thiết lập Nginx, duyệt thư mục thông minh, PM2, SSL)"
        echo -e ""
        echo -e " [3] ⚡ ${BOLD}Quick FE Site Deployer (Automated)${NC}"
        echo -e "      (Nhập nhanh tham số để tự động sinh cấu hình Nginx, PM2, SSL)"
        echo -e ""
        echo -e " [4] ⚙️  ${BOLD}VPS Server Setup & Resource Monitor Suite${NC}"
        echo -e "      (Cài đặt công cụ VPS và giám sát tài nguyên VPS tự động)"
        echo -e ""
        echo -e " [5] 🚀 ${BOLD}Khởi tạo dự án mới hoàn toàn (FE/BE Orchestrator)${NC} ${GREEN}[KHUYÊN DÙNG]${NC}"
        echo -e "      (Tự động Clone, sinh PM2 Cluster, tạo Nginx site, cài SSL và sinh GitLab CI/CD)"
        echo -e ""
        echo -e " [6] 🔑 ${BOLD}Tạo user deployer và SSH Key bảo mật${NC} ${REC_DEPLOYER}"
        echo -e "      (Thiết lập deployer user hạn chế & cấu hình SSH Keys cho CI/CD)"
        echo -e ""
        echo -e " [7] 🦊 ${BOLD}Cài đặt GitLab Runner an toàn (Non-Root)${NC} ${REC_RUNNER}"
        echo -e "      (Tải, cài đặt và đăng ký GitLab Runner chạy chế độ bảo mật không root)"
        echo -e ""
        echo -e " [8] 🦊 ${BOLD}Cấu hình kết nối Cloudflare WARP & GitLab Local${NC} ${REC_WARP}"
        echo -e "      (Cài đặt WARP, liên kết Zero Trust Team, test định tuyến và cấu hình alias SSH)"
        echo -e ""
        echo -e " [00] 📖 ${BOLD}Hướng dẫn quy trình chuẩn (Guidelines)${NC}"
        echo -e ""
        echo -e " [0] 🚪 ${BOLD}Thoát chương trình${NC}"
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        read -p "Nhập lựa chọn của bạn [0-8 hoặc 00]: " choice

        case "$choice" in
            00)
                show_guidelines
                ;;
            1)
                if [ -f "$SCRIPT_DIR/security/security_check.sh" ]; then
                    bash "$SCRIPT_DIR/security/security_check.sh"
                else
                    echo -e "${CROSS} Không tìm thấy file script bảo mật tại $SCRIPT_DIR/security/security_check.sh"
                fi
                ;;
            2)
                if [ -f "$SCRIPT_DIR/deploy-fe/interactive_setup_site.sh" ]; then
                    bash "$SCRIPT_DIR/deploy-fe/interactive_setup_site.sh"
                else
                    echo -e "${CROSS} Không tìm thấy file script deploy tại $SCRIPT_DIR/deploy-fe/interactive_setup_site.sh"
                fi
                ;;
            3)
                if [ -f "$SCRIPT_DIR/deploy-fe/quick_setup_site.sh" ]; then
                    run_quick_setup_wrapper
                else
                    echo -e "${CROSS} Không tìm thấy file script deploy tại $SCRIPT_DIR/deploy-fe/quick_setup_site.sh"
                fi
                ;;
            4)
                run_setup_monitor_menu
                ;;
            5)
                if [ -f "$SCRIPT_DIR/setup/orchestrate_new_project.sh" ]; then
                    bash "$SCRIPT_DIR/setup/orchestrate_new_project.sh"
                else
                    echo -e "${CROSS} Không tìm thấy file script tại $SCRIPT_DIR/setup/orchestrate_new_project.sh"
                fi
                ;;
            6)
                if [ -f "$SCRIPT_DIR/setup/setup_vps_deployer.sh" ]; then
                    bash "$SCRIPT_DIR/setup/setup_vps_deployer.sh"
                else
                    echo -e "${CROSS} Không tìm thấy file script tại $SCRIPT_DIR/setup/setup_vps_deployer.sh"
                fi
                ;;
            7)
                if [ -f "$SCRIPT_DIR/setup/setup_gitlab_runner.sh" ]; then
                    bash "$SCRIPT_DIR/setup/setup_gitlab_runner.sh"
                else
                    echo -e "${CROSS} Không tìm thấy file script tại $SCRIPT_DIR/setup/setup_gitlab_runner.sh"
                fi
                ;;
            8)
                if [ -f "$SCRIPT_DIR/setup/setup_warp_gitlab.sh" ]; then
                    bash "$SCRIPT_DIR/setup/setup_warp_gitlab.sh"
                else
                    echo -e "${CROSS} Không tìm thấy file script tại $SCRIPT_DIR/setup/setup_warp_gitlab.sh"
                fi
                ;;
            0)
                echo -e "\n${BOLD}${GREEN}Cảm ơn bạn đã sử dụng Star-Bash Suite. Hẹn gặp lại!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${CROSS} Lựa chọn không hợp lệ. Vui lòng nhập từ 0 đến 8 hoặc 00."
                ;;
        esac
        
        echo -e "\n${INFO} Nhấn Enter để tiếp tục quay lại Menu chính..."
        read -r temp
    done
}

main_menu "$@"
