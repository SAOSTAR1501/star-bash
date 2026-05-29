#!/bin/bash
# ==============================================================================
# Script Name   : sys_monitor.sh
# Description   : Real-time VPS System Resource Monitor & Telegram Alert Tool
# Author        : Antigravity AI
# Version       : 1.0.0
# Compatibility : Ubuntu, Debian, CentOS
# Usage         : bash sys_monitor.sh [dashboard | check | config]
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

# Config File Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.sys_monitor.conf"

# Default limits if config file doesn't specify
CPU_LIMIT=90
RAM_LIMIT=90
DISK_LIMIT=90

# Load Config if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Print beautiful progress bar
draw_bar() {
    local pct=$1
    local width=20
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar=""
    
    # Choose color based on percentage
    local color=$GREEN
    if [ "$pct" -ge "$CPU_LIMIT" ]; then
        color=$RED
    elif [ "$pct" -ge 75 ]; then
        color=$YELLOW
    fi
    
    bar+="${color}"
    for ((i=0; i<filled; i++)); do bar+="█"; done
    bar+="${NC}"
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo -e "[$bar]"
}

# Fetch metrics
get_cpu_usage() {
    # Fast calculation from /proc/stat
    local cpu_now=($(head -n1 /proc/stat))
    local cpu_sum=$((cpu_now[1]+cpu_now[2]+cpu_now[3]+cpu_now[4]+cpu_now[5]+cpu_now[6]+cpu_now[7]+cpu_now[8]))
    local cpu_idle=${cpu_now[4]}
    
    sleep 0.5
    
    local cpu_next=($(head -n1 /proc/stat))
    local cpu_sum2=$((cpu_next[1]+cpu_next[2]+cpu_next[3]+cpu_next[4]+cpu_next[5]+cpu_next[6]+cpu_next[7]+cpu_next[8]))
    local cpu_idle2=${cpu_next[4]}
    
    local diff_sum=$((cpu_sum2 - cpu_sum))
    local diff_idle=$((cpu_idle2 - cpu_idle))
    
    if [ "$diff_sum" -eq 0 ]; then
        echo "0"
        return
    fi
    
    local diff_used=$((diff_sum - diff_idle))
    local usage=$((diff_used * 100 / diff_sum))
    echo "$usage"
}

get_network_speed() {
    local interface=$(ip route | grep default | awk '{print $5}' | head -n 1)
    [ -z "$interface" ] && interface="eth0"
    
    local rx1=$(cat /proc/net/dev | grep "$interface" | awk '{print $2}')
    local tx1=$(cat /proc/net/dev | grep "$interface" | awk '{print $10}')
    sleep 0.5
    local rx2=$(cat /proc/net/dev | grep "$interface" | awk '{print $2}')
    local tx2=$(cat /proc/net/dev | grep "$interface" | awk '{print $10}')
    
    # Calculate speed in KB/s
    local rx_speed=$(( (rx2 - rx1) * 2 / 1024 ))
    local tx_speed=$(( (tx2 - tx1) * 2 / 1024 ))
    
    echo "$rx_speed|$tx_speed|$interface"
}

# Send Telegram Alert
send_telegram() {
    local message="$1"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${message}" \
            -d "parse_mode=HTML" > /dev/null
        return $?
    fi
    return 1
}

