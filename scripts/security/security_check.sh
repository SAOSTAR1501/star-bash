#!/bin/bash
# ==============================================================================
# Script Name   : security_check.sh
# Description   : Advanced VPS Security Audit & System Monitoring Tool
# Author        : Antigravity AI
# Version       : 1.0.0
# Date          : 2026-05-26
# Compatibility : Ubuntu, Debian, CentOS, RHEL, AlmaLinux, Rocky Linux
# Usage         : sudo bash security_check.sh
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

# Log File Configuration
LOG_DIR="./security_logs"
LOG_FILE="${LOG_DIR}/security_report_$(date +%Y%m%d_%H%M%S).log"

# Initialization
setup_logging() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || LOG_FILE="./security_report_$(date +%Y%m%d_%H%M%S).log"
    fi
    echo -e "${BLUE}=== VPS Security Audit Log initialized at $(date) ===${NC}" > "$LOG_FILE"
}

# Print headers to both screen and log file
log_section() {
    local title="$1"
    echo -e "\n${BOLD}${CYAN}======================================================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${WHITE}  ${title}${NC}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${CYAN}======================================================================${NC}" | tee -a "$LOG_FILE"
}

log_message() {
    local level="$1" # TICK, CROSS, WARN, INFO
    local msg="$2"
    case "$level" in
        "SUCCESS") echo -e "${TICK} ${msg}" | tee -a "$LOG_FILE" ;;
        "FAIL")    echo -e "${CROSS} ${RED}${msg}${NC}" | tee -a "$LOG_FILE" ;;
        "WARN")    echo -e "${WARN} ${YELLOW}${msg}${NC}" | tee -a "$LOG_FILE" ;;
        "INFO")    echo -e "${INFO} ${msg}" | tee -a "$LOG_FILE" ;;
        *)         echo -e "${msg}" | tee -a "$LOG_FILE" ;;
    esac
}

# Ensure script is run with sudo/root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}${BOLD}Error:${NC} This script must be run as ${BOLD}root${NC} (or with sudo) to retrieve complete security details."
        echo -e "Some checks (like reading system logs, listening ports, rootkits) will fail or be incomplete without root privileges."
        read -p "Do you want to continue anyway? (y/N): " choice
        case "$choice" in
            [yY][eE][sS]|[yY])
                echo -e "${YELLOW}Proceeding without root privileges. Expect missing data.${NC}"
                ;;
            *)
                exit 1
                ;;
        esac
    fi
}

# ==============================================================================
# 1. SYSTEM & HARDWARE METRICS
# ==============================================================================
check_system_info() {
    log_section "1. SYSTEM & OPERATING SYSTEM INFORMATION"
    
    local os_name="Unknown"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_name="$PRETTY_NAME"
    fi
    
    local kernel_ver=$(uname -r)
    local uptime_info=$(uptime -p)
    local virtualization=$(systemd-detect-virt 2>/dev/null || echo "Unknown")
    
    log_message "INFO" "OS Name        : ${BOLD}${os_name}${NC}"
    log_message "INFO" "Kernel Version : ${BOLD}${kernel_ver}${NC}"
    log_message "INFO" "System Uptime  : ${BOLD}${uptime_info}${NC}"
    log_message "INFO" "Virtualization : ${BOLD}${virtualization}${NC}"
}

check_cpu_memory_disk() {
    log_section "2. CPU, MEMORY & DISK METRICS"
    
    # 2.1 CPU Check
    local cpu_cores=$(nproc)
    local load_avg=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/ //g')
    local load_1m=$(echo "$load_avg" | cut -d',' -f1)
    
    log_message "INFO" "CPU Cores      : ${BOLD}${cpu_cores}${NC}"
    log_message "INFO" "Load Average   : ${BOLD}${load_avg}${NC}"
    
    # Simple check if load is abnormal
    # If 1 min load is greater than CPU core count, flag a warning
    local load_1m_int=$(echo "$load_1m" | cut -d'.' -f1)
    if [ -n "$load_1m_int" ] && [ "$load_1m_int" -ge "$cpu_cores" ]; then
        log_message "WARN" "CPU load is extremely high! 1-min load average ($load_1m) exceeds core count ($cpu_cores)."
    else
        log_message "SUCCESS" "CPU Load is normal."
    fi
    
    # 2.2 Memory Check
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    local mem_used=$(free -m | awk '/^Mem:/{print $3}')
    local mem_pct=$(( mem_used * 100 / mem_total ))
    
    log_message "INFO" "Memory Usage   : ${BOLD}${mem_used}MB / ${mem_total}MB (${mem_pct}%)${NC}"
    if [ "$mem_pct" -gt 90 ]; then
        log_message "WARN" "Memory usage is above 90%! System might experience instability."
    else
        log_message "SUCCESS" "Memory usage is within safe limits."
    fi
    
    # 2.3 Disk Storage Check
    log_message "INFO" "Checking disk partition usage..."
    df -h | grep -E '^/dev/' | while read -r line; do
        local disk_name=$(echo "$line" | awk '{print $1}')
        local disk_usage=$(echo "$line" | awk '{print $5}' | cut -d'%' -f1)
        local mount_point=$(echo "$line" | awk '{print $6}')
        
        if [ "$disk_usage" -ge 85 ]; then
            log_message "WARN" "Partition ${disk_name} mounted on ${mount_point} is ${disk_usage}% full!"
        else
            log_message "SUCCESS" "Partition ${disk_name} (${mount_point}): ${disk_usage}% used."
        fi
    done
    
    # 2.4 Top 5 CPU Consuming Processes
    log_message "INFO" "Top 5 processes by CPU usage:"
    echo -e "${BOLD}%CPU   PID    COMMAND${NC}" | tee -a "$LOG_FILE"
    ps -eo %cpu,pid,comm --sort=-%cpu | head -n 6 | tail -n 5 | while read -r line; do
        echo -e "  $line" | tee -a "$LOG_FILE"
    done
    
    # 2.5 Top 5 Memory Consuming Processes
    log_message "INFO" "Top 5 processes by Memory usage:"
    echo -e "${BOLD}%MEM   PID    COMMAND${NC}" | tee -a "$LOG_FILE"
    ps -eo %mem,pid,comm --sort=-%mem | head -n 6 | tail -n 5 | while read -r line; do
        echo -e "  $line" | tee -a "$LOG_FILE"
    done
}

