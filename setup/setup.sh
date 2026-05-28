#!/bin/bash
# ==============================================================================
# Script Name   : setup.sh
# Description   : Automated Server Tool Installer (Node, NPM, Yarn, PM2, Docker, Nginx, Certbot)
# Author        : Antigravity AI
# Version       : 1.0.0
# Compatibility : Ubuntu, Debian
# Usage         : sudo bash setup.sh [tools_separated_by_comma]
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LOG_DIR="${SCRIPT_DIR}/setup_logs"
LOG_FILE="${LOG_DIR}/setup_$(date +%Y%m%d_%H%M%S).log"

# Initialization logging
setup_logging() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || LOG_FILE="/tmp/setup_$(date +%Y%m%d_%H%M%S).log"
    fi
    echo -e "${BLUE}=== VPS Server Setup Log initialized at $(date) ===${NC}" > "$LOG_FILE"
}

# Print headers to both screen and log file
log_section() {
    local title="$1"
    echo -e "\n${BOLD}${CYAN}======================================================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${WHITE}  ${title}${NC}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${CYAN}======================================================================${NC}" | tee -a "$LOG_FILE"
}

log_message() {
    local level="$1" # SUCCESS, FAIL, WARN, INFO, PLAIN
    local msg="$2"
    case "$level" in
        "SUCCESS") echo -e "${TICK} ${msg}" | tee -a "$LOG_FILE" ;;
        "FAIL")    echo -e "${CROSS} ${RED}${msg}${NC}" | tee -a "$LOG_FILE" ;;
        "WARN")    echo -e "${WARN} ${YELLOW}${msg}${NC}" | tee -a "$LOG_FILE" ;;
        "INFO")    echo -e "${INFO} ${msg}" | tee -a "$LOG_FILE" ;;
        *)         echo -e "${msg}" | tee -a "$LOG_FILE" ;;
    esac
}

# Ensure script is run with root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}${BOLD}Lỗi:${NC} Script này phải được chạy với quyền ${BOLD}root${NC} (hoặc sử dụng sudo)."
        exit 1
    fi
}

# Check OS compatibility (Debian/Ubuntu focus)
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            log_message "WARN" "Script này được tối ưu hóa cho Ubuntu và Debian. Hệ điều hành hiện tại của bạn là: $NAME. Một số lệnh cài đặt có thể không hoạt động chính xác."
            read -p "Bạn có muốn tiếp tục chạy không? (y/N): " choice
            case "$choice" in
                [yY][eE][sS]|[yY])
                    log_message "INFO" "Tiếp tục chạy trên hệ điều hành $NAME..."
                    ;;
                *)
                    log_message "FAIL" "Đã hủy cài đặt do không đúng hệ điều hành hỗ trợ."
                    exit 1
                    ;;
            esac
        fi
    else
        log_message "WARN" "Không thể xác định hệ điều hành. Có thể gặp lỗi trong quá trình cài đặt."
    fi
}

# Install Functions
install_node() {
    log_message "INFO" "Đang kiểm tra Node.js..."
    if command -v node &>/dev/null; then
        local version=$(node -v)
        log_message "SUCCESS" "Node.js đã được cài đặt sẵn (Phiên bản: $version)."
        return 0
    fi

    log_message "INFO" "Đang tiến hành cài đặt Node.js LTS (v20) từ NodeSource..."
    apt-get update -y >> "$LOG_FILE" 2>&1
    apt-get install -y curl ca-certificates gnupg >> "$LOG_FILE" 2>&1
    
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> "$LOG_FILE" 2>&1
    apt-get install -y nodejs >> "$LOG_FILE" 2>&1

    if command -v node &>/dev/null; then
        log_message "SUCCESS" "Cài đặt Node.js thành công! Phiên bản: $(node -v)"
        log_message "SUCCESS" "Cài đặt NPM thành công! Phiên bản: $(npm -v)"
        return 0
    else
        log_message "FAIL" "Cài đặt Node.js thất bại. Vui lòng kiểm tra file log: $LOG_FILE"
        return 1
    fi
}

