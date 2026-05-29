#!/bin/bash
# ==============================================================================
# Script Name   : install.sh
# Description   : Automated installer for System Monitor & Security Alert
# Author        : Antigravity AI
# Version       : 1.0.0
# ==============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
BOLD='\033[1m'; CYAN='\033[0;36m'; NC='\033[0m'
OK="${GREEN}[✔]${NC}"; WARN="${YELLOW}[⚠]${NC}"; INFO="${BLUE}[ℹ]${NC}"

echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "   🛠️  CÀI ĐẶT BOT GIÁM SÁT TÀI NGUYÊN & AN NINH VPS (TELEGRAM/LARK)  "
echo -e "${BOLD}${CYAN}========================================================================${NC}"

# 1. Đảm bảo chạy với quyền root/sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Lỗi:${NC} Hãy chạy script này với quyền ${BOLD}root${NC} (sudo bash install.sh)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
MONITOR_SCRIPT="${SCRIPT_DIR}/system_monitor.sh"

# 2. Khởi tạo file cấu hình config.env
if [ ! -f "$CONFIG_FILE" ]; then
    cp "${SCRIPT_DIR}/config.env.example" "$CONFIG_FILE"
    echo -e "${OK} Khởi tạo file cấu hình '${BOLD}config.env${NC}'."
else
    echo -e "${INFO} File cấu hình '${BOLD}config.env${NC}' đã tồn tại sẵn."
fi

# 3. Yêu cầu cài đặt jq nếu chưa có (Dùng để parse JSON gửi webhook)
if ! command -v jq &>/dev/null; then
    echo -e "${INFO} Đang cài đặt thư viện 'jq' hỗ trợ gửi dữ liệu JSON..."
    apt-get update &>/dev/null && apt-get install -y jq &>/dev/null
    echo -e "${OK} Cài đặt 'jq' thành công."
fi

# 4. Phân quyền thực thi
chmod +x "$MONITOR_SCRIPT"
echo -e "${OK} Cấp quyền thực thi cho file giám sát."

# 5. Hướng dẫn cấu hình nhanh
echo -e "\n⚙️  ${BOLD}Cấu hình thông tin gửi thông báo:${NC}"
read -p "❓ Bạn có muốn cấu hình Bot gửi thông báo ngay bây giờ không? (y/N): " run_setup
run_setup=${run_setup:-"n"}

if [[ "$run_setup" =~ ^[yY] ]]; then
    echo -e "\n  --- 1. Cấu hình Telegram ---"
    read -p "👉 Bật Telegram Alert? (y/N): " enable_tele
    if [[ "$enable_tele" =~ ^[yY] ]]; then
        sed -i 's/ENABLE_TELEGRAM=.*/ENABLE_TELEGRAM=true/' "$CONFIG_FILE"
        read -p "   - Nhập Telegram Bot Token: " tele_token
        sed -i "s|TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=\"$tele_token\"|" "$CONFIG_FILE"
        read -p "   - Nhập Telegram Chat ID: " tele_chatid
        sed -i "s|TELEGRAM_CHAT_ID=.*|TELEGRAM_CHAT_ID=\"$tele_chatid\"|" "$CONFIG_FILE"
    else
        sed -i 's/ENABLE_TELEGRAM=.*/ENABLE_TELEGRAM=false/' "$CONFIG_FILE"
    fi

    echo -e "\n  --- 2. Cấu hình Lark Suite Bot ---"
    read -p "👉 Bật Lark Suite Bot Alert? (y/N): " enable_lark
    if [[ "$enable_lark" =~ ^[yY] ]]; then
        sed -i 's/ENABLE_LARK=.*/ENABLE_LARK=true/' "$CONFIG_FILE"
        read -p "   - Nhập Lark Webhook URL: " lark_url
        sed -i "s|LARK_WEBHOOK_URL=.*|LARK_WEBHOOK_URL=\"$lark_url\"|" "$CONFIG_FILE"
    else
        sed -i 's/ENABLE_LARK=.*/ENABLE_LARK=false/' "$CONFIG_FILE"
    fi
fi

# 6. Thiết lập Cronjob chạy tự động mỗi 5 phút
echo -e "\n⏰ ${BOLD}Thiết lập chạy tự động (Cronjob):${NC}"
CRON_JOB="*/5 * * * * bash ${MONITOR_SCRIPT} > /dev/null 2>&1"

# Kiểm tra xem cronjob đã tồn tại chưa để tránh trùng lặp
if crontab -l 2>/dev/null | grep -Fq "${MONITOR_SCRIPT}"; then
    echo -e "${INFO} Cronjob giám sát đã được thiết lập sẵn từ trước."
else
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo -e "${OK} Đã thêm Cronjob chạy tự động giám sát mỗi 5 phút một lần."
fi

echo -e "\n${BOLD}${GREEN}========================================================================${NC}"
echo -e "       🎉 THIẾT LẬP HOÀN TẤT HỆ THỐNG GIÁM SÁT HỆ THỐNG VPS 🎉"
echo -e "========================================================================${NC}"
echo -e " 1. File chạy chính : ${BOLD}${MONITOR_SCRIPT}${NC}"
echo -e " 2. File cấu hình   : ${BOLD}${CONFIG_FILE}${NC}"
echo -e " 3. Tần suất quét   : ${GREEN}Mỗi 5 phút/lần (Tự động)${NC}"
echo -e ""
echo -e " 👉 Bạn có thể chạy thử kịch bản ngay bằng lệnh:"
echo -e "    ${BOLD}bash ${MONITOR_SCRIPT}${NC}"
echo -e "${BOLD}${GREEN}========================================================================${NC}\n"
