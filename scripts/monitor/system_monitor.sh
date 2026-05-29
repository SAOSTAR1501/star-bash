#!/bin/bash
# ==============================================================================
# Script Name   : system_monitor.sh
# Description   : Premium VPS monitor (RAM, CPU, Disk, Security & Malware scans)
#                 with high-end Telegram (HTML) and Lark Card (Interactive) alerts.
# Author        : Antigravity AI
# Version       : 2.0.0
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

# Các biến thu thập lỗi
TELE_ALERT_MSG=""
LARK_ALERT_ELEMENTS=""

# ------------------------------------------------------------------------------
# HÀM GỬI THÔNG BÁO TELEGRAM (Định dạng HTML cao cấp)
# ------------------------------------------------------------------------------
send_telegram() {
    local html_body="$1"
    if [ "$ENABLE_TELEGRAM" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local full_msg="🚨 <b>CẢNH BÁO BẤT THƯỜNG VPS</b>
<b>━━━━━━━━━━━━━━━━━━━━━━━━</b>
<b>🖥️ Host:</b> <code>$HOSTNAME</code>
<b>🌐 IP:</b> <code>$SERVER_IP</code>
<b>📅 Thời gian:</b> <code>$DATE_TIME</code>
<b>━━━━━━━━━━━━━━━━━━━━━━━━</b>

$html_body"

        local payload
        payload=$(jq -n --arg chat_id "$TELEGRAM_CHAT_ID" --arg text "$full_msg" --arg parse_mode "HTML" \
            '{chat_id: $chat_id, text: $text, parse_mode: $parse_mode}')
        
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -H "Content-Type: application/json" \
            -d "$payload" > /dev/null
    fi
}

# ------------------------------------------------------------------------------
# HÀM GỬI THÔNG BÁO LARK SUITE (Thẻ Interactive Card Premium)
# ------------------------------------------------------------------------------
send_lark_card() {
    if [ "$ENABLE_LARK" = "true" ] && [ -n "$LARK_WEBHOOK_URL" ] && [ -n "$LARK_ALERT_ELEMENTS" ]; then
        # Xóa dấu phẩy thừa ở cuối danh sách elements JSON
        local cleaned_elements
        cleaned_elements=$(echo -e "$LARK_ALERT_ELEMENTS" | sed 's/,$//')

        local payload
        payload="{
            \"msg_type\": \"interactive\",
            \"card\": {
                \"config\": {
                    \"wide_screen_mode\": true,
                    \"enable_forward\": true
                },
                \"header\": {
                    \"title\": {
                        \"tag\": \"plain_text\",
                        \"content\": \"🚨 CẢNH BÁO BẤT THƯỜNG HỆ THỐNG VPS\"
                    },
                    \"template\": \"red\"
                },
                \"elements\": [
                    {
                        \"tag\": \"div\",
                        \"fields\": [
                            {
                                \"is_short\": true,
                                \"text\": {
                                    \"tag\": \"lark_md\",
                                    \"content\": \"**🖥️ Máy chủ:**\\n$HOSTNAME\"
                                }
                            },
                            {
                                \"is_short\": true,
                                \"text\": {
                                    \"tag\": \"lark_md\",
                                    \"content\": \"**🌐 Địa chỉ IP:**\\n$SERVER_IP\"
                                }
                            },
                            {
                                \"is_short\": false,
                                \"text\": {
                                    \"tag\": \"lark_md\",
                                    \"content\": \"**📅 Thời gian phát hiện:**\\n$DATE_TIME\"
                                }
                            }
                        ]
                    },
                    {
                        \"tag\": \"hr\"
                    },
                    $cleaned_elements
                ]
            }
        }"

        curl -s -X POST "$LARK_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$payload" > /dev/null
    fi
}

# ------------------------------------------------------------------------------
# 1. GIÁM SÁT TÀI NGUYÊN HỆ THỐNG
# ------------------------------------------------------------------------------