install_npm() {
    log_message "INFO" "Đang kiểm tra NPM..."
    if command -v npm &>/dev/null; then
        local version=$(npm -v)
        log_message "SUCCESS" "NPM đã được cài đặt sẵn (Phiên bản: $version)."
        return 0
    fi

    # Nếu chưa có NPM nhưng có Node, ta sẽ thử cài NPM riêng lẻ, thông thường NPM đi kèm Node
    if command -v node &>/dev/null; then
        log_message "INFO" "Đang cài đặt NPM tương thích với Node.js hiện tại..."
        apt-get install -y npm >> "$LOG_FILE" 2>&1
    else
        log_message "WARN" "NPM yêu cầu Node.js. Đang tiến hành cài đặt Node.js..."
        install_node
    fi

    if command -v npm &>/dev/null; then
        log_message "SUCCESS" "Cài đặt NPM thành công! Phiên bản: $(npm -v)"
        return 0
    else
        log_message "FAIL" "Cài đặt NPM thất bại."
        return 1
    fi
}

install_yarn() {
    log_message "INFO" "Đang kiểm tra Yarn..."
    if command -v yarn &>/dev/null; then
        local version=$(yarn -v)
        log_message "SUCCESS" "Yarn đã được cài đặt sẵn (Phiên bản: $version)."
        return 0
    fi

    # Yêu cầu NPM
    if ! command -v npm &>/dev/null; then
        log_message "WARN" "Yarn yêu cầu NPM. Đang tiến hành cài đặt NPM/Node.js trước..."
        install_node
    fi

    log_message "INFO" "Đang cài đặt Yarn Corepack/Global..."
    npm install -g yarn >> "$LOG_FILE" 2>&1

    if command -v yarn &>/dev/null; then
        log_message "SUCCESS" "Cài đặt Yarn thành công! Phiên bản: $(yarn -v)"
        return 0
    else
        log_message "FAIL" "Cài đặt Yarn thất bại."
        return 1
    fi
}

install_pm2() {
    log_message "INFO" "Đang kiểm tra PM2..."
    if command -v pm2 &>/dev/null; then
        local version=$(pm2 -v)
        log_message "SUCCESS" "PM2 đã được cài đặt sẵn (Phiên bản: $version)."
        return 0
    fi

    # Yêu cầu NPM
    if ! command -v npm &>/dev/null; then
        log_message "WARN" "PM2 yêu cầu NPM. Đang tiến hành cài đặt NPM/Node.js trước..."
        install_node
    fi

    log_message "INFO" "Đang cài đặt PM2 toàn cục thông qua NPM..."
    npm install -g pm2 >> "$LOG_FILE" 2>&1

    if command -v pm2 &>/dev/null; then
        # Thiết lập khởi động cùng hệ thống
        pm2 startup systemd -u root --hp /root >> "$LOG_FILE" 2>&1
        log_message "SUCCESS" "Cài đặt PM2 thành công! Phiên bản: $(pm2 -v)"
        return 0
    else
        log_message "FAIL" "Cài đặt PM2 thất bại."
        return 1
    fi
}

install_docker() {
    log_message "INFO" "Đang kiểm tra Docker..."
    if command -v docker &>/dev/null; then
        local version=$(docker -v)
        log_message "SUCCESS" "Docker đã được cài đặt sẵn (Phiên bản: $version)."
        return 0
    fi

    log_message "INFO" "Đang cài đặt Docker Engine sử dụng script chính thức từ Docker..."
    apt-get update -y >> "$LOG_FILE" 2>&1
    apt-get install -y curl >> "$LOG_FILE" 2>&1
    
    curl -fsSL https://get.docker.com -o get-docker.sh >> "$LOG_FILE" 2>&1
    sh get-docker.sh >> "$LOG_FILE" 2>&1
    rm -f get-docker.sh

    # Khởi chạy và kích hoạt Docker service
    systemctl start docker >> "$LOG_FILE" 2>&1
    systemctl enable docker >> "$LOG_FILE" 2>&1

    if command -v docker &>/dev/null; then
        log_message "SUCCESS" "Cài đặt Docker thành công! Phiên bản: $(docker -v)"
        return 0
    else
        log_message "FAIL" "Cài đặt Docker thất bại."
        return 1
    fi
}