# ==============================================================================
# 2. NETWORK & PORT ANALYSIS
# ==============================================================================
check_network_ports() {
    log_section "3. NETWORK PORTS & SERVICE ANALYSIS"
    
    # Check what tool is available for port checking (ss is preferred)
    if command -v ss &>/dev/null; then
        log_message "INFO" "Active Listening Ports (TCP/UDP):"
        echo -e "${BOLD}Proto  Port      Process/Service Name${NC}" | tee -a "$LOG_FILE"
        
        ss -tulpn 2>/dev/null | grep LISTEN | while read -r line; do
            local proto=$(echo "$line" | awk '{print $1}')
            local local_addr=$(echo "$line" | awk '{print $5}')
            local port=$(echo "$local_addr" | awk -F':' '{print $NF}')
            local process=$(echo "$line" | awk '{print $7}' | sed -e 's/"//g' -e 's/users:(//g' -e 's/)//g')
            
            # Format and print
            printf "  %-5s  %-8s  %s\n" "$proto" "$port" "$process" | tee -a "$LOG_FILE"
        done
    elif command -v netstat &>/dev/null; then
        log_message "INFO" "Active Listening Ports (TCP/UDP):"
        netstat -tulpn 2>/dev/null | grep LISTEN | tee -a "$LOG_FILE"
    else
        log_message "WARN" "Neither 'ss' nor 'netstat' is available. Skipping port details."
    fi
    
    # Firewall Verification
    log_message "INFO" "Checking Firewall Status..."
    if command -v ufw &>/dev/null; then
        local ufw_status=$(ufw status | head -n 1)
        if echo "$ufw_status" | grep -q "active"; then
            log_message "SUCCESS" "UFW Firewall is ${GREEN}ACTIVE${NC}."
        else
            log_message "WARN" "UFW Firewall is ${RED}INACTIVE${NC}!"
        fi
    elif command -v firewall-cmd &>/dev/null; then
        if systemctl is-active --quiet firewalld; then
            log_message "SUCCESS" "Firewalld is ${GREEN}ACTIVE${NC}."
        else
            log_message "WARN" "Firewalld is ${RED}INACTIVE${NC}!"
        fi
    elif command -v iptables &>/dev/null; then
        local rules_count=$(iptables -S | wc -l)
        if [ "$rules_count" -gt 3 ]; then
            log_message "SUCCESS" "iptables rules detected ($rules_count active rules)."
        else
            log_message "WARN" "iptables seems to have default policy (no custom rules configured)!"
        fi
    else
        log_message "FAIL" "No standard firewall tool (UFW, Firewalld, iptables) detected!"
    fi

    # Auditing DOCKER-USER chain in iptables to prevent accidental port blocking
    if command -v iptables &>/dev/null; then
        if iptables -L DOCKER-USER -n &>/dev/null; then
            local docker_user_rules; docker_user_rules=$(iptables -S DOCKER-USER 2>/dev/null)
            local drop_rules_count; drop_rules_count=$(echo "$docker_user_rules" | grep -c "DROP" || echo "0")
            if [ "$drop_rules_count" -gt 0 ]; then
                log_message "WARN" "Phát hiện chuỗi DOCKER-USER chứa $drop_rules_count luật chặn (DROP)."
                # Check if port 80 and 443 are explicitly allowed before the DROP rules
                local accept_80; accept_80=$(echo "$docker_user_rules" | grep -E "ACCEPT" | grep -c "dport 80" || echo "0")
                local accept_443; accept_443=$(echo "$docker_user_rules" | grep -E "ACCEPT" | grep -c "dport 443" || echo "0")
                if [ "$accept_80" -eq 0 ] || [ "$accept_443" -eq 0 ]; then
                    log_message "FAIL" "CẢNH BÁO: DOCKER-USER có luật DROP nhưng CHƯA mở cổng HTTP/HTTPS (Port 80/443)! Điều này có thể làm ngắt kết nối của các dịch vụ công cộng chạy bằng Docker như Traefik/Nginx."
                else
                    log_message "SUCCESS" "DOCKER-USER có luật DROP nhưng đã mở cổng 80 & 443 an toàn."
                fi
            fi
        fi
    fi
}

