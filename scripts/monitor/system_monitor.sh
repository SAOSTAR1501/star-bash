#!/bin/bash
# ==============================================================================
# Script Name   : system_monitor.sh
# Description   : Enterprise VPS monitor (RAM, SWAP, CPU, Load Avg, Disk, Connections, 
#                 Zombie Procs, Security & Malware scans) with Telegram & Lark Card.
# Author        : Antigravity AI
# Version       : 3.4.0
# ==============================================================================

# Thiết lập đường dẫn cấu hình toàn cục an toàn ngoài thư mục dự án
GLOBAL_CONFIG_DIR="/etc/star-bash"
CONFIG_FILE="${GLOBAL_CONFIG_DIR}/monitor.env"

# Nếu chưa có cấu hình toàn cục, fallback về thư mục hiện tại của script
if [ ! -f "$CONFIG_FILE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    CONFIG_FILE="${SCRIPT_DIR}/config.env"
    if [ ! -f "$CONFIG_FILE" ]; then
        CONFIG_FILE="${SCRIPT_DIR}/config.env.example"
    fi
fi

# Nạp cấu hình
source "$CONFIG_FILE"

# IP Public của máy chủ và thời gian
SERVER_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)
DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')
UPTIME_VAL=$(uptime -p 2>/dev/null || echo "N/A")

# Khai báo biến chế độ Test
TEST_MODE=false
if [ "${1:-}" = "--test" ] || [ "${1:-}" = "-t" ]; then
    TEST_MODE=true
fi

# Các biến thu thập lỗi
TELE_ALERT_MSG=""
LARK_ALERT_MSG=""

# ------------------------------------------------------------------------------
# HÀM GỬI THÔNG BÁO TELEGRAM (Định dạng HTML cao cấp)
# ------------------------------------------------------------------------------
send_telegram() {
    local html_body="$1"
    if [ "$ENABLE_TELEGRAM" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local full_msg="🚨 <b>CẢNH BÁO HỆ THỐNG VPS KHẨN CẤP</b>
<b>━━━━━━━━━━━━━━━━━━━━━━━━</b>
<b>🖥️ Host:</b> <code>$HOSTNAME</code>
<b>🌐 IP:</b> <code>$SERVER_IP</code>
<b>⏱️ Uptime:</b> <code>$UPTIME_VAL</code>
<b>📅 Thời gian:</b> <code>$DATE_TIME</code>
<b>━━━━━━━━━━━━━━━━━━━━━━━━</b>

$html_body"

        local payload
        payload=$(jq -n --arg chat_id "$TELEGRAM_CHAT_ID" --arg text "$full_msg" --arg parse_mode "HTML" \
            '{chat_id: $chat_id, text: $text, parse_mode: $parse_mode}')
        
        if [ "$TEST_MODE" = "true" ]; then
            echo -e "\n📤 [Telegram] Đang gửi thông báo test tới Telegram..."
            local response
            response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -H "Content-Type: application/json" \
                -d "$payload")
            echo -e "💬 [Telegram API Response]: $response"
        else
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -H "Content-Type: application/json" \
                -d "$payload" > /dev/null
        fi
    fi
}

