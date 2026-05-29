#!/bin/bash
# ==============================================================================
# Script Name   : install.sh
# Description   : Premium, State-aware, Menu-based Interactive Installer & Configurator 
#                 for Star-Bash System Monitor Alert Suite. (State-Memory Optimized)
# Author        : Antigravity AI
# Version       : 3.2.0
# ==============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
BOLD='\033[1m'; CYAN='\033[0;36m'; NC='\033[0m'
OK="${GREEN}[✔]${NC}"; FAIL="${RED}[✘]${NC}"; WARN="${YELLOW}[⚠]${NC}"; INFO="${BLUE}[ℹ]${NC}"

# 1. Đảm bảo chạy với quyền root/sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Lỗi:${NC} Hãy chạy script này với quyền ${BOLD}root${NC} (sudo bash install.sh)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
GLOBAL_CONFIG_DIR="/etc/star-bash"
CONFIG_FILE="${GLOBAL_CONFIG_DIR}/monitor.env"
MONITOR_SCRIPT="${SCRIPT_DIR}/system_monitor.sh"

# Khởi tạo thư mục cấu hình toàn cục
mkdir -p "$GLOBAL_CONFIG_DIR"

# Nạp cấu hình mặc định ban đầu
ENABLE_TELEGRAM=false
ENABLE_LARK=false
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
LARK_WEBHOOK_URL=""
RAM_THRESHOLD_PERCENT=85
CPU_THRESHOLD_PERCENT=90
DISK_THRESHOLD_PERCENT=90
SCAN_SUSPICIOUS_PATHS=true
ENABLE_SSH_MONITOR=true

# Đọc cấu hình hiện tại từ file nếu tồn tại
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Yêu cầu cài đặt jq nếu chưa có
if ! command -v jq &>/dev/null; then
    echo -e "${INFO} Đang cài đặt thư viện 'jq' hỗ trợ gửi dữ liệu JSON..."
    apt-get update &>/dev/null && apt-get install -y jq &>/dev/null
fi

# Phân quyền thực thi
chmod +x "$MONITOR_SCRIPT"

# Hàm lưu toàn bộ biến cấu hình hiện tại xuống file an toàn (Ghi đè sạch sẽ)
save_config_to_file() {
    cat <<EOF > "$CONFIG_FILE"
ENABLE_TELEGRAM=$ENABLE_TELEGRAM
ENABLE_LARK=$ENABLE_LARK
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
LARK_WEBHOOK_URL="$LARK_WEBHOOK_URL"
RAM_THRESHOLD_PERCENT=$RAM_THRESHOLD_PERCENT
CPU_THRESHOLD_PERCENT=$CPU_THRESHOLD_PERCENT
DISK_THRESHOLD_PERCENT=$DISK_THRESHOLD_PERCENT
SCAN_SUSPICIOUS_PATHS=$SCAN_SUSPICIOUS_PATHS
ENABLE_SSH_MONITOR=$ENABLE_SSH_MONITOR
EOF
}