install_docker_compose() {
    log_message "INFO" "Đang kiểm tra Docker Compose..."
    if docker compose version &>/dev/null; then
        local version=$(docker compose version)
        log_message "SUCCESS" "Docker Compose đã được cài đặt sẵn (Phiên bản: $version)."
        return 0
    fi

    # Đảm bảo đã có Docker trước
    if ! command -v docker &>/dev/null; then
        log_message "WARN" "Docker Compose yêu cầu Docker. Đang tiến hành cài đặt Docker..."
        install_docker
    fi

    log_message "INFO" "Đang cài đặt Docker Compose Plugin..."
    apt-get update -y >> "$LOG_FILE" 2>&1
    apt-get install -y docker-compose-plugin >> "$LOG_FILE" 2>&1

    if docker compose version &>/dev/null; then
        log_message "SUCCESS" "Cài đặt Docker Compose thành công! Phiên bản: $(docker compose version)"
        return 0
    else
        log_message "FAIL" "Cài đặt Docker Compose thất bại."
        return 1
    fi
}

install_nginx() {
    log_message "INFO" "Đang kiểm tra Nginx..."
    if command -v nginx &>/dev/null; then
        local version=$(nginx -v 2>&1)
        log_message "SUCCESS" "Nginx đã được cài đặt sẵn (Phiên bản: $version)."
        return 0
    fi

    log_message "INFO" "Đang cài đặt Nginx từ kho apt..."
    apt-get update -y >> "$LOG_FILE" 2>&1
    apt-get install -y nginx >> "$LOG_FILE" 2>&1

    # Khởi động dịch vụ
    systemctl start nginx >> "$LOG_FILE" 2>&1
    systemctl enable nginx >> "$LOG_FILE" 2>&1

    if command -v nginx &>/dev/null; then
        log_message "SUCCESS" "Cài đặt Nginx thành công! Phiên bản: $(nginx -v 2>&1)"
        return 0
    else
        log_message "FAIL" "Cài đặt Nginx thất bại."
        return 1
    fi
}

install_certbot() {
    log_message "INFO" "Đang kiểm tra Certbot..."
    if command -v certbot &>/dev/null; then
        local version=$(certbot --version)
        log_message "SUCCESS" "Certbot đã được cài đặt sẵn (Phiên bản: $version)."
        return 0
    fi

    log_message "INFO" "Đang cài đặt Certbot và plugin Nginx..."
    apt-get update -y >> "$LOG_FILE" 2>&1
    apt-get install -y certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1

    if command -v certbot &>/dev/null; then
        log_message "SUCCESS" "Cài đặt Certbot thành công! Phiên bản: $(certbot --version)"
        return 0
    else
        log_message "FAIL" "Cài đặt Certbot thất bại."
        return 1
    fi
}

# Main Interactive Tool Selector
interactive_tool_selection() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "========================================================================"
    echo "       🚀 HỆ THỐNG CÀI ĐẶT CÔNG CỤ VPS TỰ ĐỘNG - STAR-BASH 🚀           "
    echo "========================================================================"
    echo -e "${NC}"
    echo -e "Danh sách các công cụ có sẵn hỗ trợ cài đặt tự động:"
    echo -e "  - ${BOLD}node${NC}           : Node.js LTS v20 & NPM"
    echo -e "  - ${BOLD}npm${NC}            : Node Package Manager"
    echo -e "  - ${BOLD}yarn${NC}           : Yarn Package Manager"
    echo -e "  - ${BOLD}pm2${NC}            : Production Process Manager cho Node.js"
    echo -e "  - ${BOLD}docker${NC}         : Docker Container Engine"
    echo -e "  - ${BOLD}docker compose${NC} : Docker Compose Orchestration Tool"
    echo -e "  - ${BOLD}nginx${NC}          : Nginx High-Performance Web Server"
    echo -e "  - ${BOLD}certbot${NC}        : Let's Encrypt SSL Automated Client"
    echo -e "========================================================================"
    echo -e "${BOLD}${WHITE}👉 HƯỚNG DẪN NHẬP:${NC}"
    echo -e "Nhập danh sách các công cụ bạn muốn cài đặt, cách nhau bằng ${BOLD}dấu phẩy${NC}."
    echo -e "Ví dụ: ${YELLOW}node, pm2, docker, nginx${NC}"
    echo -e "Hoặc gõ ${BOLD}all${NC} để cài đặt tất cả các công cụ trên."
    echo -e "------------------------------------------------------------------------"
    
    local raw_input
    read -p "👉 Nhập danh sách công cụ: " raw_input
    
    if [ -z "$raw_input" ]; then
        log_message "WARN" "Đầu vào trống. Vui lòng chạy lại script và nhập công cụ."
        exit 0
    fi
    
    process_tools_list "$raw_input"
}