# ------------------------------------------------------------------------------
# HÀM GỬI THÔNG BÁO LARK SUITE (Thẻ Interactive Card cao cấp giống Gitlab)
# ------------------------------------------------------------------------------
send_lark_card() {
    local markdown_body="$1"
    if [ "$ENABLE_LARK" = "true" ] && [ -n "$LARK_WEBHOOK_URL" ]; then
        
        # Đóng gói JSON Interactive Card siêu chuẩn bằng jq
        local payload
        payload=$(jq -n \
            --arg hostname "$HOSTNAME" \
            --arg ip "$SERVER_IP" \
            --arg uptime "$UPTIME_VAL" \
            --arg time "$DATE_TIME" \
            --arg content "$markdown_body" \
            '{
                msg_type: "interactive",
                card: {
                    config: {
                        wide_screen_mode: true,
                        enable_forward: true
                    },
                    header: {
                        template: "red",
                        title: {
                            tag: "plain_text",
                            content: ("🚨 CẢNH BÁO VPS: " + $hostname + " (" + $ip + ")")
                        }
                    },
                    elements: [
                        {
                            tag: "div",
                            fields: [
                                {
                                    is_short: true,
                                    text: {
                                        tag: "lark_md",
                                        content: ("**🖥️ Máy chủ:**\n" + $hostname)
                                    }
                                },
                                {
                                    is_short: true,
                                    text: {
                                        tag: "lark_md",
                                        content: ("**🌐 Địa chỉ IP:**\n" + $ip)
                                    }
                                },
                                {
                                    is_short: true,
                                    text: {
                                        tag: "lark_md",
                                        content: ("**⏱️ Uptime:**\n" + $uptime)
                                    }
                                },
                                {
                                    is_short: true,
                                    text: {
                                        tag: "lark_md",
                                        content: ("**📅 Thời gian quét:**\n" + $time)
                                    }
                                }
                            ]
                        },
                        {
                            tag: "hr"
                        },
                        {
                            tag: "div",
                            text: {
                                tag: "lark_md",
                                content: $content
                            }
                        },
                        {
                            tag: "hr"
                        },
                        {
                            tag: "note",
                            elements: [
                                {
                                    tag: "plain_text",
                                    content: "💡 DevOps Command Center - Star-Bash Suite"
                                }
                            ]
                        }
                    ]
                }
            }')

        if [ "$TEST_MODE" = "true" ]; then
            echo -e "\n📤 [Lark Suite] Đang gửi thông báo test tới Lark Suite..."
            local response
            response=$(curl -s -X POST "$LARK_WEBHOOK_URL" \
                -H "Content-Type: application/json" \
                -d "$payload")
            echo -e "💬 [Lark Suite API Response]: $response"
        else
            curl -s -X POST "$LARK_WEBHOOK_URL" \
                -H "Content-Type: application/json" \
                -d "$payload" > /dev/null
        fi
    fi
}

# ------------------------------------------------------------------------------
# CHẾ ĐỘ CHẠY THỬ (TEST MODE) - Gửi ngay tin nhắn giả lập
# ------------------------------------------------------------------------------
if [ "$TEST_MODE" = "true" ]; then
    echo -e "🧪 [Chế độ chạy thử] Khởi chạy mô phỏng gửi cảnh báo..."
    
    # Tạo nội dung giả lập RAM quá tải
    TOP_RAM_PROCESS="PID 226394  RAM 34.5%  /usr/bin/node (NextJS Build)\nPID 5996    RAM 12.1%  /usr/bin/dockerd"
    
    TELE_ALERT_MSG+="⚠️ <b>[MÔ PHỎNG] RAM TĂNG CAO: 92%</b> (Ngưỡng: ${RAM_THRESHOLD_PERCENT}%)
<pre>Top tiến trình ngốn RAM nhất:
$TOP_RAM_PROCESS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    LARK_ALERT_MSG+="⚠️ **[MÔ PHỎNG] RAM TĂNG CAO: 92%** (Ngưỡng: ${RAM_THRESHOLD_PERCENT}%)\n"
    LARK_ALERT_MSG+="*Top tiến trình chiếm dụng:*\n"
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n'"$TOP_RAM_PROCESS"
    LARK_ALERT_MSG+=$'\n'
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n\n'

    # Tạo nội dung giả lập Đăng nhập SSH
    RECENT_LOGINS="- root from 113.161.12.34 (accepted password)\n- deployer from 113.161.12.34 (accepted publickey)"
    
    TELE_ALERT_MSG+="🔑 <b>[MÔ PHỎNG] ĐĂNG NHẬP SSH THÀNH CÔNG MỚI:</b>
<pre>$RECENT_LOGINS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    LARK_ALERT_MSG+="🔑 **[MÔ PHỎNG] ĐĂNG NHẬP SSH THÀNH CÔNG MỚI:**\n"
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n'"$RECENT_LOGINS"
    LARK_ALERT_MSG+=$'\n'
    LARK_ALERT_MSG+='```'

    # Thực thi gửi tin nhắn và thoát
    TELE_ALERT_MSG=$(echo -e "$TELE_ALERT_MSG" | sed 's/━━━━━━━━━━━━━━━━━━━━━━━━\\n$//')
    LARK_ALERT_MSG=$(echo -e "$LARK_ALERT_MSG")
    
    send_telegram "$TELE_ALERT_MSG"
    send_lark_card "$LARK_ALERT_MSG"
    exit 0