# ==============================================================================
# 3. SSH & USER AUTHENTICATION SECURITY
# ==============================================================================
check_ssh_security() {
    log_section "4. SSH & SYSTEM AUTHENTICATION SECURITY"
    
    local sshd_config="/etc/ssh/sshd_config"
    
    if [ ! -f "$sshd_config" ]; then
        log_message "FAIL" "SSH Configuration file not found at $sshd_config!"
        return 1
    fi
    
    # 3.1 Fetch critical SSH configurations
    local port=$(grep -E "^#?Port " "$sshd_config" | awk '{print $2}' | tail -n 1)
    [ -z "$port" ] && port="22" # Default SSH Port
    
    local permit_root=$(grep -E "^#?PermitRootLogin " "$sshd_config" | awk '{print $2}' | tail -n 1)
    [ -z "$permit_root" ] && permit_root="yes (default)"
    
    local password_auth=$(grep -E "^#?PasswordAuthentication " "$sshd_config" | awk '{print $2}' | tail -n 1)
    [ -z "$password_auth" ] && password_auth="yes (default)"
    
    local pubkey_auth=$(grep -E "^#?PubkeyAuthentication " "$sshd_config" | awk '{print $2}' | tail -n 1)
    [ -z "$pubkey_auth" ] && pubkey_auth="yes (default)"
    
    log_message "INFO" "SSH Port                 : ${BOLD}${port}${NC}"
    log_message "INFO" "Permit Root Login        : ${BOLD}${permit_root}${NC}"
    log_message "INFO" "Password Authentication  : ${BOLD}${password_auth}${NC}"
    log_message "INFO" "Public Key Authentication: ${BOLD}${pubkey_auth}${NC}"
    
    # Analyze and advise
    if [ "$port" == "22" ]; then
        log_message "WARN" "SSH runs on default port 22. Consider changing it to reduce automated brute-force attacks."
    else
        log_message "SUCCESS" "SSH runs on a non-standard port ($port)."
    fi
    
    if [[ "$permit_root" =~ ^(yes|prohibit-password|without-password) ]]; then
        if [ "$permit_root" == "yes" ]; then
            log_message "WARN" "Direct root SSH logins are ${RED}ALLOWED${NC}. Highly recommended to disable root logins and use sudo."
        else
            log_message "INFO" "Root login allowed only with SSH keys ($permit_root)."
        fi
    else
        log_message "SUCCESS" "Direct root login is disabled."
    fi
    
    if [[ "$password_auth" =~ ^(yes) ]]; then
        log_message "WARN" "Password Authentication is ${RED}ENABLED${NC}. It is safer to use SSH Key-based authentication only."
    fi
}

check_user_logins() {
    log_message "INFO" "Active Logged-in Users:"
    who | tee -a "$LOG_FILE"
    
    log_message "INFO" "Checking recently logged-in accounts..."
    last -n 5 | grep -v '^$' | head -n 5 | tee -a "$LOG_FILE"
    
    # 3.2 Failed Login Attempts (Brute force warning)
    log_message "INFO" "Auditing Failed SSH Login Attempts..."
    local auth_log=""
    
    if [ -f /var/log/auth.log ]; then
        auth_log="/var/log/auth.log" # Debian/Ubuntu
    elif [ -f /var/log/secure ]; then
        auth_log="/var/log/secure" # CentOS/RHEL/RHEL derivatives
    fi
    
    if [ -n "$auth_log" ]; then
        local failed_count=$(grep -i "Failed password" "$auth_log" 2>/dev/null | wc -l)
        log_message "INFO" "Total failed login attempts in active logs: ${BOLD}${failed_count}${NC}"
        
        if [ "$failed_count" -gt 100 ]; then
            log_message "WARN" "High volume of failed SSH logins detected (${failed_count} attempts). System might be under brute force attack!"
            
            # Show top 5 offending IPs
            log_message "INFO" "Top 5 IPs responsible for failed SSH attempts:"
            grep -i "Failed password" "$auth_log" 2>/dev/null | \
                grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
                sort | uniq -c | sort -nr | head -n 5 | while read -r count ip; do
                    echo -e "  - ${RED}${ip}${NC} : ${count} times" | tee -a "$LOG_FILE"
                done
        else
            log_message "SUCCESS" "No critical level of SSH brute-force attempts detected."
        fi
    else
        log_message "WARN" "Security logs not accessible or empty. Cannot check failed SSH login counts."
    fi
}