# Parse and normalize tools list
process_tools_list() {
    local input="$1"
    local normalized_tools=()
    
    # Thay thế dấu phẩy và khoảng trắng thành định dạng tiêu chuẩn
    # Sử dụng IFS để phân tách bằng dấu phẩy
    IFS=',' read -ra ADDR <<< "$input"
    for item in "${ADDR[@]}"; do
        # Trim khoảng trắng ở hai đầu và chuyển thành chữ thường
        local clean_item=$(echo "$item" | xargs | tr '[:upper:]' '[:lower:]')
        
        # Sửa lỗi chính tả hoặc chuẩn hóa các tên đồng nghĩa
        case "$clean_item" in
            "node"|"nodejs"|"node.js")
                normalized_tools+=("node")
                ;;
            "npm")
                normalized_tools+=("npm")
                ;;
            "yarn")
                normalized_tools+=("yarn")
                ;;
            "pm2")
                normalized_tools+=("pm2")
                ;;
            "docker")
                normalized_tools+=("docker")
                ;;
            "docker-compose"|"docker compose"|"dockercompose")
                normalized_tools+=("docker-compose")
                ;;
            "nginx")
                normalized_tools+=("nginx")
                ;;
            "certbot"|"cerbot") # Bắt lỗi gõ thiếu chữ t của cerbot
                normalized_tools+=("certbot")
                ;;
            "all")
                normalized_tools=("node" "npm" "yarn" "pm2" "docker" "docker-compose" "nginx" "certbot")
                break
                ;;
            "")
                # Bỏ qua phần tử trống
                ;;
            *)
                log_message "WARN" "Không nhận diện được công cụ: '$item'. Sẽ bỏ qua công cụ này."
                ;;
        esac
    done

    # Kiểm tra xem có công cụ hợp lệ nào không
    if [ ${#normalized_tools[@]} -eq 0 ]; then
        log_message "FAIL" "Không tìm thấy công cụ hợp lệ nào để cài đặt!"
        exit 1
    fi

    # Loại bỏ phần tử trùng lặp trong mảng
    local unique_tools=($(echo "${normalized_tools[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    log_section "TIẾN TRÌNH CÀI ĐẶT CÁC CÔNG CỤ ĐÃ CHỌN"
    log_message "INFO" "Danh sách cài đặt: ${unique_tools[*]}"
    echo -e "Bắt đầu cài đặt... Chi tiết quá trình được ghi tại: ${BOLD}${LOG_FILE}${NC}\n"

    local success_count=0
    local fail_count=0

    for tool in "${unique_tools[@]}"; do
        log_message "PLAIN" "\n----------------------------------------"
        case "$tool" in
            "node")
                install_node && ((success_count++)) || ((fail_count++))
                ;;
            "npm")
                install_npm && ((success_count++)) || ((fail_count++))
                ;;
            "yarn")
                install_yarn && ((success_count++)) || ((fail_count++))
                ;;
            "pm2")
                install_pm2 && ((success_count++)) || ((fail_count++))
                ;;
            "docker")
                install_docker && ((success_count++)) || ((fail_count++))
                ;;
            "docker-compose")
                install_docker_compose && ((success_count++)) || ((fail_count++))
                ;;
            "nginx")
                install_nginx && ((success_count++)) || ((fail_count++))
                ;;
            "certbot")
                install_certbot && ((success_count++)) || ((fail_count++))
                ;;
        esac
    done

    log_section "TỔNG KẾT QUÁ TRÌNH CÀI ĐẶT"
    log_message "INFO" "Hoàn thành xử lý cài đặt VPS Tools."
    log_message "SUCCESS" "Thành công / Đã có sẵn: $success_count"
    if [ $fail_count -gt 0 ]; then
        log_message "FAIL" "Thất bại: $fail_count (Xem chi tiết lỗi trong file: ${LOG_FILE})"
    else
        log_message "SUCCESS" "Tất cả công cụ hoạt động hoàn hảo!"
    fi
    echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
}

# Main Execution
main() {
    check_root
    setup_logging
    check_os

    # Nếu có tham số dòng lệnh truyền vào (ví dụ: sudo bash setup.sh node,pm2)
    if [ $# -gt 0 ]; then
        # Nối tất cả các tham số lại bằng dấu phẩy để xử lý thống nhất
        local combined_args=$(echo "$*" | tr ' ' ',')
        process_tools_list "$combined_args"
    else
        # Chạy ở chế độ tương tác nhập liệu
        interactive_tool_selection
    fi
}

main "$@"
