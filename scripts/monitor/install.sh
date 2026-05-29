#!/bin/bash
# ==============================================================================
# Script Name   : install.sh
# Description   : Premium, State-aware, Menu-based Interactive Installer & Configurator 
#                 for Star-Bash System Monitor Alert Suite.
# Author        : Antigravity AI
# Version       : 2.0.0
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

# Nếu file chưa tồn tại, copy từ mẫu example
if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "${SCRIPT_DIR}/config.env.example" ]; then
        cp "${SCRIPT_DIR}/config.env.example" "$CONFIG_FILE"
    else
        # Tự sinh cấu hình mặc định nếu thiếu file mẫu
        cat <<EOF > "$CONFIG_FILE"
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
EOF
    fi
fi

# Yêu cầu cài đặt jq nếu chưa có
if ! command -v jq &>/dev/null; then
    echo -e "${INFO} Đang cài đặt thư viện 'jq' hỗ trợ gửi dữ liệu JSON..."
    apt-get update &>/dev/null && apt-get install -y jq &>/dev/null
fi

# Phân quyền thực thi
chmod +x "$MONITOR_SCRIPT"

# Hàm che giấu Token nhạy cảm
mask_token() {
    local token="$1"
    if [ -z "$token" ] || [ "$token" = "your_telegram_bot_token_here" ]; then
        echo "Chưa cấu hình"
    else
        local len=${#token}
        if [ "$len" -gt 10 ]; then
            echo "${token:0:4}...${token: -4}"
        else
            echo "********"
        fi
    fi
}

# Menu quản lý cấu hình thông minh
interactive_config_menu() {
    while true; do
        # Đọc trực tiếp cấu hình hiện tại để hiển thị Real-time
        source "$CONFIG_FILE"

        clear
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e "      ⚙️   ${BOLD}${WHITE}TRÌNH QUẢN LÝ & CẤU HÌNH BOT GIÁM SÁT VPS STAR-BASH${NC}   ⚙️"
        echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
        
        echo -e " ${BOLD}${WHITE}Trạng thái cấu hình hiện tại:${NC}"
        
        # Trạng thái Telegram
        if [ "$ENABLE_TELEGRAM" = "true" ]; then
            echo -e "  📬 [1] Telegram Alert : ${GREEN}${BOLD}[ BẬT ]${NC}"
        else
            echo -e "  📬 [1] Telegram Alert : ${RED}${BOLD}[ TẮT ]${NC}"
        fi
        echo -e "         - Bot Token    : $(mask_token "$TELEGRAM_BOT_TOKEN")"
        echo -e "         - Chat ID      : $(mask_token "$TELEGRAM_CHAT_ID")"
        
        # Trạng thái Lark Suite
        if [ "$ENABLE_LARK" = "true" ]; then
            echo -e "  📬 [2] Lark Suite Bot : ${GREEN}${BOLD}[ BẬT ]${NC}"
        else
            echo -e "  📬 [2] Lark Suite Bot : ${RED}${BOLD}[ TẮT ]${NC}"
        fi
        echo -e "         - Webhook URL  : $(mask_token "$LARK_WEBHOOK_URL")"
        
        # Ngưỡng tài nguyên
        echo -e "\n  📊 Ngưỡng cảnh báo tài nguyên hiện tại:"
        echo -e "         - [3] Ngưỡng RAM      : ${YELLOW}${RAM_THRESHOLD_PERCENT}%${NC}"
        echo -e "         - [4] Ngưỡng CPU      : ${YELLOW}${CPU_THRESHOLD_PERCENT}%${NC}"
        echo -e "         - [5] Ngưỡng Ổ cứng   : ${YELLOW}${DISK_THRESHOLD_PERCENT}%${NC}"

        # An ninh bổ sung
        echo -e "\n  🛡️  Bảo mật & Quét an ninh:"
        echo -e "         - [6] Quét suspicious paths (Malware/Miner) : $([ "$SCAN_SUSPICIOUS_PATHS" = "true" ] && echo -e "${GREEN}BẬT${NC}" || echo -e "${RED}TẮT${NC}")"
        echo -e "         - [7] Giám sát đăng nhập SSH mới            : $([ "$ENABLE_SSH_MONITOR" = "true" ] && echo -e "${GREEN}BẬT${NC}" || echo -e "${RED}TẮT${NC}")"
        
        echo -e "\n  [T] Chạy kiểm tra nóng & Gửi thông báo Test ngay lập tức"
        echo -e "  [0] Hoàn tất & Thoát"
        echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
        
        read -r -p "👉 Nhập lựa chọn của bạn muốn điều chỉnh [0-7, T]: " choice
        case "$choice" in
            0)
                # Thiết lập Cronjob chạy tự động mỗi 30 phút (Đã dọn dẹp các cron cũ của file này)
                local CRON_JOB="*/30 * * * * bash ${MONITOR_SCRIPT} > /dev/null 2>&1"
                
                # Xóa toàn bộ cronjob cũ liên quan đến system_monitor.sh để tránh trùng lặp tần suất
                crontab -l 2>/dev/null | grep -v "${MONITOR_SCRIPT}" | crontab -
                
                # Thêm cronjob 30 phút mới
                (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
                
                echo -e "\n${OK} Lưu cấu hình thành công! Cronjob định kỳ 30 phút đã hoạt động."
                sleep 2.5
                break
                ;;
            1)
                if [ "$ENABLE_TELEGRAM" = "true" ]; then
                    sed -i 's/ENABLE_TELEGRAM=.*/ENABLE_TELEGRAM=false/' "$CONFIG_FILE"
                else
                    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ "$TELEGRAM_BOT_TOKEN" = "your_telegram_bot_token_here" ]; then
                        echo -e "${WARN} Bạn chưa cấu hình Token Telegram. Vui lòng cập nhật Token trước!"
                        read -r -p "👉 Nhập Telegram Bot Token: " t_token
                        sed -i "s|TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=\"$t_token\"|" "$CONFIG_FILE"
                        read -r -p "👉 Nhập Telegram Chat ID: " t_chat
                        sed -i "s|TELEGRAM_CHAT_ID=.*|TELEGRAM_CHAT_ID=\"$t_chat\"|" "$CONFIG_FILE"
                    fi
                    sed -i 's/ENABLE_TELEGRAM=.*/ENABLE_TELEGRAM=true/' "$CONFIG_FILE"
                fi
                ;;
            2)
                read -r -p "👉 Nhập Telegram Bot Token mới: " t_token
                sed -i "s|TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=\"$t_token\"|" "$CONFIG_FILE"
                read -r -p "👉 Nhập Telegram Chat ID mới: " t_chat
                sed -i "s|TELEGRAM_CHAT_ID=.*|TELEGRAM_CHAT_ID=\"$t_chat\"|" "$CONFIG_FILE"
                sed -i 's/ENABLE_TELEGRAM=.*/ENABLE_TELEGRAM=true/' "$CONFIG_FILE"
                ;;
            3)
                if [ "$ENABLE_LARK" = "true" ]; then
                    sed -i 's/ENABLE_LARK=.*/ENABLE_LARK=false/' "$CONFIG_FILE"
                else
                    if [ -z "$LARK_WEBHOOK_URL" ] || [ "$LARK_WEBHOOK_URL" = "https://open.larksuite.com/open-apis/bot/v2/hook/your_lark_webhook_uuid_here" ]; then
                        echo -e "${WARN} Bạn chưa cấu hình Webhook Lark. Vui lòng cập nhật Webhook trước!"
                        read -r -p "👉 Nhập Lark Suite Webhook URL: " l_url
                        sed -i "s|LARK_WEBHOOK_URL=.*|LARK_WEBHOOK_URL=\"$l_url\"|" "$CONFIG_FILE"
                    fi
                    sed -i 's/ENABLE_LARK=.*/ENABLE_LARK=true/' "$CONFIG_FILE"
                fi
                ;;
            4)
                read -r -p "👉 Nhập Lark Suite Webhook URL mới: " l_url
                sed -i "s|LARK_WEBHOOK_URL=.*|LARK_WEBHOOK_URL=\"$l_url\"|" "$CONFIG_FILE"
                sed -i 's/ENABLE_LARK=.*/ENABLE_LARK=true/' "$CONFIG_FILE"
                ;;
            5)
                read -r -p "👉 Cài đặt ngưỡng cảnh báo RAM mới (%) [10-95]: " r_th
                if [[ "$r_th" =~ ^[0-9]+$ ]] && [ "$r_th" -ge 10 ] && [ "$r_th" -le 95 ]; then
                    sed -i "s/RAM_THRESHOLD_PERCENT=.*/RAM_THRESHOLD_PERCENT=$r_th/" "$CONFIG_FILE"
                fi
                ;;
            6)
                read -r -p "👉 Cài đặt ngưỡng cảnh báo CPU mới (%) [10-95]: " c_th
                if [[ "$c_th" =~ ^[0-9]+$ ]] && [ "$c_th" -ge 10 ] && [ "$c_th" -le 95 ]; then
                    sed -i "s/CPU_THRESHOLD_PERCENT=.*/CPU_THRESHOLD_PERCENT=$c_th/" "$CONFIG_FILE"
                fi
                ;;
            7)
                read -r -p "👉 Cài đặt ngưỡng cảnh báo Ổ cứng mới (%) [10-95]: " d_th
                if [[ "$d_th" =~ ^[0-9]+$ ]] && [ "$d_th" -ge 10 ] && [ "$d_th" -le 95 ]; then
                    sed -i "s/DISK_THRESHOLD_PERCENT=.*/DISK_THRESHOLD_PERCENT=$d_th/" "$CONFIG_FILE"
                fi
                ;;
            [sS])
                if [ "$SCAN_SUSPICIOUS_PATHS" = "true" ]; then
                    sed -i 's/SCAN_SUSPICIOUS_PATHS=.*/SCAN_SUSPICIOUS_PATHS=false/' "$CONFIG_FILE"
                else
                    sed -i 's/SCAN_SUSPICIOUS_PATHS=.*/SCAN_SUSPICIOUS_PATHS=true/' "$CONFIG_FILE"
                fi
                ;;
            [sS][sS][hH])
                if [ "$ENABLE_SSH_MONITOR" = "true" ]; then
                    sed -i 's/ENABLE_SSH_MONITOR=.*/ENABLE_SSH_MONITOR=false/' "$CONFIG_FILE"
                else
                    sed -i 's/ENABLE_SSH_MONITOR=.*/ENABLE_SSH_MONITOR=true/' "$CONFIG_FILE"
                fi
                ;;
            [tT])
                echo -e "\n🔍 ${BOLD}Đang chạy quét nóng kiểm tra & Gửi Alert test...${NC}"
                # Ép buộc gửi thông báo test bằng cách hạ ngưỡng tạm thời trong phiên chạy này
                RAM_THRESHOLD_PERCENT=10 CPU_THRESHOLD_PERCENT=10 bash "$MONITOR_SCRIPT"
                echo -e "${OK} Đã thực thi xong kịch bản test. Hãy kiểm tra điện thoại/tin nhắn của bạn!"
                read -r -p "👉 Nhấn Enter để tiếp tục..." _
                ;;
            *)
                # Cho phép đổi bật/tắt các mục phụ qua chữ cái
                if [ "$choice" = "6" ] || [ "$choice" = "6" ]; then
                    if [ "$SCAN_SUSPICIOUS_PATHS" = "true" ]; then
                        sed -i 's/SCAN_SUSPICIOUS_PATHS=.*/SCAN_SUSPICIOUS_PATHS=false/' "$CONFIG_FILE"
                    else
                        sed -i 's/SCAN_SUSPICIOUS_PATHS=.*/SCAN_SUSPICIOUS_PATHS=true/' "$CONFIG_FILE"
                    fi
                elif [ "$choice" = "7" ] || [ "$choice" = "7" ]; then
                    if [ "$ENABLE_SSH_MONITOR" = "true" ]; then
                        sed -i 's/ENABLE_SSH_MONITOR=.*/ENABLE_SSH_MONITOR=false/' "$CONFIG_FILE"
                    else
                        sed -i 's/ENABLE_SSH_MONITOR=.*/ENABLE_SSH_MONITOR=true/' "$CONFIG_FILE"
                    fi
                else
                    echo -e "${FAIL} Lựa chọn không hợp lệ."
                    sleep 1
                fi
                ;;
        esac
    done
}

# Khởi động trình menu
interactive_config_menu