# ==============================================================================
# 4. MALWARE & SUSPICIOUS BEHAVIOR CHECKS
# ==============================================================================
check_malware_indicators() {
    log_section "5. MALWARE & SUSPICIOUS BEHAVIOR SCAN"
    
    # 4.1 Processes running from temp/shared memory (common malware drop zones)
    log_message "INFO" "Scanning for processes executing from writable directories (/tmp, /dev/shm, /var/tmp)..."
    local suspicious_procs=$(ps -eo pid,cmd | grep -E '(/tmp/|/dev/shm/|/var/tmp/)' | grep -v grep)
    
    if [ -n "$suspicious_procs" ]; then
        log_message "FAIL" "Suspicious processes found running from writable paths!"
        echo -e "${RED}${suspicious_procs}${NC}" | tee -a "$LOG_FILE"
    else
        log_message "SUCCESS" "No active processes executing from /tmp, /dev/shm, or /var/tmp."
    fi
    
    # 4.2 Check for typical cryptominers
    log_message "INFO" "Checking for common cryptominer signatures (xmrig, minerd, cpuminer, etc.)..."
    local miner_sigs="xmrig|minerd|cpuminer|cryptonight|stratum|nanopool|ethermine|nicehash"
    local active_miners=$(ps -eo pid,comm,cmd | grep -Ei "$miner_sigs" | grep -v grep)
    
    if [ -n "$active_miners" ]; then
        log_message "FAIL" "WARNING: Potential Cryptocurrency Miner processes detected!"
        echo -e "${RED}${active_miners}${NC}" | tee -a "$LOG_FILE"
    else
        log_message "SUCCESS" "No active cryptocurrency miner signatures detected."
    fi
    
    # 4.3 Check for deleted files held open by running processes (often hidden malware or active log-tampering)
    log_message "INFO" "Scanning for large deleted files held open by active processes..."
    if command -v lsof &>/dev/null; then
        local deleted_files=$(lsof +L1 2>/dev/null | grep -i 'deleted' | head -n 10)
        if [ -n "$deleted_files" ]; then
            log_message "WARN" "Some deleted files are still active in memory (potential trace wiping/hidden runs):"
            echo -e "${YELLOW}${deleted_files}${NC}" | tee -a "$LOG_FILE"
        else
            log_message "SUCCESS" "No abnormal deleted-but-open files detected."
        fi
    else
        log_message "INFO" "'lsof' tool not installed. Skipping deleted files scan."
    fi

    # 4.4 Check if common Linux protection tools are installed
    log_message "INFO" "Checking availability of recommended security tools:"
    for tool in "rkhunter" "chkrootkit" "clamav" "fail2ban"; do
        if command -v "$tool" &>/dev/null || systemctl is-active --quiet "$tool" 2>/dev/null; then
            log_message "SUCCESS" "Security Tool [${tool}] is installed / active."
        else
            log_message "WARN" "Security Tool [${tool}] is NOT installed. Consider installing for enhanced protection."
        fi
    done
}

# ==============================================================================
# 5. PERSISTENCE & CRON JOBS
# ==============================================================================
check_persistence() {
    log_section "6. PERSISTENCE MECHANISMS (CRON & SERVICES)"
    
    # 5.1 System-wide Cron Jobs
    log_message "INFO" "Checking system-wide cron folders for active scripts..."
    local system_crons=$(ls -la /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly /etc/crontab 2>/dev/null | grep -vE '^total|^d' | awk '{print $9}' | grep -v '^$' | wc -l)
    log_message "INFO" "Found ${system_crons} system cron configurations."
    
    # 5.2 User Crontabs
    log_message "INFO" "Auditing cron jobs configured for system users..."
    local cron_users=""
    while IFS=: read -r user _ _ _ _ _ shell; do
        # Only check users with valid logins to avoid massive overhead
        if [[ "$shell" =~ /bin/(bash|sh|zsh) ]]; then
            local user_cron=$(crontab -u "$user" -l 2>/dev/null | grep -v '^#')
            if [ -n "$user_cron" ]; then
                log_message "WARN" "Active crontab found for user: ${BOLD}${user}${NC}"
                echo -e "${YELLOW}${user_cron}${NC}" | tee -a "$LOG_FILE"
                cron_users="${cron_users}${user} "
            fi
        fi
    done < /etc/passwd
    
    if [ -z "$cron_users" ]; then
        log_message "SUCCESS" "No hidden cron-based persistence found in user environments."
    fi
    
    # 5.3 Shell RC Files Modifications
    log_message "INFO" "Scanning for abnormal executable shell injections in root files..."
    if [ -f /root/.bashrc ]; then
        local root_rc_web=$(grep -E "(curl|wget|bash -i|/dev/tcp)" /root/.bashrc)
        if [ -n "$root_rc_web" ]; then
            log_message "WARN" "Suspicious web commands or shells detected in /root/.bashrc:"
            echo -e "${RED}${root_rc_web}${NC}" | tee -a "$LOG_FILE"
        fi
    fi
}

