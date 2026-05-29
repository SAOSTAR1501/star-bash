#!/bin/bash
# ==============================================================================
# Script Name   : system_monitor.sh
# Description   : Lightweight VPS monitor (RAM, CPU, Disk, Security & Malware scans)
#                 with Telegram and Lark Suite alerting.
# Author        : Antigravity AI
# Version       : 1.0.0
# ==============================================================================

# Thiết lập đường dẫn tương đối và nạp cấu hình
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
    # Fallback về file example nếu chưa cấu hình
    CONFIG_FILE="${SCRIPT_DIR}/config.env.example"
fi

# Nạp cấu hình
source "$CONFIG_FILE"

# IP Public của máy chủ
SERVER_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)
ALERT_MSG=""

# ------------------------------------------------------------------------------
# HÀM GỬI THÔNG BÁO TELEGRAM
# ------------------------------------------------------------------------------
send_telegram() {
    local message="$1"
    if [ "$ENABLE_TELEGRAM" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local payload
        payload=$(jq -n --arg chat_id "$TELEGRAM_CHAT_ID" --arg text "$message" --arg parse_mode "Markdown" \
            '{chat_id: $chat_id, text: $text, parse_mode: $parse_mode}')
        
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -H "Content-Type: application/json" \
            -d "$payload" > /dev/null
    fi
}

# ------------------------------------------------------------------------------
# HÀM GỬI THÔNG BÁO LARK SUITE
# ------------------------------------------------------------------------------
send_lark() {
    local title="$1"
    local message="$2"
    if [ "$ENABLE_LARK" = "true" ] && [ -n "$LARK_WEBHOOK_URL" ]; then
        local payload
        # Format thẻ Rich Text của Lark
        payload=$(jq -n \
            --arg title "$title" \
            --arg text "$message" \
            '{
                msg_type: "post",
                content: {
                    post: {
                        zh_cn: {
                            title: $title,
                            content: [
                                [
                                    {
                                        tag: "text",
                                        text: $text
                                    }
                                ]
                            ]
                        }
                    }
                }
            }')
            
        curl -s -X POST "$LARK_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$payload" > /dev/null
    fi
}

# Hàm phát cảnh báo tổng hợp
trigger_alert() {
    local alert_title="🚨 CẢNH BÁO VPS: $HOSTNAME ($SERVER_IP)"
    local raw_msg="$1"
    
    # Format Telegram (Markdown)
    local tele_msg="*🚨 CẢNH BÁO HỆ THỐNG VPS*
=============================
*Host:* $HOSTNAME
*IP:* \`$SERVER_IP\`
*Thời gian:* \`$(date '+%Y-%m-%d %H:%M:%S')\`
=============================

$raw_msg"

    # Gửi đi
    send_telegram "$tele_msg"
    send_lark "$alert_title" "$raw_msg"
}

# ------------------------------------------------------------------------------
# 1. GIÁM SÁT TÀI NGUYÊN HỆ THỐNG
# ------------------------------------------------------------------------------

# Kiểm tra RAM
RAM_USAGE_PCT=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
if [ "$RAM_USAGE_PCT" -ge "$RAM_THRESHOLD_PERCENT" ]; then
    TOP_RAM_PROCESS=$(ps -eo pid,ppid,cmd,%mem --sort=-%mem | head -n 4 | tail -n 3)
    ALERT_MSG+="⚠️ *RAM tăng đột biến:* Hiện tại đã dùng *${RAM_USAGE_PCT}%* (Ngưỡng: ${RAM_THRESHOLD_PERCENT}%)
*Top tiến trình ngốn RAM nhất:*
\`\`\`
PID   PPID  COMMAND                      %RAM
$TOP_RAM_PROCESS
\`\`\`
-----------------------------------\n"
fi

# Kiểm tra CPU
CPU_USAGE_PCT=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | cut -d. -f1)
if [ "$CPU_USAGE_PCT" -ge "$CPU_THRESHOLD_PERCENT" ]; then
    TOP_CPU_PROCESS=$(ps -eo pid,ppid,cmd,%cpu --sort=-%cpu | head -n 4 | tail -n 3)
    ALERT_MSG+="⚠️ *CPU quá tải:* Hiện tại đã dùng *${CPU_USAGE_PCT}%* (Ngưỡng: ${CPU_THRESHOLD_PERCENT}%)
*Top tiến trình ngốn CPU nhất:*
\`\`\`
PID   PPID  COMMAND                      %CPU
$TOP_CPU_PROCESS
\`\`\`
-----------------------------------\n"
fi

# Kiểm tra Ổ cứng (Disk)
DISK_USAGE_PCT=$(df -h / | grep / | awk '{print $5}' | cut -d% -f1)
if [ "$DISK_USAGE_PCT" -ge "$DISK_THRESHOLD_PERCENT" ]; then
    ALERT_MSG+="⚠️ *Ổ cứng sắp đầy:* Thư mục gốc (/) đã dùng *${DISK_USAGE_PCT}%* (Ngưỡng: ${DISK_THRESHOLD_PERCENT}%)\n-----------------------------------\n"
fi

# ------------------------------------------------------------------------------
# 2. PHÁT HIỆN MALWARE VÀ TIẾN TRÌNH KHÔNG HỢP LỆ
# ------------------------------------------------------------------------------
MALWARE_ALERT=""

if [ "$SCAN_SUSPICIOUS_PATHS" = "true" ]; then
    # Tìm tiến trình chạy từ thư mục tạm (/tmp, /dev/shm, /var/tmp) - dấu hiệu malware
    SUSPICIOUS_PROCS=$(ls -l /proc/*/exe 2>/dev/null | grep -E '\(/tmp|/dev/shm|/var/tmp\)' || true)
    if [ -n "$SUSPICIOUS_PROCS" ]; then
        MALWARE_ALERT+="⚠️ *Phát hiện tiến trình chạy từ thư mục tạm (Nghi ngờ Malware/Miner):*
\`\`\`
$SUSPICIOUS_PROCS
\`\`\`\n"
    fi
    
    # Phát hiện tiến trình chiếm dụng > 85% CPU ẩn (Miner đào coin)
    HEAVY_PROCS=$(ps -eo pid,cmd,%cpu --sort=-%cpu | awk '$3 > 85.0 {print "PID: "$1" - "$2" ("$3"%)"}' | head -n 5)
    if [ -n "$HEAVY_PROCS" ]; then
        # Ngoại trừ tiến trình biên dịch Next.js/Webpack hợp lệ nếu có
        if ! echo "$HEAVY_PROCS" | grep -qE "(node|next|npm|webpack)"; then
            MALWARE_ALERT+="⚠️ *Phát hiện tiến trình ngốn CPU bất thường (>85% CPU):*
\`\`\`
$HEAVY_PROCS
\`\`\`\n"
        fi
    fi
fi

if [ -n "$MALWARE_ALERT" ]; then
    ALERT_MSG+="☣️ *CẢNH BÁO AN NINH & MALWARE:*
$MALWARE_ALERT
-----------------------------------\n"
fi

# ------------------------------------------------------------------------------
# 3. GIÁM SÁT SSH LOGINS (ĐĂNG NHẬP THÀNH CÔNG MỚI)
# ------------------------------------------------------------------------------
if [ "$ENABLE_SSH_MONITOR" = "true" ]; then
    # Đường dẫn log đăng nhập tuỳ hệ điều hành
    AUTH_LOG="/var/log/auth.log"
    [ ! -f "$AUTH_LOG" ] && AUTH_LOG="/var/log/secure"
    
    if [ -f "$AUTH_LOG" ]; then
        # Kiểm tra xem có đăng nhập SSH thành công mới trong 5 phút qua không
        # Tìm các dòng "Accepted publickey" hoặc "Accepted password"
        SSH_LOGINS=$(tail -n 50 "$AUTH_LOG" | grep -E "Accepted (publickey|password)" || true)
        
        # Lọc đăng nhập trong vòng 5 phút gần nhất
        RECENT_LOGINS=""
        CURRENT_TIME_EPOCH=$(date +%s)
        
        while read -r line; do
            [ -z "$line" ] && continue
            # Parse thời gian của dòng log
            log_date_str=$(echo "$line" | awk '{print $1" "$2" "$3}')
            log_epoch=$(date -d "$log_date_str" +%s 2>/dev/null)
            if [ -n "$log_epoch" ]; then
                diff=$((CURRENT_TIME_EPOCH - log_epoch))
                # 300 giây = 5 phút
                if [ "$diff" -ge 0 ] && [ "$diff" -le 300 ]; then
                    RECENT_LOGINS+="$line\n"
                fi
            fi
        done <<< "$SSH_LOGINS"
        
        if [ -n "$RECENT_LOGINS" ]; then
            ALERT_MSG+="🔑 *Phát hiện đăng nhập SSH thành công mới:*
\`\`\`
$RECENT_LOGINS
\`\`\`
-----------------------------------\n"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# KÍCH HOẠT GỬI CẢNH BÁO NẾU CÓ BẤT THƯỜNG
# ------------------------------------------------------------------------------
if [ -n "$ALERT_MSG" ]; then
    # Xoá ký tự xuống dòng dư thừa ở cuối cùng
    ALERT_MSG=$(echo -e "$ALERT_MSG" | sed 's/-----------------------------------\\n$//')
    trigger_alert "$ALERT_MSG"
fi