# 1.1 Kiểm tra RAM
RAM_USAGE_PCT=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
if [ "$RAM_USAGE_PCT" -ge "$RAM_THRESHOLD_PERCENT" ]; then
    TOP_RAM_PROCESS=$(ps -eo pid,cmd,%mem --sort=-%mem | head -n 4 | tail -n 3 | awk '{printf "PID %-7s RAM %-4s %s\n", $1, $3"%", $2}')
    
    # Telegram Msg
    TELE_ALERT_MSG+="⚠️ <b>RAM TĂNG CAO: ${RAM_USAGE_PCT}%</b> (Ngưỡng: ${RAM_THRESHOLD_PERCENT}%)
<pre>Top tiến trình ngốn RAM nhất:
$TOP_RAM_PROCESS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    # Lark Element
    LARK_ALERT_ELEMENTS+="{
        \"tag\": \"div\",
        \"text\": {
            \"tag\": \"lark_md\",
            \"content\": \"⚠️ **RAM TĂNG CAO: ${RAM_USAGE_PCT}%** (Ngưỡng cảnh báo: ${RAM_THRESHOLD_PERCENT}%)\\n\\n**Top tiến trình chiếm dụng:**\\n\`\`\`\\n$TOP_RAM_PROCESS\\n\`\`\`\"
        }
    },"
fi

# 1.2 Kiểm tra CPU
CPU_USAGE_PCT=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | cut -d. -f1)
if [ "$CPU_USAGE_PCT" -ge "$CPU_THRESHOLD_PERCENT" ]; then
    TOP_CPU_PROCESS=$(ps -eo pid,cmd,%cpu --sort=-%cpu | head -n 4 | tail -n 3 | awk '{printf "PID %-7s CPU %-4s %s\n", $1, $3"%", $2}')

    # Telegram Msg
    TELE_ALERT_MSG+="🔥 <b>CPU QUÁ TẢI: ${CPU_USAGE_PCT}%</b> (Ngưỡng: ${CPU_THRESHOLD_PERCENT}%)
<pre>Top tiến trình ngốn CPU nhất:
$TOP_CPU_PROCESS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    # Lark Element
    LARK_ALERT_ELEMENTS+="{
        \"tag\": \"div\",
        \"text\": {
            \"tag\": \"lark_md\",
            \"content\": \"🔥 **CPU QUÁ TẢI: ${CPU_USAGE_PCT}%** (Ngưỡng cảnh báo: ${CPU_THRESHOLD_PERCENT}%)\\n\\n**Top tiến trình chiếm dụng:**\\n\`\`\`\\n$TOP_CPU_PROCESS\\n\`\`\`\"
        }
    },"
fi

# 1.3 Kiểm tra Ổ cứng (Disk)
DISK_USAGE_PCT=$(df -h / | grep / | awk '{print $5}' | cut -d% -f1)
if [ "$DISK_USAGE_PCT" -ge "$DISK_THRESHOLD_PERCENT" ]; then
    DISK_DETAIL=$(df -h / | tail -n 1 | awk '{printf "Tổng: %s - Đã dùng: %s - Trống: %s", $2, $3, $4}')

    # Telegram Msg
    TELE_ALERT_MSG+="💾 <b>Ổ CỨNG SẮP ĐẦY: ${DISK_USAGE_PCT}%</b>
<code>$DISK_DETAIL</code>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    # Lark Element
    LARK_ALERT_ELEMENTS+="{
        \"tag\": \"div\",
        \"text\": {
            \"tag\": \"lark_md\",
            \"content\": \"💾 **Ổ CỨNG SẮP ĐẦY: ${DISK_USAGE_PCT}%** (Ngưỡng: ${DISK_THRESHOLD_PERCENT}%)\\n*Chi tiết:* \`$DISK_DETAIL\`\"
        }
    },"
fi

# ------------------------------------------------------------------------------
# 2. PHÁT HIỆN AN NINH & CẢNH BÁO MALWARE
# ------------------------------------------------------------------------------
MALWARE_TELE=""
MALWARE_LARK=""