# ==============================================================================
# 6. SYSTEM INTEGRITY & PRIVILEGE ELEVATION
# ==============================================================================
check_system_integrity() {
    log_section "7. PRIVILEGE ESCALATION & SYSTEM INTEGRITY"
    
    # 6.1 World-writable files in system binary folders
    log_message "INFO" "Scanning critical system binary folders (/bin, /sbin, /usr/bin, /usr/sbin) for world-writable files..."
    local ww_files=$(find /bin /sbin /usr/bin /usr/sbin -perm -0002 -type f 2>/dev/null)
    if [ -n "$ww_files" ]; then
        log_message "FAIL" "World-writable system binaries detected! Severe security risk."
        echo -e "${RED}${ww_files}${NC}" | tee -a "$LOG_FILE"
    else
        log_message "SUCCESS" "No world-writable binaries found in system directories."
    fi
    
    # 6.2 Check for passwordless sudo accounts
    log_message "INFO" "Scanning sudoers file for accounts that can execute root actions without password..."
    if [ -f /etc/sudoers ]; then
        local nopasswd_users=$(grep -r -i "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^#')
        if [ -n "$nopasswd_users" ]; then
            log_message "WARN" "Accounts with NOPASSWD privileges detected (highly vulnerable to rapid privilege escalation):"
            echo -e "${YELLOW}${nopasswd_users}${NC}" | tee -a "$LOG_FILE"
        else
            log_message "SUCCESS" "No passwordless sudo vulnerabilities found in default configurations."
        fi
    else
        log_message "WARN" "Cannot read /etc/sudoers configuration files."
    fi
}

# ==============================================================================
# REMEDIATION & HARDENING ACTIONS
# ==============================================================================

remediate_fail2ban() {
    echo -e "\n${BOLD}${YELLOW}--- TỰ ĐỘNG CÀI ĐẶT & KÍCH HOẠT FAIL2BAN ---${NC}"
    if command -v apt-get &>/dev/null; then
        echo -e "${INFO} Đang cập nhật gói và cài đặt fail2ban bằng apt..."
        apt-get update -y && apt-get install fail2ban -y
    elif command -v yum &>/dev/null; then
        echo -e "${INFO} Đang cài đặt fail2ban bằng yum..."
        yum install epel-release -y && yum install fail2ban -y
    else
        echo -e "${CROSS} Không tìm thấy trình quản lý gói phù hợp (apt/yum)!"
        return 1
    fi
    
    # Enable and start service
    echo -e "${INFO} Đang cấu hình tự động kích hoạt dịch vụ Fail2Ban..."
    systemctl enable fail2ban &>/dev/null
    systemctl restart fail2ban &>/dev/null
    
    if systemctl is-active --quiet fail2ban; then
        echo -e "${TICK} ${GREEN}Fail2Ban đã được cài đặt và kích hoạt thành công!${NC}"
        echo -e "${INFO} Trạng thái dịch vụ SSH Jail:"
        fail2ban-client status sshd 2>/dev/null || fail2ban-client status
    else
        echo -e "${CROSS} Cài đặt thành công nhưng Fail2Ban không thể khởi chạy. Vui lòng kiểm tra lại log."
    fi
}

remediate_ssh() {
    echo -e "\n${BOLD}${YELLOW}--- THIẾT LẬP CỔNG SSH MỚI & BẢO MẬT ĐĂNG NHẬP ---${NC}"
    echo -e "${WARN} LƯU Ý: Thay đổi cổng SSH có thể khóa bạn khỏi VPS nếu tường lửa chặn cổng mới."
    echo -e "Chúng tôi sẽ tự động mở cổng mới trên UFW cho bạn trước khi khởi động lại dịch vụ SSH."
    echo -e ""
    read -p "Nhập cổng SSH mới muốn đổi (từ 1024 - 65535, ấn Enter để bỏ qua đổi cổng): " new_port
    
    if [ -z "$new_port" ]; then
        echo -e "${WARN} Bỏ qua đổi cổng SSH. Giữ nguyên cổng hiện tại."
        new_port="22"
    else
        # Validate port number
        if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1024 ] || [ "$new_port" -gt 65535 ]; then
            echo -e "${CROSS} Cổng không hợp lệ! Vui lòng chọn cổng số từ 1024 đến 65535."
            return 1
        fi
    fi
    
    # Back up config
    local ssh_conf="/etc/ssh/sshd_config"
    if [ ! -f "$ssh_conf" ]; then
        echo -e "${CROSS} Không tìm thấy file cấu hình SSH tại $ssh_conf!"
        return 1
    fi
    
    local backup_file="${ssh_conf}.bak_$(date +%Y%m%d_%H%M%S)"
    cp "$ssh_conf" "$backup_file"
    echo -e "${INFO} Đã tạo bản sao lưu cấu hình SSH tại: ${backup_file}"
    
    # UFW Configuration
    if command -v ufw &>/dev/null; then
        if ufw status | grep -q "Status: active"; then
            echo -e "${INFO} Đang mở cổng ${new_port}/tcp trên tường lửa UFW..."
            ufw allow "$new_port"/tcp
            ufw reload
        fi
    fi
    
    # Modify sshd_config
    if [ "$new_port" != "22" ]; then
        # Check if Port exists, if so change it, otherwise append
        if grep -qE "^#?Port " "$ssh_conf"; then
            sed -i "s/^#\?Port .*/Port $new_port/" "$ssh_conf"
        else
            echo "Port $new_port" >> "$ssh_conf"
        fi
        echo -e "${TICK} Đã đổi cấu hình Port thành ${new_port}"
    fi
    
    # Disable PasswordAuthentication
    if grep -qE "^#?PasswordAuthentication " "$ssh_conf"; then
        sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication no/" "$ssh_conf"
    else
        echo "PasswordAuthentication no" >> "$ssh_conf"
    fi
    echo -e "${TICK} Đã cấu hình PasswordAuthentication thành no (Chỉ dùng SSH Key)"
    
    # Disable direct root password login but keep keys (prohibit-password)
    if grep -qE "^#?PermitRootLogin " "$ssh_conf"; then
        sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/" "$ssh_conf"
    else
        echo "PermitRootLogin prohibit-password" >> "$ssh_conf"
    fi
    echo -e "${TICK} Đã cấu hình PermitRootLogin thành prohibit-password"
    
    # Test SSH config validity before restarting
    if sshd -t; then
        echo -e "${INFO} Cấu hình hợp lệ. Đang khởi động lại dịch vụ SSH..."
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
        echo -e "${TICK} ${GREEN}Thiết lập bảo mật SSH thành công!${NC}"
        echo -e "${BOLD}${RED}⚠️ CHÚ Ý CỰC KỲ QUAN TRỌNG:${NC}"
        echo -e " 1. ${BOLD}KHÔNG ĐƯỢC TẮT PHIÊN KẾT NỐI HIỆN TẠI!${NC}"
        echo -e " 2. Hãy mở một cửa sổ terminal mới trên máy tính của bạn và thử kết nối qua lệnh:"
        echo -e "    ${BOLD}ssh -p $new_port root@<IP_CUA_BAN>${NC}"
        echo -e " 3. Chỉ đóng cửa sổ này khi bạn chắc chắn đã kết nối thành công ở cửa sổ mới."
    else
        echo -e "${CROSS} Phát hiện lỗi cú pháp trong cấu hình SSH mới! Đang khôi phục lại từ bản sao lưu..."
        cp "$backup_file" "$ssh_conf"
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
        echo -e "${WARN} Đã khôi phục cấu hình an toàn cũ."
    fi
}