# Hàm che giấu Token nhạy cảm
mask_token() {
    local token="$1"
    if [ -z "$token" ] || [ "$token" = "your_telegram_bot_token_here" ] || [ "$token" = "your_telegram_chat_id_here" ] || [ "$token" = "https://open.larksuite.com/open-apis/bot/v2/hook/your_lark_webhook_uuid_here" ]; then
        echo "Chưa cấu hình"
    else
        local len=${#token}
        if [ "$len" -gt 15 ]; then
            echo "${token:0:5}...${token: -5}"
        else
            echo "********"
        fi
    fi
}

# Menu quản lý cấu hình thông minh
interactive_config_menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e "      ⚙️   ${BOLD}${WHITE}TRÌNH QUẢN LÝ & CẤU HÌNH BOT GIÁM SÁT VPS STAR-BASH${NC}   ⚙️"
        echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
        
        echo -e " ${BOLD}${WHITE}Trạng thái cấu hình hiện tại:${NC}"
        
        # Cấu hình Telegram
        if [ "$ENABLE_TELEGRAM" = "true" ]; then
            echo -e "  📬 [1] Telegram Alert                  : ${GREEN}${BOLD}[ BẬT ]${NC}"
        else
            echo -e "  📬 [1] Telegram Alert                  : ${RED}${BOLD}[ TẮT ]${NC}"
        fi
        echo -e "         - Bot Token & Chat ID           : [2] $([ -n "$TELEGRAM_BOT_TOKEN" ] && echo -e "${CYAN}Đã cấu hình (${NC}$(mask_token "$TELEGRAM_BOT_TOKEN")${CYAN})${NC}" || echo -e "${RED}Chưa cấu hình${NC}")"
        
        # Cấu hình Lark Suite
        if [ "$ENABLE_LARK" = "true" ]; then
            echo -e "  📬 [3] Lark Suite Bot Alert            : ${GREEN}${BOLD}[ BẬT ]${NC}"
        else
            echo -e "  📬 [3] Lark Suite Bot Alert            : ${RED}${BOLD}[ TẮT ]${NC}"
        fi
        echo -e "         - Lark Webhook URL              : [4] $([ -n "$LARK_WEBHOOK_URL" ] && echo -e "${CYAN}Đã cấu hình (${NC}$(mask_token "$LARK_WEBHOOK_URL")${CYAN})${NC}" || echo -e "${RED}Chưa cấu hình${NC}")"
        
        # Ngưỡng tài nguyên
        echo -e "\n  📊 Ngưỡng cảnh báo tài nguyên hiện tại:"
        echo -e "         - [5] Ngưỡng RAM                : ${YELLOW}${RAM_THRESHOLD_PERCENT}%${NC}"
        echo -e "         - [6] Ngưỡng CPU                : ${YELLOW}${CPU_THRESHOLD_PERCENT}%${NC}"
        echo -e "         - [7] Ngưỡng Ổ cứng             : ${YELLOW}${DISK_THRESHOLD_PERCENT}%${NC}"

        # An ninh bổ sung
        echo -e "\n  🛡️  Bảo mật & Quét an ninh:"
        echo -e "         - [8] Quét suspicious paths (Malware)   : $([ "$SCAN_SUSPICIOUS_PATHS" = "true" ] && echo -e "${GREEN}BẬT${NC}" || echo -e "${RED}TẮT${NC}")"
        echo -e "         - [9] Giám sát đăng nhập SSH mới        : $([ "$ENABLE_SSH_MONITOR" = "true" ] && echo -e "${GREEN}BẬT${NC}" || echo -e "${RED}TẮT${NC}")"
        
        echo -e "\n  [T] Chạy kiểm tra nóng & Gửi thông báo Test ngay"
        echo -e "  [0] Lưu & Thoát"
        echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
        
        read -r -p "👉 Nhập lựa chọn của bạn muốn điều chỉnh [0-9, T]: " choice
        case "$choice" in
            0)
                # Lưu cấu hình xuống file trước khi thoát
                save_config_to_file
                
                # Thiết lập Cronjob chạy tự động mỗi 30 phút (Đã dọn dẹp các cron cũ của file này)
                local CRON_JOB="*/30 * * * * bash ${MONITOR_SCRIPT} > /dev/null 2>&1"
                
                # Xóa toàn bộ cronjob cũ liên quan đến system_monitor.sh để tránh trùng lặp tần suất
                crontab -l 2>/dev/null | grep -v "${MONITOR_SCRIPT}" | crontab -
                
                # Thêm cronjob 30 phút mới
                (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
                
                echo -e "\n${OK} Lưu cấu hình thành công! Cronjob định kỳ 30 phút đã hoạt động."
                sleep 2
                break
                ;;
            1)
                if [ "$ENABLE_TELEGRAM" = "true" ]; then
                    ENABLE_TELEGRAM=false
                else
                    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ "$TELEGRAM_BOT_TOKEN" = "your_telegram_bot_token_here" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
                        echo -e "${WARN} Bạn chưa cấu hình Token Telegram. Hãy nhập cấu hình!"
                        read -r -p "👉 Nhập Telegram Bot Token: " t_token
                        TELEGRAM_BOT_TOKEN="$t_token"
                        read -r -p "👉 Nhập Telegram Chat ID: " t_chat
                        TELEGRAM_CHAT_ID="$t_chat"
                    fi
                    ENABLE_TELEGRAM=true
                fi
                save_config_to_file
                ;;
            2)
                read -r -p "👉 Nhập Telegram Bot Token mới: " t_token
                TELEGRAM_BOT_TOKEN="$t_token"
                read -r -p "👉 Nhập Telegram Chat ID mới: " t_chat
                TELEGRAM_CHAT_ID="$t_chat"
                ENABLE_TELEGRAM=true
                save_config_to_file
                ;;
            3)
                if [ "$ENABLE_LARK" = "true" ]; then
                    ENABLE_LARK=false
                else
                    if [ -z "$LARK_WEBHOOK_URL" ] || [ "$LARK_WEBHOOK_URL" = "https://open.larksuite.com/open-apis/bot/v2/hook/your_lark_webhook_uuid_here" ]; then
                        echo -e "${WARN} Bạn chưa cấu hình Webhook Lark. Hãy nhập cấu hình!"
                        read -r -p "👉 Nhập Lark Suite Webhook URL: " l_url
                        LARK_WEBHOOK_URL="$l_url"
                    fi
                    ENABLE_LARK=true
                fi
                save_config_to_file
                ;;
            4)
                read -r -p "👉 Nhập Lark Suite Webhook URL mới: " l_url
                LARK_WEBHOOK_URL="$l_url"
                ENABLE_LARK=true
                save_config_to_file
                ;;
            5)
                read -r -p "👉 Cài đặt ngưỡng cảnh báo RAM mới (%) [10-95]: " r_th
                if [[ "$r_th" =~ ^[0-9]+$ ]] && [ "$r_th" -ge 10 ] && [ "$r_th" -le 95 ]; then
                    RAM_THRESHOLD_PERCENT=$r_th
                    save_config_to_file
                fi
                ;;
            6)
                read -r -p "👉 Cài đặt ngưỡng cảnh báo CPU mới (%) [10-95]: " c_th
                if [[ "$c_th" =~ ^[0-9]+$ ]] && [ "$c_th" -ge 10 ] && [ "$c_th" -le 95 ]; then
                    CPU_THRESHOLD_PERCENT=$c_th
                    save_config_to_file
                fi
                ;;
            7)
                read -r -p "👉 Cài đặt ngưỡng cảnh báo Ổ cứng mới (%) [10-95]: " d_th
                if [[ "$d_th" =~ ^[0-9]+$ ]] && [ "$d_th" -ge 10 ] && [ "$d_th" -le 95 ]; then
                    DISK_THRESHOLD_PERCENT=$d_th
                    save_config_to_file
                fi
                ;;
            8)
                if [ "$SCAN_SUSPICIOUS_PATHS" = "true" ]; then
                    SCAN_SUSPICIOUS_PATHS=false
                else
                    SCAN_SUSPICIOUS_PATHS=true
                fi
                save_config_to_file
                ;;
            9)
                if [ "$ENABLE_SSH_MONITOR" = "true" ]; then
                    ENABLE_SSH_MONITOR=false
                else
                    ENABLE_SSH_MONITOR=true
                fi
                save_config_to_file
                ;;
            [tT])
                # Lưu cấu hình xuống file tạm thời trước khi test để system_monitor.sh đọc được chính xác
                save_config_to_file
                echo -e "\n🔍 ${BOLD}Đang chạy thử nghiệm liên kết và Gửi thông báo Test...${NC}"
                echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                bash "$MONITOR_SCRIPT" --test
                echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo -e "\n${OK} Đã chạy xong kịch bản Test."
                echo -e "💡 Mẹo: Xem phản hồi API (Response) ở trên để kiểm tra Token / Webhook có chuẩn hay không."
                read -r -p "👉 Nhấn Enter để tiếp tục..." _
                ;;
            *)
                echo -e "${FAIL} Lựa chọn không hợp lệ."
                sleep 1
                ;;
        esac
    done
}

# Khởi chạy menu quản trị
interactive_config_menu