fi

# ------------------------------------------------------------------------------
# 1. GIÁM SÁT TÀI NGUYÊN HỆ THỐNG THỰC TẾ (CHẠY THẬT)
# ------------------------------------------------------------------------------

# 1.1 Kiểm tra RAM
RAM_USAGE_PCT=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
if [ "$RAM_USAGE_PCT" -ge "$RAM_THRESHOLD_PERCENT" ]; then
    TOP_RAM_PROCESS=$(ps -eo pid,cmd,%mem --sort=-%mem | head -n 4 | tail -n 3 | awk '{printf "PID %-7s RAM %-4s %s\n", $1, $3"%", $2}')
    
    TELE_ALERT_MSG+="⚠️ <b>RAM TĂNG CAO: ${RAM_USAGE_PCT}%</b> (Ngưỡng: ${RAM_THRESHOLD_PERCENT}%)
<pre>Top tiến trình ngốn RAM nhất:
$TOP_RAM_PROCESS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="⚠️ **RAM TĂNG CAO: ${RAM_USAGE_PCT}%** (Ngưỡng: ${RAM_THRESHOLD_PERCENT}%)\n"
    LARK_ALERT_MSG+="*Top tiến trình chiếm dụng:*\n"
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n'"$TOP_RAM_PROCESS"
    LARK_ALERT_MSG+=$'\n'
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n\n'
fi

# 1.2 Kiểm tra SWAP
SWAP_TOTAL=$(free | grep Swap | awk '{print $2}')
if [ "$SWAP_TOTAL" -gt 0 ]; then
    SWAP_USAGE_PCT=$(free | grep Swap | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
    if [ "$SWAP_USAGE_PCT" -ge 60 ]; then
        TELE_ALERT_MSG+="⚠️ <b>SWAP BỊ DÙNG NHIỀU: ${SWAP_USAGE_PCT}%</b> (RAM vật lý đã cạn kiệt)
━━━━━━━━━━━━━━━━━━━━━━━━\n"

        LARK_ALERT_MSG+="⚠️ **BỘ NHỚ ẢO SWAP BỊ DÙNG QUÁ MỨC: ${SWAP_USAGE_PCT}%**\n*Cảnh báo:* RAM vật lý đã cạn kiệt, hệ thống đang phải swap ảo trên SSD/HDD (gây đơ máy).\n\n"
    fi
fi

# 1.3 Kiểm tra CPU và Load Average
CPU_USAGE_PCT=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | cut -d. -f1)
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1" "$2" "$3}')
CPU_CORES=$(nproc)
LOAD_1M=$(cat /proc/loadavg | awk '{print $1}' | cut -d. -f1)

if [ "$CPU_USAGE_PCT" -ge "$CPU_THRESHOLD_PERCENT" ] || [ "$LOAD_1M" -ge "$CPU_CORES" ]; then
    TOP_CPU_PROCESS=$(ps -eo pid,cmd,%cpu --sort=-%cpu | head -n 4 | tail -n 3 | awk '{printf "PID %-7s CPU %-4s %s\n", $1, $3"%", $2}')

    TELE_ALERT_MSG+="🔥 <b>CPU/TẢI HỆ THỐNG CAO: CPU ${CPU_USAGE_PCT}%</b>
<b>Tải trung bình (1/5/15m):</b> <code>$LOAD_AVG</code> (Nhân CPU: $CPU_CORES)
<pre>Top tiến trình ngốn CPU nhất:
$TOP_CPU_PROCESS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="🔥 **CPU/TẢI HỆ THỐNG QUÁ TẢI: CPU ${CPU_USAGE_PCT}%**\n"
    LARK_ALERT_MSG+="**Tải trung bình (1/5/15m):** \`$LOAD_AVG\` (Số nhân CPU: $CPU_CORES)\n"
    LARK_ALERT_MSG+="*Top tiến trình ngốn CPU nhất:*\n"
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n'"$TOP_CPU_PROCESS"
    LARK_ALERT_MSG+=$'\n'
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n\n'
fi