remediate_docker_info() {
    local docker_opt
    while true; do
        clear
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e "${BOLD}${WHITE}       🐳 QUẢN TRỊ & BẢO MẬT CỔNG CONTAINER DOCKER (DOCKER-USER)      ${NC}"
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e " [1] 📋 Xem các quy tắc DOCKER-USER hiện có trong iptables"
        echo -e " [2] 🔓 Mở cổng 80 & 443 cho Traefik/Web (Sửa lỗi Let's Encrypt Timeout)"
        echo -e " [3] 🔓 Mở một cổng tùy chỉnh tự chọn (Ví dụ: 3002)"
        echo -e " [4] ❌ Xóa bỏ luật chặn chung chung (-i eth0 -j DROP) khỏi DOCKER-USER"
        echo -e " [5] 📖 Xem hướng dẫn bảo mật cổng Docker (Docker-UFW bypass)"
        echo -e " [0] Quay lại Menu bảo mật"
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        read -p "👉 Nhập lựa chọn quản trị Docker Firewall [0-5]: " docker_opt
        
        case "$docker_opt" in
            0|"") return 0 ;;
            1)
                echo -e "\n📋 Các quy tắc trong chuỗi DOCKER-USER hiện tại:"
                echo -e "--------------------------------------------------------"
                if iptables -L DOCKER-USER -n -v &>/dev/null; then
                    iptables -L DOCKER-USER -n -v
                else
                    echo -e "${FAIL} Không thể đọc chuỗi DOCKER-USER. Có thể Docker chưa chạy hoặc không có quyền root."
                fi
                echo -e "--------------------------------------------------------"
                ;;
            2)
                echo -e "\n🔓 Đang chèn luật cho phép cổng 80 (HTTP) và 443 (HTTPS) vào chuỗi DOCKER-USER..."
                if sudo iptables -I DOCKER-USER 1 -i eth0 -p tcp --dport 80 -j ACCEPT 2>/dev/null && \
                   sudo iptables -I DOCKER-USER 1 -i eth0 -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
                    echo -e "${TICK} ${GREEN}Đã mở cổng 80 & 443 thành công trên DOCKER-USER!${NC}"
                else
                    echo -e "${CROSS} Thực thi thất bại. Vui lòng kiểm tra quyền sudo/root."
                fi
                ;;
            3)
                echo -e ""
                read -p "👉 Nhập số cổng muốn mở rộng (Ví dụ: 3002): " custom_port
                if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1 ] && [ "$custom_port" -le 65535 ]; then
                    echo -e "\n🔓 Đang chèn luật cho phép cổng $custom_port vào chuỗi DOCKER-USER..."
                    if sudo iptables -I DOCKER-USER 1 -i eth0 -p tcp --dport "$custom_port" -j ACCEPT 2>/dev/null; then
                        echo -e "${TICK} ${GREEN}Đã mở cổng $custom_port thành công trên DOCKER-USER!${NC}"
                    else
                        echo -e "${CROSS} Thực thi thất bại. Vui lòng kiểm tra quyền sudo/root."
                    fi
                else
                    echo -e "${CROSS} Số cổng không hợp lệ!"
                fi
                ;;
            4)
                echo -e "\n❌ Đang tiến hành xóa các quy tắc chặn chung (-i eth0 -j DROP) khỏi DOCKER-USER..."
                local deleted=0
                while sudo iptables -D DOCKER-USER -i eth0 -j DROP 2>/dev/null; do
                    deleted=$((deleted + 1))
                done
                if [ "$deleted" -gt 0 ]; then
                    echo -e "${TICK} ${GREEN}Đã xóa thành công $deleted quy tắc DROP trên eth0!${NC}"
                else
                    echo -e "${WARN} Không tìm thấy quy tắc DROP nào phù hợp để xóa."
                fi
                ;;
            5)
                clear
                echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
                echo -e "${BOLD}${WHITE}       🐳 HƯỚNG DẪN BẢO MẬT CỔNG CONTAINER DOCKER (DOCKER-UFW BYPASS)  ${NC}"
                echo -e "${BOLD}${CYAN}========================================================================${NC}"
                echo -e "${YELLOW}Cảnh báo:${NC} Mặc định, Docker tự thêm rules vào iptables và bypass hoàn toàn tường lửa UFW."
                echo -e "Điều này có nghĩa là nếu bạn mở cổng dịch vụ dạng ${BOLD}-p 5432:5432${NC}, bất kỳ ai cũng truy cập được cổng này."
                echo -e ""
                echo -e "${BOLD}${GREEN}Giải pháp 1: Chỉ cho phép kết nối nội bộ (Khuyên dùng)${NC}"
                echo -e "Nếu PostgreSQL hoặc dịch vụ chỉ dùng cho các container khác kết nối nội bộ, hãy:"
                echo -e " - ${BOLD}Xóa hoàn toàn${NC} phần 'ports:' khỏi file ${BOLD}docker-compose.yml${NC}."
                echo -e " - Sử dụng cơ chế Docker Network để các container tự liên lạc nội bộ với nhau."
                echo -e ""
                echo -e "${BOLD}${GREEN}Giải pháp 2: Chỉ bind cổng vào localhost (127.0.0.1)${NC}"
                echo -e "Nếu cần truy cập cổng này từ máy cá nhân thông qua SSH Tunneling:"
                echo -e " - Trong file ${BOLD}docker-compose.yml${NC}, hãy đổi cấu hình port thành:"
                echo -e "   ${BOLD}ports:${NC}"
                echo -e "     ${BOLD}- \"127.0.0.1:5432:5432\"${NC}"
                echo -e " - Đối với dòng lệnh chạy container đơn lẻ, dùng:"
                echo -e "   ${BOLD}docker run -p 127.0.0.1:5432:5432 postgres${NC}"
                echo -e ""
                echo -e "${BOLD}${GREEN}Giải pháp 3: Sử dụng ufw-docker (Cấp cao)${NC}"
                echo -e "Nếu bắt buộc phải mở cổng công khai nhưng muốn UFW kiểm soát:"
                echo -e " - Xem thêm hướng dẫn tích hợp tại: https://github.com/chaifeng/ufw-docker"
                echo -e "${BOLD}${CYAN}========================================================================${NC}"
                ;;
        esac
        echo -e "\n${INFO} Nhấn Enter để tiếp tục..."
        read -r temp
    done
}

