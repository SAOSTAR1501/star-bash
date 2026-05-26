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

show_banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "========================================================================"
    echo "    🌟 STAR-BASH VPS ORCHESTRATOR & DEPLOYMENT HUB 🌟                 "
    echo "========================================================================"
    echo -e "${NC}"
    echo -e "${BOLD}${WHITE}Hệ điều hành :${NC} $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 || echo "Linux")"
    echo -e "${BOLD}${WHITE}Uptime       :${NC} $(uptime -p)"
    echo -e "${BOLD}${WHITE}Thư mục gốc  :${NC} ${SCRIPT_DIR}"
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
        echo -e " [0] 🚪 ${BOLD}Thoát chương trình${NC}"
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        read -p "Nhập lựa chọn của bạn [0-3]: " choice

        case "$choice" in
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
            0)
                echo -e "\n${BOLD}${GREEN}Cảm ơn bạn đã sử dụng Star-Bash Suite. Hẹn gặp lại!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${CROSS} Lựa chọn không hợp lệ. Vui lòng nhập từ 0 đến 3."
                ;;
        esac
        
        echo -e "\n${INFO} Nhấn Enter để tiếp tục quay lại Menu chính..."
        read -r temp
    done
}

main_menu "$@"