# 1.4 Kiểm tra Ổ cứng (Disk)
DISK_USAGE_PCT=$(df -h / | grep / | awk '{print $5}' | cut -d% -f1)
if [ "$DISK_USAGE_PCT" -ge "$DISK_THRESHOLD_PERCENT" ]; then
    DISK_DETAIL=$(df -h / | tail -n 1 | awk '{printf "Tổng: %s - Đã dùng: %s - Trống: %s", $2, $3, $4}')

    TELE_ALERT_MSG+="💾 <b>Ổ CỨNG SẮP ĐẦY: ${DISK_USAGE_PCT}%</b> (Ngưỡng: ${DISK_THRESHOLD_PERCENT}%)
<code>$DISK_DETAIL</code>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="💾 **Ổ CỨNG SẮP ĐẦY: ${DISK_USAGE_PCT}%** (Ngưỡng: ${DISK_THRESHOLD_PERCENT}%)\n*Chi tiết:* \`$DISK_DETAIL\`\n\n"
fi

# 1.5 Kiểm tra các tiến trình Zombie treo
ZOMBIE_COUNT=$(ps -eo state | grep -c 'Z' || echo "0")
if [ "$ZOMBIE_COUNT" -gt 3 ]; then
    ZOMBIE_LIST=$(ps -eo pid,ppid,stat,cmd | awk '$3 ~ /Z/ {print "PID: "$1" - Parent: "$2" - "$4}' | head -n 5)
    TELE_ALERT_MSG+="🧟 <b>PHÁT HIỆN TIẾN TRÌNH ZOMBIE (BỊ TREO): $ZOMBIE_COUNT tiến trình</b>
<pre>$ZOMBIE_LIST</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="🧟 **PHÁT HIỆN TIẾN TRÌNH ZOMBIE (TREO): ${ZOMBIE_COUNT} procs**\n"
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n'"$ZOMBIE_LIST"
    LARK_ALERT_MSG+=$'\n'
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n\n'
fi

# 1.6 Giám sát Số lượng Kết nối Mạng
CONN_TOTAL=$(ss -ant | wc -l)
CONN_ESTABLISHED=$(ss -ant state established | wc -l)
CONN_SYN_RECV=$(ss -ant state syn-recv | wc -l)

if [ "$CONN_TOTAL" -gt 1500 ] || [ "$CONN_SYN_RECV" -gt 30 ]; then
    NET_ALERT="Tổng kết nối: $CONN_TOTAL | Kết nối hoạt động: $CONN_ESTABLISHED | SYN_RECV (DDoS?): $CONN_SYN_RECV"
    
    TELE_ALERT_MSG+="🌐 <b>CẢNH BÁO KẾT NỐI MẠNG ĐỘT BIẾN:</b>
<code>$NET_ALERT</code>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="🌐 **CẢNH BÁO KẾT NỐI MẠNG ĐỘT BIẾN:**\n\`$NET_ALERT\`\n\n"
fi

# ------------------------------------------------------------------------------
# 2. PHÁT HIỆN AN NINH & CẢNH BÁO MALWARE
# ------------------------------------------------------------------------------
MALWARE_TELE=""
MALWARE_LARK=""