remediate_security_tools() {
    echo -e "\n${BOLD}${YELLOW}--- CÀI ĐẶT CÁC CÔNG CỤ QUÉT BẢO MẬT CHUYÊN SÂU ---${NC}"
    if command -v apt-get &>/dev/null; then
        echo -e "${INFO} Đang cài đặt rkhunter, chkrootkit, clamav bằng apt..."
        apt-get update -y && apt-get install rkhunter chkrootkit clamav clamav-daemon -y
    elif command -v yum &>/dev/null; then
        echo -e "${INFO} Đang cài đặt rkhunter, chkrootkit, clamav bằng yum..."
        yum install epel-release -y && yum install rkhunter chkrootkit clamav clamav-update -y
    else
        echo -e "${CROSS} Không tìm thấy trình quản lý gói phù hợp (apt/yum)!"
        return 1
    fi
    echo -e "${TICK} ${GREEN}Đã cài đặt thành công rkhunter, chkrootkit, clamav!${NC}"
    echo -e "${INFO} Các lệnh quét bạn có thể chạy thủ công sau này:"
    echo -e "  - Quét rootkit 1: ${BOLD}sudo chkrootkit${NC}"
    echo -e "  - Quét rootkit 2: ${BOLD}sudo rkhunter --check${NC}"
    echo -e "  - Quét virus:    ${BOLD}sudo clamscan -r /path/to/scan${NC}"
}