# Config Telegram & Alert Parameters
configure_tool() {
    clear
    echo -e "${BOLD}${CYAN}========================================================================${NC}"
    echo -e "${BOLD}${WHITE}    🛠️  CẤU HÌNH CẢNH BÁO TÀI NGUYÊN VPS QUA TELEGRAM BOT  🛠️${NC}"
    echo -e "${BOLD}${CYAN}========================================================================${NC}"
    echo -e "Công cụ này cho phép tự động gửi thông báo về nhóm/kênh Telegram cá nhân"
    echo -e "khi tài nguyên VPS vượt quá ngưỡng cho phép (mặc định > 90%)."
    echo -e ""
    
    read -p "👉 Nhập Telegram Bot Token (Ấn Enter để bỏ qua): " input_token
    [ -n "$input_token" ] && TELEGRAM_BOT_TOKEN="$input_token"
    
    read -p "👉 Nhập Telegram Chat ID (Ấn Enter để bỏ qua): " input_chat
    [ -n "$input_chat" ] && TELEGRAM_CHAT_ID="$input_chat"
    
    read -p "👉 Ngưỡng cảnh báo CPU % (Ví dụ: 85, Ấn Enter giữ nguyên $CPU_LIMIT%): " input_cpu
    if [[ "$input_cpu" =~ ^[0-9]+$ ]]; then CPU_LIMIT="$input_cpu"; fi
    
    read -p "👉 Ngưỡng cảnh báo RAM % (Ví dụ: 85, Ấn Enter giữ nguyên $RAM_LIMIT%): " input_ram
    if [[ "$input_ram" =~ ^[0-9]+$ ]]; then RAM_LIMIT="$input_ram"; fi
    
    read -p "👉 Ngưỡng cảnh báo Disk % (Ví dụ: 85, Ấn Enter giữ nguyên $DISK_LIMIT%): " input_disk
    if [[ "$input_disk" =~ ^[0-9]+$ ]]; then DISK_LIMIT="$input_disk"; fi
    
    # Save to file config
    cat << EOF > "$CONFIG_FILE"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
CPU_LIMIT=${CPU_LIMIT}
RAM_LIMIT=${RAM_LIMIT}
DISK_LIMIT=${DISK_LIMIT}
EOF
    
    echo -e "\n${TICK} Cấu hình đã được lưu thành công tại: ${BOLD}${CONFIG_FILE}${NC}"
    
    # Test message
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        echo -e "${INFO} Đang gửi thử một tin nhắn test tới Telegram..."
        local hostname=$(hostname)
        local ip_address=$(curl -s https://ifconfig.me || echo "Unknown IP")
        local test_msg="🔔 <b>[STAR-BASH MONITOR]</b> Kênh cảnh báo VPS hoạt động tốt!%0A<b>VPS Host:</b> ${hostname}%0A<b>IP:</b> ${ip_address}%0A<b>Trạng thái:</b> Đã kết nối thành công."
        
        if send_telegram "$test_msg"; then
            echo -e "${TICK} ${GREEN}Gửi tin nhắn thử nghiệm thành công! Vui lòng kiểm tra ứng dụng Telegram.${NC}"
        else
            echo -e "${CROSS} ${RED}Gửi thất bại! Vui lòng kiểm tra lại Bot Token hoặc Chat ID.${NC}"
        fi
    fi
}

# Run Check Alert (For cron jobs)
check_resources_once() {
    local cpu=$(get_cpu_usage)
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    local mem_used=$(free -m | awk '/^Mem:/{print $3}')
    local ram=$(( mem_used * 100 / mem_total ))
    local disk=$(df -h / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    local hostname=$(hostname)
    local ip_address=$(curl -s https://ifconfig.me || echo "Unknown IP")
    
    local alert_triggered=false
    local alert_msg="⚠️ <b>[STAR-BASH VPS WARNING]</b>%0A<b>Host:</b> ${hostname} (${ip_address})%0A<b>Tài nguyên hệ thống quá tải:</b>%0A"
    
    if [ "$cpu" -ge "$CPU_LIMIT" ]; then
        alert_triggered=true
        alert_msg="${alert_msg}🔴 CPU Usage: <b>${cpu}%</b> (Vượt ngưỡng ${CPU_LIMIT}%)%0A"
    fi
    
    if [ "$ram" -ge "$RAM_LIMIT" ]; then
        alert_triggered=true
        alert_msg="${alert_msg}🔴 RAM Usage: <b>${ram}%</b> (${mem_used}MB/${mem_total}MB, Vượt ngưỡng ${RAM_LIMIT}%)%0A"
    fi
    
    if [ "$disk" -ge "$DISK_LIMIT" ]; then
        alert_triggered=true
        alert_msg="${alert_msg}🔴 Disk Usage: <b>${disk}%</b> (Vượt ngưỡng ${DISK_LIMIT}%)%0A"
    fi
    
    if [ "$alert_triggered" = true ]; then
        echo -e "${WARN} Phát hiện tài nguyên vượt ngưỡng cảnh báo! Đang gửi cảnh báo tới Telegram..."
        send_telegram "${alert_msg}"
    else
        echo -e "${TICK} Mọi chỉ số tài nguyên hoạt động bình thường."
    fi
}

# Realtime Dashboard
start_dashboard() {
    clear
    # Hide cursor
    tput civis
    
    # Restore cursor on exit
    trap 'tput cnorm; clear; exit 0' INT TERM
    
    while true; do
        # Fetch data
        local cpu=$(get_cpu_usage)
        
        # Memory info
        local mem_total=$(free -m | awk '/^Mem:/{print $2}')
        local mem_used=$(free -m | awk '/^Mem:/{print $3}')
        local mem_pct=$(( mem_used * 100 / mem_total ))
        
        # Disk Info
        local disk_pct=$(df -h / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
        local disk_used=$(df -h / | tail -1 | awk '{print $3}')
        local disk_total=$(df -h / | tail -1 | awk '{print $2}')
        
        # Load Average
        local load_avg=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^ //')
        
        # Network Speed
        local net_info=$(get_network_speed)
        local rx_speed=$(echo "$net_info" | cut -d'|' -f1)
        local tx_speed=$(echo "$net_info" | cut -d'|' -f2)
        local net_iface=$(echo "$net_info" | cut -d'|' -f3)
        
        # Move cursor to top left
        tput cup 0 0
        
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e "    📊  ${BOLD}BẢNG GIÁM SÁT TÀI NGUYÊN HỆ THỐNG VPS (REAL-TIME DASHBOARD)${NC}    "
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e "${BOLD}${WHITE}Hostname:${NC} $(hostname)   |   ${BOLD}${WHITE}IP public:${NC} $(curl -s -m 2 https://ifconfig.me || echo "N/A")"
        echo -e "${BOLD}${WHITE}Uptime  :${NC} $(uptime -p)   |   ${BOLD}${WHITE}Load Avg :${NC} $load_avg"
        echo -e "------------------------------------------------------------------------"
        
        # CPU
        local cpu_bar=$(draw_bar "$cpu")
        printf "%-12s %-25s %3d%%\n" "${BOLD}${WHITE}CPU Usage${NC}" "$cpu_bar" "$cpu"
        
        # RAM
        local ram_bar=$(draw_bar "$mem_pct")
        printf "%-12s %-25s %3d%%  (%dMB / %dMB)\n" "${BOLD}${WHITE}RAM Usage${NC}" "$ram_bar" "$mem_pct" "$mem_used" "$mem_total"
        
        # Disk
        local disk_bar=$(draw_bar "$disk_pct")
        printf "%-12s %-25s %3d%%  (%s / %s)\n" "${BOLD}${WHITE}Disk Usage${NC}" "$disk_bar" "$disk_pct" "$disk_used" "$disk_total"
        
        echo -e "------------------------------------------------------------------------"
        echo -e "${BOLD}${WHITE}Tốc độ mạng trên card [${net_iface}]:${NC}"
        printf "  📥 Down Speed : %6s KB/s\n" "$rx_speed"
        printf "  📤 Up Speed   : %6s KB/s\n" "$tx_speed"
        echo -e "------------------------------------------------------------------------"
        
        # Alert threshold configurations
        echo -e "${BOLD}${WHITE}Ngưỡng cảnh báo Telegram Bot:${NC}"
        if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
            echo -e "  - Trạng thái: ${GREEN}Đã kích hoạt${NC}"
            echo -e "  - Ngưỡng thiết lập: CPU >= ${CPU_LIMIT}%, RAM >= ${RAM_LIMIT}%, Disk >= ${DISK_LIMIT}%"
        else
            echo -e "  - Trạng thái: ${RED}Chưa cấu hình Telegram Bot${NC} (Chạy 'bash sys_monitor.sh config')"
        fi
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e "Nhấn ${BOLD}[Ctrl + C]${NC} để đóng bảng điều khiển."
        
        # Delay before next refresh (0.5s sleep inside network speed calculation is included, plus this sleep)
        sleep 1.5
    done
}

# Main Execution Flow
main() {
    local mode="${1:-dashboard}"
    
    case "$mode" in
        "dashboard")
            start_dashboard
            ;;
        "check")
            check_resources_once
            ;;
        "config")
            configure_tool
            ;;
        *)
            echo -e "${CROSS} Chế độ lựa chọn không hợp lệ!"
            echo -e "Sử dụng:"
            echo -e "  - ${BOLD}bash sys_monitor.sh dashboard${NC} : Khởi chạy Dashboard realtime (Mặc định)"
            echo -e "  - ${BOLD}bash sys_monitor.sh check${NC}     : Kiểm tra tài nguyên một lần và gửi cảnh báo"
            echo -e "  - ${BOLD}bash sys_monitor.sh config${NC}    : Cấu hình API Telegram & Ngưỡng tài nguyên"
            exit 1
            ;;
    esac
}

main "$@"