if [ "$SCAN_SUSPICIOUS_PATHS" = "true" ]; then
    SUSPICIOUS_PROCS=$(ls -l /proc/*/exe 2>/dev/null | grep -E '\(/tmp|/dev/shm|/var/tmp\)' | awk '{print $9" -> "$11}' | head -n 5 || true)
    if [ -n "$SUSPICIOUS_PROCS" ]; then
        MALWARE_TELE+="⚠️ <b>Phát hiện thực thi từ thư mục tạm (Nghi ngờ Malware):</b>\n<pre>$SUSPICIOUS_PROCS</pre>\n"
        
        MALWARE_LARK+="⚠️ **Phát hiện thực thi từ thư mục tạm (Malware?):**\n"
        MALWARE_LARK+='```'
        MALWARE_LARK+=$'\n'"$SUSPICIOUS_PROCS"
        MALWARE_LARK+=$'\n'
        MALWARE_LARK+='```'
        MALWARE_LARK+=$'\n'
    fi
    
    HEAVY_PROCS=$(ps -eo pid,cmd,%cpu --sort=-%cpu | awk '$3 > 85.0 {printf "PID %-7s CPU %-4s %s\n", $1, $3"%", $2}' | head -n 5)
    if [ -n "$HEAVY_PROCS" ]; then
        if ! echo "$HEAVY_PROCS" | grep -qE "(node|next|npm|webpack)"; then
            MALWARE_TELE+="⚠️ <b>Tiến trình chiếm dụng CPU bất thường (>85%):</b>\n<pre>$HEAVY_PROCS</pre>\n"
            
            MALWARE_LARK+="⚠️ **Tiến trình chiếm dụng CPU bất thường (>85%):**\n"
            MALWARE_LARK+='```'
            MALWARE_LARK+=$'\n'"$HEAVY_PROCS"
            MALWARE_LARK+=$'\n'
            MALWARE_LARK+='```'
            MALWARE_LARK+=$'\n'
        fi
    fi
fi

if [ -n "$MALWARE_TELE" ]; then
    TELE_ALERT_MSG+="☣️ <b>CẢNH BÁO AN NINH & MALWARE</b>
$MALWARE_TELE━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="☣️ **CẢNH BÁO AN NINH & MALWARE**\n$MALWARE_LARK\n"
fi

# ------------------------------------------------------------------------------
# 3. GIÁM SÁT SSH LOGINS (ĐĂNG NHẬP MỚI)
# ------------------------------------------------------------------------------
if [ "$ENABLE_SSH_MONITOR" = "true" ]; then
    AUTH_LOG="/var/log/auth.log"
    [ ! -f "$AUTH_LOG" ] && AUTH_LOG="/var/log/secure"
    
    if [ -f "$AUTH_LOG" ]; then
        SSH_LOGINS=$(tail -n 50 "$AUTH_LOG" | grep -E "Accepted (publickey|password)" || true)
        RECENT_LOGINS=""
        CURRENT_TIME_EPOCH=$(date +%s)
        
        while read -r line; do
            [ -z "$line" ] && continue
            log_date_str=$(echo "$line" | awk '{print $1" "$2" "$3}')
            log_epoch=$(date -d "$log_date_str" +%s 2>/dev/null)
            if [ -n "$log_epoch" ]; then
                diff=$((CURRENT_TIME_EPOCH - log_epoch))
                if [ "$diff" -ge 0 ] && [ "$diff" -le 300 ]; then
                    clean_login=$(echo "$line" | awk -F'Accepted ' '{print $2}')
                    RECENT_LOGINS+="- $clean_login\n"
                fi
            fi
        done <<< "$SSH_LOGINS"
        
        if [ -n "$RECENT_LOGINS" ]; then
            TELE_ALERT_MSG+="🔑 <b>ĐĂNG NHẬP SSH THÀNH CÔNG MỚI:</b>
<pre>$RECENT_LOGINS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

            LARK_ALERT_MSG+="🔑 **ĐĂNG NHẬP SSH THÀNH CÔNG MỚI:**\n"
            LARK_ALERT_MSG+='```'
            LARK_ALERT_MSG+=$'\n'"$RECENT_LOGINS"
            LARK_ALERT_MSG+=$'\n'
            LARK_ALERT_MSG+='```'
            LARK_ALERT_MSG+=$'\n'
        fi
    fi
fi

# ------------------------------------------------------------------------------
# GỬI THÔNG BÁO CẢNH BÁO NẾU CÓ BẤT THƯỜNG
# ------------------------------------------------------------------------------
if [ -n "$TELE_ALERT_MSG" ]; then
    TELE_ALERT_MSG=$(echo -e "$TELE_ALERT_MSG" | sed 's/━━━━━━━━━━━━━━━━━━━━━━━━\\n$//')
    send_telegram "$TELE_ALERT_MSG"
fi

if [ -n "$LARK_ALERT_MSG" ]; then
    send_lark_card "$LARK_ALERT_MSG"
fi
