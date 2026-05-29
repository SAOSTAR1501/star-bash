#!/bin/bash
# ==============================================================================
# Script Name   : system_monitor.sh
# Description   : Enterprise VPS Security & System Health Monitor (RAM, SWAP, CPU, 
#                 Load Avg, Disk, Connections, Network Bandwidth Traffic, Firewall, 
#                 SSH Audit, failed SSH logins brute-force detect, Malware & Privilege scans)
#                 with High-end Telegram & Lark Card formatting.
# Author        : Antigravity AI
# Version       : 5.0.0
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

# Ngưỡng băng thông cảnh báo mặc định (MB/s)
NET_SPEED_THRESHOLD_MB=30

# ------------------------------------------------------------------------------
# HÀM GỬI THÔNG BÁO TELEGRAM (Định dạng HTML cao cấp)
# ------------------------------------------------------------------------------
send_telegram() {
    local html_body="$1"
    if [ "$ENABLE_TELEGRAM" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local full_msg="🚨 <b>CẢNH BÁO AN NINH & HỆ THỐNG VPS KHẨN CẤP</b>
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
# HÀM GỬI THÔNG BÁO LARK SUITE (Thẻ Interactive Card cao cấp)
# ------------------------------------------------------------------------------
send_lark_card() {
    local markdown_body="$1"
    if [ "$ENABLE_LARK" = "true" ] && [ -n "$LARK_WEBHOOK_URL" ]; then
        
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
                            content: ("🚨 CẢNH BÁO HỆ THỐNG VPS: " + $hostname)
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
                                    content: "💡 Security Audit & System Health Monitor - Star-Bash DevOps Suite"
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
# CẢM BIẾN ĐO TRAFFIC MẠNG THỜI GIAN THỰC
# ------------------------------------------------------------------------------
NET_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
[ -z "$NET_INTERFACE" ] && NET_INTERFACE="eth0"

get_net_bytes() {
    local rx tx
    rx=$(cat /proc/net/dev | grep "$NET_INTERFACE" | awk '{print $2}')
    tx=$(cat /proc/net/dev | grep "$NET_INTERFACE" | awk '{print $10}')
    echo "$rx $tx"
}

read -r RX1 TX1 <<< "$(get_net_bytes)"
sleep 2
read -r RX2 TX2 <<< "$(get_net_bytes)"

RX_SPEED_MB=$(echo "$RX1 $RX2" | awk '{printf "%.2f", ($2-$1)/1024/1024/2}')
TX_SPEED_MB=$(echo "$TX1 $TX2" | awk '{printf "%.2f", ($2-$1)/1024/1024/2}')

# ------------------------------------------------------------------------------
# CHẾ ĐỘ CHẠY THỬ (TEST MODE) - Gửi ngay tin nhắn giả lập
# ------------------------------------------------------------------------------
if [ "$TEST_MODE" = "true" ]; then
    echo -e "🧪 [Chế độ chạy thử] Khởi chạy mô phỏng gửi cảnh báo..."
    
    # 1. Giả lập tài nguyên quá tải
    TOP_RAM_PROCESS="PID 226394  RAM 34.5%  /usr/bin/node (NextJS Build)\nPID 5996    RAM 12.1%  /usr/bin/dockerd"
    TELE_ALERT_MSG+="⚠️ <b>[MÔ PHỎNG] RAM VÀ SWAP QUÁ TẢI</b>
<b>Dung lượng RAM thực tế:</b> dùng 14.2GB / 15.0GB (94%)
<b>Dung lượng bộ nhớ ảo SWAP:</b> dùng 2.8GB / 4.0GB (70%)
<pre>Top tiến trình ngốn RAM nhất:
$TOP_RAM_PROCESS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    LARK_ALERT_MSG+="⚠️ **[MÔ PHỎNG] RAM VÀ SWAP QUÁ TẢI**\n"
    LARK_ALERT_MSG+="* Dung lượng RAM thực tế: dùng 14.2GB / 15.0GB (94%)\n"
    LARK_ALERT_MSG+="* Dung lượng bộ nhớ ảo SWAP: dùng 2.8GB / 4.0GB (70%)\n"
    LARK_ALERT_MSG+="*Top tiến trình chiếm dụng:*\n"
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n'"$TOP_RAM_PROCESS"
    LARK_ALERT_MSG+=$'\n'
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n\n'

    # 2. Giả lập Cảnh báo Tường lửa & SSH (Từ Security Audit)
    TELE_ALERT_MSG+="🛡️ <b>[MÔ PHỎNG] CẢNH BÁO TƯỜNG LỬA & BẢO MẬT SSH:</b>
<b>Cảnh báo Tường lửa:</b> 🔴 <b>UFW Firewall đang bị TẮT (INACTIVE)</b>
<b>Cảnh báo SSH Port:</b> ⚠️ SSH đang mở ở cổng mặc định <b>22</b>
<b>Cảnh báo Root login:</b> 🔴 Cho phép root đăng nhập trực tiếp qua mật khẩu!
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="🛡️ **[MÔ PHỎNG] CẢNH BÁO TƯỜNG LỬA & BẢO MẬT SSH:**\n"
    LARK_ALERT_MSG+="* Cảnh báo Tường lửa: 🔴 **UFW Firewall đang bị TẮT (INACTIVE)**\n"
    LARK_ALERT_MSG+="* Cảnh báo SSH Port: ⚠️ SSH đang mở ở cổng mặc định **22**\n"
    LARK_ALERT_MSG+="* Cảnh báo Root login: 🔴 Cho phép root đăng nhập trực tiếp qua mật khẩu!\n\n"

    # 3. Giả lập Brute-force SSH (Từ Security Audit)
    IP_ATTACKS="- 112.198.23.45 (Philippines) : 1,450 lần\n- 45.123.45.67 (China)       : 820 lần"
    TELE_ALERT_MSG+="🕵️ <b>[MÔ PHỎNG] PHÁT HIỆN TẤN CÔNG DÒ MẬT KHẨU (BRUTE-FORCE):</b>
Tổng số lượt SSH đăng nhập thất bại trong 30 phút: <b>2,270 lần</b>
<pre>Top 2 địa chỉ IP tấn công dồn dập nhất:
$IP_ATTACKS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="🕵️ **[MÔ PHỎNG] PHÁT HIỆN TẤN CÔNG DÒ MẬT KHẨU (BRUTE-FORCE):**\n"
    LARK_ALERT_MSG+="Tổng số lượt SSH đăng nhập thất bại trong 30 phút: **2,270 lần**\n"
    LARK_ALERT_MSG+="*Top địa chỉ IP tấn công dồn dập nhất:*\n"
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n'"$IP_ATTACKS"
    LARK_ALERT_MSG+=$'\n'
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n\n'

    # 4. Giả lập Đăng nhập SSH thành công
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

# 1.1 Kiểm tra RAM & SWAP
RAM_USAGE_PCT=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
if [ "$RAM_USAGE_PCT" -ge "$RAM_THRESHOLD_PERCENT" ]; then
    TOP_RAM_PROCESS=$(ps -eo pid,cmd,%mem --sort=-%mem | head -n 4 | tail -n 3 | awk '{printf "PID %-7s RAM %-4s %s\n", $1, $3"%", $2}')
    RAM_DETAIL=$(free -h | grep Mem | awk '{printf "Dùng %s / Tổng %s (%s)", $3, $2, "'"$RAM_USAGE_PCT"'%"}')
    
    TELE_ALERT_MSG+="⚠️ <b>RAM HỆ THỐNG TĂNG CAO: ${RAM_USAGE_PCT}%</b> (Ngưỡng: ${RAM_THRESHOLD_PERCENT}%)
<b>Chi tiết RAM:</b> <code>$RAM_DETAIL</code>"

    LARK_ALERT_MSG+="⚠️ **RAM HỆ THỐNG TĂNG CAO: ${RAM_USAGE_PCT}%** (Ngưỡng: ${RAM_THRESHOLD_PERCENT}%)\n"
    LARK_ALERT_MSG+="* Chi tiết bộ nhớ: \`$RAM_DETAIL\`\n"

    SWAP_TOTAL=$(free | grep Swap | awk '{print $2}')
    if [ "$SWAP_TOTAL" -gt 0 ]; then
        SWAP_USAGE_PCT=$(free | grep Swap | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
        SWAP_DETAIL=$(free -h | grep Swap | awk '{printf "Dùng %s / Tổng %s (%s)", $3, $2, "'"$SWAP_USAGE_PCT"'%"}')
        TELE_ALERT_MSG+="\n<b>Bộ nhớ ảo SWAP:</b> <code>$SWAP_DETAIL</code>"
        LARK_ALERT_MSG+="* Bộ nhớ ảo SWAP: \`$SWAP_DETAIL\`\n"
    fi

    TELE_ALERT_MSG+="\n<pre>Top tiến trình ngốn RAM nhất:
$TOP_RAM_PROCESS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="*Top tiến trình chiếm dụng:*\n"
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n'"$TOP_RAM_PROCESS"
    LARK_ALERT_MSG+=$'\n'
    LARK_ALERT_MSG+='```'
    LARK_ALERT_MSG+=$'\n\n'
fi

# 1.2 Kiểm tra CPU và Load Average
CPU_USAGE_PCT=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | cut -d. -f1)
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1" "$2" "$3}')
CPU_CORES=$(nproc)
LOAD_1M=$(cat /proc/loadavg | awk '{print $1}' | cut -d. -f1)

if [ "$CPU_USAGE_PCT" -ge "$CPU_THRESHOLD_PERCENT" ] || [ "$LOAD_1M" -ge "$CPU_CORES" ]; then
    TOP_CPU_PROCESS=$(ps -eo pid,cmd,%cpu --sort=-%cpu | head -n 4 | tail -n 3 | awk '{printf "PID %-7s CPU %-4s %s\n", $1, $3"%", $2}')

    TELE_ALERT_MSG+="🔥 <b>CPU/TẢI HỆ THỐNG QUÁ TẢI: CPU ${CPU_USAGE_PCT}%</b>
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

# 1.3 Kiểm tra Ổ cứng (Disk)
DISK_USAGE_PCT=$(df -h / | grep / | awk '{print $5}' | cut -d% -f1)
if [ "$DISK_USAGE_PCT" -ge "$DISK_THRESHOLD_PERCENT" ]; then
    DISK_DETAIL=$(df -h / | tail -n 1 | awk '{printf "Tổng: %s - Đã dùng: %s - Trống: %s", $2, $3, $4}')

    TELE_ALERT_MSG+="💾 <b>Ổ CỨNG HỆ THỐNG SẮP ĐẦY: ${DISK_USAGE_PCT}%</b> (Ngưỡng: ${DISK_THRESHOLD_PERCENT}%)
<code>$DISK_DETAIL</code>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="💾 **Ổ CỨNG HỆ THỐNG SẮP ĐẦY: ${DISK_USAGE_PCT}%** (Ngưỡng: ${DISK_THRESHOLD_PERCENT}%)\n*Chi tiết:* \`$DISK_DETAIL\`\n\n"
fi

# 1.4 Cảnh báo Băng thông Mạng đột biến
if (( $(echo "$RX_SPEED_MB $NET_SPEED_THRESHOLD_MB" | awk '{print ($1 >= $2)}') )) || (( $(echo "$TX_SPEED_MB $NET_SPEED_THRESHOLD_MB" | awk '{print ($1 >= $2)}') )); then
    NET_DETAIL="Tải xuống (Download): ${RX_SPEED_MB} MB/s | Tải lên (Upload): ${TX_SPEED_MB} MB/s"

    TELE_ALERT_MSG+="🌐 <b>TRAFFIC BĂNG THÔNG MẠNG TĂNG ĐỘT BIẾN:</b>
<code>$NET_DETAIL</code> (Card mạng: $NET_INTERFACE)
━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="🌐 **TRAFFIC BĂNG THÔNG MẠNG TĂNG ĐỘT BIẾN:**\n*Chi tiết:* \`$NET_DETAIL\` (Card mạng: $NET_INTERFACE)\n\n"
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
# 2. KIỂM TRA BẢO MẬT & TƯỜNG LỬA (MỚI - TỪ SECURITY AUDIT)
# ------------------------------------------------------------------------------
SEC_TELE=""
SEC_LARK=""

# 2.1 Kiểm tra trạng thái Firewall
FIREWALL_OK=true
if command -v ufw &>/dev/null; then
    if ! ufw status | grep -q "Status: active"; then
        FIREWALL_OK=false
        SEC_TELE+="🔴 <b>Tường lửa UFW Firewall đang bị TẮT (INACTIVE)</b>\n"
        SEC_LARK+="* Tường lửa UFW Firewall đang bị 🔴 **TẮT (INACTIVE)**\n"
    fi
fi

# 2.2 Kiểm tra SSH cấu hình mặc định nguy hiểm
sshd_config="/etc/ssh/sshd_config"
if [ -f "$sshd_config" ]; then
    ssh_port=$(grep -E "^#?Port " "$sshd_config" | awk '{print $2}' | tail -n 1)
    [ -z "$ssh_port" ] && ssh_port="22"
    
    permit_root=$(grep -E "^#?PermitRootLogin " "$sshd_config" | awk '{print $2}' | tail -n 1)
    [ -z "$permit_root" ] && permit_root="yes"
    
    if [ "$ssh_port" = "22" ]; then
        SEC_TELE+="⚠️ Cổng SSH đang mở ở cổng mặc định <b>22</b> (Dễ bị brute-force)\n"
        SEC_LARK+="* Cổng SSH đang mở ở cổng mặc định **22** (Nguy cơ bị brute-force cao)\n"
    fi
    
    if [ "$permit_root" = "yes" ]; then
        SEC_TELE+="🔴 Cho phép root đăng nhập trực tiếp qua SSH mật khẩu!\n"
        SEC_LARK+="* Cho phép root đăng nhập trực tiếp qua 🔴 **SSH mật khẩu (Cực kỳ nguy hiểm)**\n"
    fi
fi

# 2.3 Quét lỗi leo thang quyền NOPASSWD trong Sudoers
if [ -f /etc/sudoers ]; then
    # Lọc trừ ra deployer hợp pháp
    nopasswd_users=$(grep -r -i "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^#' | grep -v "deployer" || true)
    if [ -n "$nopasswd_users" ]; then
        SEC_TELE+="🔴 <b>Phát hiện tài khoản NOPASSWD lạ trong Sudoers:</b>\n<pre>$nopasswd_users</pre>\n"
        SEC_LARK+="* Phát hiện tài khoản leo thang quyền 🔴 **NOPASSWD lạ trong Sudoers**:\n\`\`\`\n$nopasswd_users\n\`\`\`\n"
    fi
fi

if [ -n "$SEC_TELE" ]; then
    TELE_ALERT_MSG+="🛡️ <b>CẢNH BÁO LỖ HỔNG AN NINH & TƯỜNG LỬA:</b>
$SEC_TELE━━━━━━━━━━━━━━━━━━━━━━━━\n"

    LARK_ALERT_MSG+="🛡️ **CẢNH BÁO LỖ HỔNG AN NINH & TƯỜNG LỬA:**\n$SEC_LARK\n"
fi

# ------------------------------------------------------------------------------
# 3. PHÁT HIỆN TẤN CÔNG DÒ MẬT KHẨU BRUTE-FORCE SSH (MỚI - TỪ SECURITY AUDIT)
# ------------------------------------------------------------------------------
AUTH_LOG="/var/log/auth.log"
[ ! -f "$AUTH_LOG" ] && AUTH_LOG="/var/log/secure"

if [ -f "$AUTH_LOG" ]; then
    # Đếm số lần đăng nhập thất bại trong 30 phút qua
    CURRENT_TIME_EPOCH=$(date +%s)
    FAILED_ATTEMPTS=""
    FAILED_COUNT=0
    
    # Quét logs SSH thất bại gần nhất
    SSH_FAILS=$(grep -i "Failed password" "$AUTH_LOG" | tail -n 200 || true)
    
    while read -r line; do
        [ -z "$line" ] && continue
        log_date_str=$(echo "$line" | awk '{print $1" "$2" "$3}')
        log_epoch=$(date -d "$log_date_str" +%s 2>/dev/null)
        if [ -n "$log_epoch" ]; then
            diff=$((CURRENT_TIME_EPOCH - log_epoch))
            # Quét trong 30 phút qua (1800 giây)
            if [ "$diff" -ge 0 ] && [ "$diff" -le 1800 ]; then
                FAILED_ATTEMPTS+="$line\n"
                FAILED_COUNT=$((FAILED_COUNT + 1))
            fi
        fi
    done <<< "$SSH_FAILS"
    
    # Nếu số lần login lỗi vượt quá 30 lần trong 30 phút, phát cảnh báo tấn công dò mật khẩu
    if [ "$FAILED_COUNT" -ge 30 ]; then
        # Thống kê top 3 IP đang dò mật khẩu
        TOP_OFFENDERS=$(echo -e "$FAILED_ATTEMPTS" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort | uniq -c | sort -nr | head -n 3 | awk '{printf "IP %-15s : %s lần\n", $2, $1}')
        
        TELE_ALERT_MSG+="🕵️ <b>PHÁT HIỆN TẤN CÔNG DÒ MẬT KHẨU (BRUTE-FORCE):</b>
Tổng số lượt đăng nhập SSH thất bại trong 30 phút: <b>$FAILED_COUNT lần</b>
<pre>Top địa chỉ IP tấn công dồn dập nhất:
$TOP_OFFENDERS</pre>
━━━━━━━━━━━━━━━━━━━━━━━━\n"

        LARK_ALERT_MSG+="🕵️ **PHÁT HIỆN TẤN CÔNG DÒ MẬT KHẨU (BRUTE-FORCE):**\n"
        LARK_ALERT_MSG+="Tổng số lượt đăng nhập SSH thất bại trong 30 phút: **$FAILED_COUNT lần**\n"
        LARK_ALERT_MSG+="*Top địa chỉ IP tấn công dồn dập nhất:*\n"
        LARK_ALERT_MSG+='```'
        LARK_ALERT_MSG+=$'\n'"$TOP_OFFENDERS"
        LARK_ALERT_MSG+=$'\n'
        LARK_ALERT_MSG+='```'
        LARK_ALERT_MSG+=$'\n\n'
    fi
fi

# ------------------------------------------------------------------------------
# 4. PHÁT HIỆN AN NINH & CẢNH BÁO MALWARE (DỊCH CHUYỂN & NÂNG CẤP)
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
# 5. GIÁM SÁT SSH LOGINS (ĐĂNG NHẬP MỚI THÀNH CÔNG)
# ------------------------------------------------------------------------------
if [ "$ENABLE_SSH_MONITOR" = "true" ]; then
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