remediate_reboot() {
    echo -e "\n${BOLD}${RED}--- KHỞI ĐỘNG LẠI VPS (REBOOT) ---${NC}"
    echo -e "${WARN} LƯU Ý: Khởi động lại VPS sẽ ngắt kết nối SSH hiện tại của bạn trong vài phút."
    read -p "Bạn có chắc chắn muốn reboot VPS ngay bây giờ không? (y/N): " confirm
    case "$confirm" in
        [yY][eE][sS]|[yY])
            echo -e "${INFO} Hệ thống đang khởi động lại. Kết nối của bạn sẽ bị ngắt..."
            sleep 2
            reboot
            ;;
        *)
            echo -e "${WARN} Đã hủy yêu cầu khởi động lại."
            ;;
    esac
}

interactive_menu() {
    local choice
    while true; do
        echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
        echo -e "${BOLD}${WHITE}       🛡️  HỆ THỐNG GỢI Ý HÀNH ĐỘNG CẬP NHẬT BẢO MẬT (REMEDIATION)  🛡️${NC}"
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e " [1] 🚀 ${BOLD}Cài đặt và Kích hoạt Fail2Ban${NC} (Chặn IP brute-force SSH ngay lập tức)"
        echo -e " [2] 🔑 ${BOLD}Đổi cổng SSH & Tắt đăng nhập mật khẩu${NC} (Chống quét port 22 và dò pass)"
        echo -e " [3] 🐳 ${BOLD}Xem hướng dẫn bảo mật cổng Docker${NC} (Ngăn chặn bypass tường lửa UFW)"
        echo -e " [4] 🪲 ${BOLD}Cài đặt bộ công cụ quét bảo mật${NC} (rkhunter, chkrootkit, clamav)"
        echo -e " [5] 🔄 ${BOLD}Khởi động lại VPS (Reboot)${NC} (Áp dụng các bản vá nhân/tiến trình mới)"
        echo -e " [0] 🚪 ${BOLD}Thoát khỏi chương trình${NC}"
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        read -p "Vui lòng nhập lựa chọn hành động [0-5]: " choice
        
        case "$choice" in
            1) remediate_fail2ban ;;
            2) remediate_ssh ;;
            3) remediate_docker_info ;;
            4) remediate_security_tools ;;
            5) remediate_reboot ;;
            0) echo -e "\n${BOLD}${GREEN}Cảm ơn bạn đã sử dụng Star-Bash Security Tool. Hẹn gặp lại!${NC}\n"; exit 0 ;;
            *) echo -e "${CROSS} Lựa chọn không hợp lệ. Vui lòng nhập từ 0 đến 5." ;;
        esac
        echo -e "\n${INFO} Nhấn Enter để tiếp tục quay lại Menu..."
        read -r temp
    done
}

# ==============================================================================
# MAIN EXECUTION FLOW
# ==============================================================================
main() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "========================================================================"
    echo "       🌟 STAR-BASH VPS SECURITY AUDIT & HEALTHCHECK TOOL 🌟            "
    echo "========================================================================"
    echo -e "${NC}"
    
    setup_logging
    check_root
    
    log_message "INFO" "Beginning audit scan..."
    
    # Run Checks
    check_system_info
    check_cpu_memory_disk
    check_network_ports
    check_ssh_security
    check_user_logins
    check_malware_indicators
    check_persistence
    check_system_integrity
    
    log_section "AUDIT SUMMARY & RECOMMENDATIONS"
    log_message "INFO" "Security audit completed successfully."
    log_message "INFO" "Full audit logs have been compiled into: ${BOLD}${LOG_FILE}${NC}"
    echo -e "\n${BOLD}${GREEN}Recommended Next Steps:${NC}"
    echo -e " 1. If SSH default port 22 is still active, change it in /etc/ssh/sshd_config."
    echo -e " 2. Enable key-based authentication and set 'PasswordAuthentication no' to prevent brute force attacks."
    echo -e " 3. Install fail2ban to automatically block brute-force IP addresses."
    echo -e " 4. Regularly inspect processes with high CPU loads (possible hidden miners)."
    echo -e " 5. Keep the system kernel updated to patch against recent privilege escalation exploits."
    echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
    
    # Start Interactive Hardening Menu
    interactive_menu
}

main "$@"