if [ "$SCAN_SUSPICIOUS_PATHS" = "true" ]; then
    # Tìm tiến trình đáng ngờ chạy từ /tmp, /dev/shm
    SUSPICIOUS_PROCS=$(ls -l /proc/*/exe 2>/dev/null | grep -E '\(/tmp|/dev/shm|/var/tmp\)' | awk '{print $9" -> "$11}' | head -n 5 || true)
    if [ -n "$SUSPICIOUS_PROCS" ]; then
        MALWARE_TELE+="⚠️ <b>Phát hiện thực thi từ thư mục tạm (Nghi ngờ Malware):</b>\n<pre>$SUSPICIOUS_PROCS</pre>\n"
        MALWARE_LARK+="⚠️ **Phát hiện thực thi từ thư mục tạm (Nghi ngờ Malware):**\\n\`\`\`\\n$SUSPICIOUS_PROCS\\n\`\`\`\\n"
    fi
    
    # Phát hiện tiến trình CPU > 85% lạ
    HEAVY_PROCS=$(ps -eo pid,cmd,%cpu --sort=-%cpu | awk '$3 > 85.0 {printf "PID %-7s CPU %-4s %s\n", $1, $3"%", $2}' | head -n 5)
    if [ -n "$HEAVY_PROCS" ]; then
        # Ngoại trừ tiến trình dev/build thông thường
        if ! echo "$HEAVY_PROCS" | grep -qE "(node|next|npm|webpack)"; then
            MALWARE_TELE+="⚠️ <b>Tiến trình chiếm dụng CPU bất thường (>85%):</b>\n<pre>$HEAVY_PROCS</pre>\n"
            MALWARE_LARK+="⚠️ **Tiến trình chiếm dụng CPU bất thường (>85%):**\\n\`\`\`\\n$HEAVY_PROCS\\n\`\`\`\\n"
        fi
    fi
fi

if [ -n "$MALWARE_TELE" ]; then
    # Telegram Msg
    TELE_ALERT_MSG+="☣️ <b>CẢNH BÁO AN NINH & MALWARE</b>
$MALWARE_TELE━━━━━━━━━━━━━━━━━━━━━━━━\n"

    # Lark Element
    LARK_ALERT_ELEMENTS+="{
        \"tag\": \"div\",
        \"text\": {
            \"tag\": \"lark_md\",
            \"content\": \"☣️ **CẢNH BÁO AN NINH & MALWARE**\\n\\n$MALWARE_LARK\"
        }
    },"
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
                    # Rút gọn chuỗi login để dễ nhìn
                    clean_login=$(echo "$line" | awk -F'Accepted ' '{print $2}')
                    RECENT_LOGINS+="- $clean_login\n"
                fi
            fi
        done <<< "$SSH_LOGINS"
        
        if [ -n "$RECENT_LOGINS" ]; then
            # Telegram Msg
            TELE_ALERT_MSG+="🔑 <b>ĐĂNG NHẬP SSH THÀNH CÔNG MỚI:</b>
<pre>$RECENT_LOGINS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

            # Lark Element
            LARK_ALERT_ELEMENTS+="{
                \"tag\": \"div\",
                \"text\": {
                    \"tag\": \"lark_md\",
                    \"content\": \"🔑 **ĐĂNG NHẬP SSH THÀNH CÔNG MỚI:**\\n\`\`\`\\n$RECENT_LOGINS\\n\`\`\`\"
                }
            },"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# GỬI THÔNG BÁO CẢNH BÁO
# ------------------------------------------------------------------------------
if [ -n "$TELE_ALERT_MSG" ]; then
    # Cắt bỏ ký tự ngăn cách thừa ở cuối tin Telegram
    TELE_ALERT_MSG=$(echo -e "$TELE_ALERT_MSG" | sed 's/━━━━━━━━━━━━━━━━━━━━━━━━\\n$//')
    
    # Kích hoạt gửi tin
    send_telegram "$TELE_ALERT_MSG"
    send_lark_card
fi
