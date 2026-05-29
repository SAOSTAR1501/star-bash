#!/bin/bash
# ==============================================================================
# Script Name   : setup_gitlab_runner.sh
# Description   : Secure, Non-root GitLab Runner Auto-Installer & Hardener
# Author        : Antigravity AI & User
# Version       : 1.2.0
# Compatibility : Ubuntu, Debian
# Usage         : sudo bash setup_gitlab_runner.sh
# ==============================================================================

set -euo pipefail

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

RUNNER_USER="gitlab-runner"
RUNNER_HOME="/home/${RUNNER_USER}"
SERVICE_FILE="/etc/systemd/system/gitlab-runner.service"

# Trạng thái tổng kết các hạng mục công việc
STATUS_CLEANUP="${WARN} Chưa thực hiện"
STATUS_USER="${WARN} Chưa thực hiện"
STATUS_ENGINE="${WARN} Chưa cài đặt"
STATUS_DOCKER="${WARN} Chưa kiểm tra"
STATUS_SYSTEMD="${WARN} Chưa cấu hình"
STATUS_PERM="${WARN} Chưa phân quyền"
STATUS_SERVICE="${WARN} Chưa khởi chạy"
STATUS_REGISTER="${WARN} Bỏ qua (Đăng ký thủ công)"
STATUS_CRON="${WARN} Bỏ qua"

# Ensure script is run with root privileges to perform installations and systemctl changes
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}Lỗi:${NC} Script setup hệ thống này phải được chạy với quyền ${BOLD}root${NC} (hoặc sử dụng sudo)."
    exit 1
fi

clear
echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "       🦊 SETUP GITLAB RUNNER AN TOÀN - KHÔNG ROOT (NON-ROOT) 🦊        "
echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "${INFO} Đang khởi động quy trình thiết lập chuẩn bảo mật nâng cao..."

echo -e "\n${BOLD}${WHITE}==> 1. Stop và gỡ service gitlab-runner cũ nếu có${NC}"
if systemctl is-active --quiet gitlab-runner 2>/dev/null; then
    echo -e "${INFO} Đang dừng dịch vụ gitlab-runner..."
    systemctl stop gitlab-runner 2>/dev/null || true
fi
if command -v gitlab-runner &> /dev/null; then
    echo -e "${INFO} Đang gỡ bỏ service gitlab-runner hiện tại..."
    gitlab-runner uninstall 2>/dev/null || true
fi
echo -e "${TICK} Hoàn tất dừng và gỡ dịch vụ cũ."
STATUS_CLEANUP="${TICK} Hoàn tất gỡ cũ"

echo -e "\n${BOLD}${WHITE}==> 2. Xóa user gitlab-runner cũ để setup lại từ đầu${NC}"
if id "${RUNNER_USER}" &>/dev/null; then
    echo -e "${WARN} Phát hiện user '${RUNNER_USER}' đã tồn tại. Tiến hành dọn dẹp để cài mới..."
    userdel -f -r ${RUNNER_USER} 2>/dev/null || echo "    User dọn dẹp một phần."
    groupdel ${RUNNER_USER} 2>/dev/null || true
    echo -e "${TICK} Đã xóa user và thư mục home cũ."
else
    echo -e "${INFO} Thư mục/User sạch, sẵn sàng tạo mới."
fi

echo -e "\n${BOLD}${WHITE}==> 3. Cài đặt GitLab Runner chính thức nếu chưa có${NC}"
if ! command -v gitlab-runner &> /dev/null; then
    echo -e "${INFO} GitLab Runner chưa được cài đặt trên hệ thống."
    
    echo -e "${INFO} Đang dọn dẹp và sửa chữa các gói cài đặt bị lỗi trên hệ thống (nếu có)..."
    dpkg --configure -a || true
    apt-get install -f -y || true

    echo -e "${INFO} Đang cài đặt các gói phụ trợ cần thiết (curl, ca-certificates, gnupg, apt-transport-https)..."
    apt-get update -y &>/dev/null || true
    apt-get install -y curl ca-certificates gnupg apt-transport-https &>/dev/null || true

    echo -e "${INFO} Đang thêm cấu hình kho lưu trữ GitLab Runner thủ công (sử dụng bản phân phối jammy tương thích)..."
    # Tải và cấu hình GPG Key chính thức của GitLab
    curl -sS -L "https://packages.gitlab.com/gpg.key" 2>/dev/null | gpg --dearmor --yes -o /usr/share/keyrings/gitlab-runner-archive-keyring.gpg || true
    
    # Tạo cấu hình kho lưu trữ sử dụng jammy (tương thích hoàn toàn 100% với noble/Ubuntu 24.04)
    echo "deb [signed-by=/usr/share/keyrings/gitlab-runner-archive-keyring.gpg] https://packages.gitlab.com/runner/gitlab-runner/ubuntu/ jammy main" > /etc/apt/sources.list.d/runner_gitlab-runner.list
    echo "deb-src [signed-by=/usr/share/keyrings/gitlab-runner-archive-keyring.gpg] https://packages.gitlab.com/runner/gitlab-runner/ubuntu/ jammy main" >> /etc/apt/sources.list.d/runner_gitlab-runner.list

    echo -e "${INFO} Đang cập nhật danh sách gói và cài đặt gitlab-runner qua apt..."
    apt-get update -y || true
    if ! apt-get install -y gitlab-runner; then
        echo -e "${WARN} Cài đặt qua apt-get thất bại."
        echo -e "${INFO} Đang tiến hành tải trực tiếp gói cài đặt .deb chính thức từ GitLab..."
        
        # Xác định kiến trúc máy chủ (mặc định x86_64/amd64 hoặc arm64)
        arch=$(uname -m)
        pkg_arch="amd64"
        if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
            pkg_arch="arm64"
        fi
        
        echo -e "${INFO} Tải tệp tin gitlab-runner_${pkg_arch}.deb..."
        curl -L -o "gitlab-runner_${pkg_arch}.deb" "https://gitlab-runner-downloads.s3.amazonaws.com/latest/deb/gitlab-runner_${pkg_arch}.deb" || true
        
        if [ -f "gitlab-runner_${pkg_arch}.deb" ]; then
            echo -e "${INFO} Đang cài đặt tệp .deb qua dpkg..."
            # Tự động bỏ qua lỗi dependency nếu có để ép dpkg cài đặt, sau đó sửa chữa
            dpkg -i --force-depends "gitlab-runner_${pkg_arch}.deb" || true
            apt-get install -f -y || true
            rm -f "gitlab-runner_${pkg_arch}.deb"
        fi
    fi
    
    if command -v gitlab-runner &> /dev/null; then
        echo -e "${TICK} ${GREEN}Cài đặt thành công GitLab Runner!${NC}"
    else
        echo -e "${CROSS} Cài đặt GitLab Runner thất bại hoàn toàn!"
        exit 1
    fi
else
    echo -e "${TICK} GitLab Runner đã được cài đặt sẵn: ${BOLD}$(gitlab-runner --version | head -n 1)${NC}"
fi
STATUS_ENGINE="${TICK} $(gitlab-runner --version | head -n 1 | awk '{print $1,$2}')"

echo -e "\n${BOLD}${WHITE}==> 4. Kiểm tra Docker Engine${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${WARN} ${YELLOW}Docker chưa được cài đặt trên hệ thống!${NC}"
    read -p "👉 Bạn có muốn tự động cài đặt Docker Engine chính thức ngay bây giờ không? (Y/n): " install_dk
    install_dk=${install_dk:-"y"}
    
    if [[ "$install_dk" =~ ^[yY] ]]; then
        echo -e "${INFO} Đang chuẩn bị gói hệ thống và cài đặt Docker Engine chính thức..."
        apt-get update -y
        apt-get install -y curl ca-certificates
        
        # Tải và chạy script cài đặt Docker chính thức từ get.docker.com
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm -f get-docker.sh
        
        # Khởi chạy và kích hoạt Docker service cùng hệ thống
        systemctl start docker
        systemctl enable docker
        
        if command -v docker &> /dev/null; then
            echo -e "${TICK} ${GREEN}Cài đặt Docker Engine thành công!${NC}"
            echo -e "${TICK} Docker đang hoạt động: ${BOLD}$(docker --version)${NC}"
        else
            echo -e "${CROSS} ${RED}LỖI: Cài đặt Docker Engine thất bại! Vui lòng kiểm tra lại hệ thống.${NC}"
            exit 1
        fi
    else
        echo -e "${CROSS} ${RED}LỖI: Trình đăng ký GitLab Runner Docker executor bắt buộc phải có Docker Engine!${NC}"
        exit 1
    fi
else
    echo -e "${TICK} Docker đã có sẵn và đang hoạt động: ${BOLD}$(docker --version)${NC}"
fi
STATUS_DOCKER="${TICK} $(docker --version | head -n 1 | awk '{print $3}' | tr -d ',')"

echo -e "\n${BOLD}${WHITE}==> 5. Tạo lại user gitlab-runner mới (Không Sudo, có Group Docker)${NC}"
useradd --comment 'GitLab Runner' --create-home --shell /bin/bash ${RUNNER_USER}
usermod -aG docker ${RUNNER_USER}
echo -e "${TICK} Đã tạo tài khoản hệ thống an toàn thành công."
echo -e "    Chi tiết User: ${BOLD}$(id ${RUNNER_USER})${NC}"
STATUS_USER="${TICK} gitlab-runner (Không sudo)"

echo -e "\n${BOLD}${WHITE}==> 6. Cài lại service runner với đúng user không root${NC}"
gitlab-runner install --user=${RUNNER_USER} --working-directory=${RUNNER_HOME}
echo -e "${TICK} Đã đăng ký service gitlab-runner dưới quyền user '${RUNNER_USER}'."

echo -e "\n${BOLD}${WHITE}==> 7. Khắc phục lỗi GitLab 18.11.3 (Thêm User & Group vào Systemd Service)${NC}"
if [ -f "${SERVICE_FILE}" ]; then
    if ! grep -q "User=${RUNNER_USER}" "${SERVICE_FILE}"; then
        # Thêm User và Group ngay dưới tag [Service]
        sed -i "/\[Service\]/a User=${RUNNER_USER}\nGroup=${RUNNER_USER}" "${SERVICE_FILE}"
        echo -e "${TICK} Đã tiêm cấu hình bảo mật User/Group vào ${SERVICE_FILE}"
    else
        echo -e "${INFO} File service đã chứa cấu hình User=, bỏ qua."
    fi
else
    echo -e "${CROSS} ${RED}Không tìm thấy file systemd service tại ${SERVICE_FILE}!${NC}"
    exit 1
fi
STATUS_SYSTEMD="${TICK} User/Group Sandbox"

echo -e "\n${BOLD}${WHITE}==> 8. Cấu hình phân quyền nghiêm ngặt bảo vệ thông tin nhạy cảm${NC}"
mkdir -p /etc/gitlab-runner
chown -R ${RUNNER_USER}:${RUNNER_USER} /etc/gitlab-runner
chown -R ${RUNNER_USER}:${RUNNER_USER} ${RUNNER_HOME}
chmod 750 /etc/gitlab-runner
chmod 640 /etc/gitlab-runner/config.toml 2>/dev/null || true
chmod 750 ${RUNNER_HOME}
echo -e "${TICK} Phân quyền thư mục cấu hình: ${BOLD}$(stat -c '%U:%G %a' /etc/gitlab-runner)${NC}"
echo -e "${TICK} Phân quyền thư mục Home       : ${BOLD}$(stat -c '%U:%G %a' ${RUNNER_HOME})${NC}"
STATUS_PERM="${TICK} Thư mục 750 / File 640"

echo -e "\n${BOLD}${WHITE}==> 9. Khởi động dịch vụ và kiểm tra trạng thái${NC}"
systemctl daemon-reload
systemctl enable gitlab-runner
systemctl start gitlab-runner
sleep 2
echo -e "${TICK} Dịch vụ GitLab Runner đã được tải lại và khởi chạy."
STATUS_SERVICE="${TICK} Active (running)"

echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
echo -e "                       KẾT QUẢ XÁC MINH HỆ THỐNG                         "
echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "${BOLD}--- Tài khoản hệ thống (User/Group) ---${NC}"
id ${RUNNER_USER}

echo -e "\n${BOLD}--- Tiến trình dịch vụ (Process check) ---${NC}"
if ps -o user:32,pid,cmd -C gitlab-runner --no-headers | grep -q "^${RUNNER_USER}"; then
    echo -e "${TICK} ${GREEN}XÁC NHẬN AN TOÀN: Dịch vụ chạy dưới quyền user '${RUNNER_USER}'!${NC}"
    ps -o user:32,pid,cmd -C gitlab-runner --no-headers
else
    echo -e "${CROSS} ${RED}NGUY HIỂM: Tiến trình runner vẫn đang chạy dưới quyền root!${NC}"
    ps -o user:32,pid,cmd -C gitlab-runner --no-headers
    exit 1
fi

echo -e "\n${BOLD}--- Trạng thái Service ---${NC}"
systemctl status gitlab-runner --no-pager -l | head -n 5

echo -e "\n${BOLD}--- File cấu hình config.toml ---${NC}"
if [ -f "/etc/gitlab-runner/config.toml" ]; then
    ls -l /etc/gitlab-runner/config.toml
else
    echo -e "${WARN} Chưa tạo file config.toml. Cần thực hiện bước đăng ký (Register) dưới đây."
fi

echo -e "\n${BOLD}${GREEN}========================================================================${NC}"
echo -e "           HOÀN TẤT THIẾT LẬP BẢO MẬT GITLAB RUNNER ✅                  "
echo -e "${BOLD}${GREEN}========================================================================${NC}"
echo -e "Hệ thống đã sẵn sàng và chạy an toàn (Non-Root) dưới tài khoản '${BOLD}${RUNNER_USER}${NC}'."
echo -e ""
echo -e "${BOLD}${YELLOW}📌 CÁC BƯỚC TIẾP THEO DÀNH CHO ADMIN:${NC}"
echo -e ""
echo -e " 1. ${BOLD}Đăng ký (Register) Runner với GitLab Server:${NC}
    Sử dụng lệnh sau để đăng ký trực tiếp bằng quyền hạn an toàn:
    ${BOLD}sudo gitlab-runner register \\
      --url <YOUR_GITLAB_URL> \\
      --registration-token <YOUR_REGISTRATION_TOKEN> \\
      --executor docker \\
      --description \"Secure VPS Runner\" \\
      --docker-image \"alpine:latest\"${NC}"
echo -e ""
echo -e " 2. ${BOLD}Kiểm tra danh sách Runner đã đăng ký:${NC}"
echo -e "    Chạy lệnh: ${BOLD}sudo gitlab-runner list${NC}"
echo -e ""
echo -e " 3. ${BOLD}Cấu hình .gitlab-ci.yml an toàn tối đa:${NC}"
echo -e "    - Sử dụng giao thức ${BOLD}SSH deploy${NC} để đẩy code lên môi trường production."
echo -e "    - ${RED}TUYỆT ĐỐI KHÔNG${NC} mount thư mục root của VPS hoặc docker.sock vào container CI nếu không cần thiết."
echo -e ""
echo -e " 4. ${BOLD}Khởi tạo tài khoản Deployer hạn chế quyền:${NC}"
echo -e "    - Tạo một user dành riêng cho deploy (ví dụ: 'deployer') trên VPS."
echo -e "    - Add SSH key của GitLab CI vào file authorized_keys của user này."
echo -e "    - Phân quyền sudo hạn chế chỉ cho lệnh restart service hoặc docker deploy cụ thể."
echo -e ""
echo -e "${RED}⚠️  CẢNH BÁO BẢO MẬT:${NC}"
echo -e " ${BOLD}KHÔNG BAO GIỜ${NC} thêm user '${RUNNER_USER}' vào nhóm '${RED}root${NC}' hoặc '${RED}sudo${NC}'."
echo -e " Việc này sẽ làm vô hiệu hóa toàn bộ cơ chế bảo mật sandbox mà chúng ta vừa xây dựng."
echo -e "${BOLD}${GREEN}========================================================================${NC}\n"

# ==============================================================================
# HỖ TRỢ ĐĂNG KÝ (REGISTER) RUNNER TƯƠNG TÁC
# ==============================================================================
echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "                 🦊 TRÌNH HỖ TRỢ ĐĂNG KÝ (REGISTER) RUNNER 🦊          "
echo -e "${BOLD}${CYAN}========================================================================${NC}"
read -p "👉 Bạn có muốn tiến hành đăng ký một Runner mới ngay bây giờ không? (y/N): " run_register

case "$run_register" in
    [yY][eE][sS]|[yY])
        echo -e "\n${INFO} Bắt đầu hướng dẫn đăng ký Runner (Mặc định sử dụng Executor: docker)..."
        
        # 1. Hỏi dọn dẹp runner chết
        read -p "❓ Bạn có muốn tự động quét và xóa các runner cũ không còn hoạt động (verify --delete)? (Y/n): " clean_old
        clean_old=${clean_old:-"y"}
        if [[ "$clean_old" =~ ^[yY] ]]; then
            echo -e "${INFO} Đang dọn dẹp các runner lỗi..."
            gitlab-runner verify --delete 2>/dev/null || true
        fi
        
        # 2. Nhập GitLab URL
        gitlab_url=""
        while [ -z "$gitlab_url" ]; do
            read -p "👉 Nhập GitLab Instance URL (Ví dụ: https://gitlab.com): " gitlab_url
            if [ -z "$gitlab_url" ]; then
                echo -e "${CROSS} ${RED}URL không được để trống!${NC}"
            fi
        done
        
        # 3. Nhập Token
        gitlab_token=""
        while [ -z "$gitlab_token" ]; do
            read -p "👉 Nhập GitLab Registration/Runner Token: " gitlab_token
            if [ -z "$gitlab_token" ]; then
                echo -e "${CROSS} ${RED}Token không được để trống!${NC}"
            fi
        done
        
        # 4. Nhập Tags
        read -p "👉 Nhập Tags cho Runner (cách nhau bởi dấu phẩy, ví dụ: fe,prod. Ấn Enter để bỏ qua): " runner_tags
        
        # 5. Nhập Description
        default_desc="Secure Docker Runner on $(hostname)"
        read -p "👉 Nhập mô tả Runner (Ấn Enter để lấy mặc định: '$default_desc'): " runner_desc
        runner_desc=${runner_desc:-"$default_desc"}
        
        # 6. Mặc định Image cho Docker executor
        default_image="alpine:latest"
        read -p "👉 Nhập Docker image mặc định (Ấn Enter để lấy mặc định: '$default_image'): " docker_image
        docker_image=${docker_image:-"$default_image"}
        
        # 7. Tiến hành đăng ký
        echo -e "\n${INFO} Đang thực hiện đăng ký với GitLab Server ở chế độ System-mode..."
        
        tag_param=""
        if [ -n "$runner_tags" ]; then
            tag_param="--tag-list $runner_tags"
        fi
        
        # Đăng ký ở mức hệ thống ghi trực tiếp vào /etc/gitlab-runner/config.toml
        if gitlab-runner register \
            --non-interactive \
            --config "/etc/gitlab-runner/config.toml" \
            --url "$gitlab_url" \
            --registration-token "$gitlab_token" \
            --executor "docker" \
            --description "$runner_desc" \
            --docker-image "$docker_image" \
            $tag_param; then
            
            echo -e "\n${TICK} ${GREEN}ĐĂNG KÝ RUNNER TRÊN HỆ THỐNG THÀNH CÔNG!${NC}"
            STATUS_REGISTER="${TICK} Đã kết nối ($runner_desc)"
            
            # Cấu hình lại phân quyền tệp tin cấu hình cho đúng user gitlab-runner
            echo -e "${INFO} Thiết lập phân quyền bảo mật cho tệp tin cấu hình..."
            chown -R ${RUNNER_USER}:${RUNNER_USER} /etc/gitlab-runner
            chmod 640 /etc/gitlab-runner/config.toml
            
            # Khởi động lại service để nạp cấu hình mới nhất
            echo -e "${INFO} Khởi động lại dịch vụ gitlab-runner..."
            systemctl restart gitlab-runner
            sleep 2
            
            # Kiểm tra xác thực (Verify) Runner với server GitLab
            echo -e "\n${INFO} Đang tiến hành kiểm tra xác thực (Verify) các Runner..."
            gitlab-runner verify
            
            echo -e "\n${TICK} ${GREEN}Danh sách các Runner đang hoạt động tốt trên hệ thống:${NC}"
            gitlab-runner list
        else
            echo -e "\n${CROSS} ${RED}Đăng ký thất bại! Vui lòng kiểm tra lại URL, Token hoặc kết nối mạng.${NC}"
            STATUS_REGISTER="${CROSS} Thất bại"
        fi
        ;;
    *)
        echo -e "\n${INFO} Đã bỏ qua đăng ký. Bạn có thể tự thực hiện đăng ký thủ công sau này."
        ;;
esac

# ==============================================================================
# HỖ TRỢ CÀI ĐẶT CRONTAB DỌN DẸP DOCKER TỰ ĐỘNG
# ==============================================================================
echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
echo -e "         🐳 THIẾT LẬP CRONJOB DỌN DẸP DOCKER DƯ THỪA TỰ ĐỘNG 🐳        "
echo -e "${BOLD}${CYAN}========================================================================${NC}"
read -p "👉 Bạn có muốn tự động lên lịch dọn dẹp Docker tạm thời hàng ngày không? (y/N): " run_cron

case "$run_cron" in
    [yY][eE][sS]|[yY])
        cron_hour=""
        while true; do
            read -p "👉 Nhập giờ chạy hàng ngày (Số từ 0 - 23, ví dụ: 3 tương đương 3 giờ sáng): " cron_hour
            if [[ "$cron_hour" =~ ^[0-9]+$ ]] && [ "$cron_hour" -ge 0 ] && [ "$cron_hour" -le 23 ]; then
                break
            else
                echo -e "${CROSS} ${RED}Giờ không hợp lệ! Vui lòng nhập số từ 0 đến 23.${NC}"
            fi
        done
        
        echo -e "${INFO} Đang cấu hình và lưu cronjob dọn dẹp..."
        
        # Tạm thời tắt set -e để tránh lỗi thoát do grep hoặc crontab rỗng
        set +e
        
        # Lấy các cronjob hiện tại và loại bỏ dòng dọn dẹp docker cũ (nếu có)
        current_cron=""
        if crontab -l &>/dev/null; then
            current_cron=$(crontab -l 2>/dev/null | grep -v "docker system prune -f --volumes")
        fi
        
        # Tạo file cấu hình tạm
        temp_cron_file=$(mktemp)
        if [ -n "$current_cron" ]; then
            echo "$current_cron" > "$temp_cron_file"
        fi
        # Thêm dòng cronjob mới
        echo "0 $cron_hour * * * docker system prune -f --volumes >/dev/null 2>&1" >> "$temp_cron_file"
        
        # Cập nhật lại crontab hệ thống
        crontab "$temp_cron_file"
        rm -f "$temp_cron_file"
        
        # Bật lại set -e
        set -e
        STATUS_CRON="${TICK} Hoạt động (${cron_hour}:00 hàng ngày)"
        
        echo -e "\n${TICK} ${GREEN}THIẾT LẬP CRONJOB THÀNH CÔNG!${NC}"
        echo -e "${INFO} Lịch dọn dẹp Docker dư thừa đã cấu hình chạy lúc ${BOLD}${cron_hour}:00${NC} hàng ngày."
        echo -e "    Chi tiết Crontab hiện tại của root:"
        crontab -l | grep "docker system prune"
        ;;
    *)
        echo -e "${INFO} Bỏ qua thiết lập Cronjob dọn dẹp Docker."
        ;;
esac

# ==============================================================================
# BẢNG TỔNG HỢP & TRẠNG THÁI THIẾT LẬP CUỐI CÙNG (PREMIUM DASHBOARD)
# ==============================================================================
echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
echo -e "             📋 BẢNG TỔNG HỢP & TRẠNG THÁI THIẾT LẬP 📋                 "
echo -e "${BOLD}${CYAN}========================================================================${NC}"
printf "  ${BOLD}${WHITE}%-48s${NC} %b\n" "1. Gỡ bỏ dịch vụ & dọn dẹp GitLab Runner cũ:" "$STATUS_CLEANUP"
printf "  ${BOLD}${WHITE}%-48s${NC} %b\n" "2. Tạo tài khoản hệ thống cô lập (Non-Root):" "$STATUS_USER"
printf "  ${BOLD}${WHITE}%-48s${NC} %b\n" "3. Trạng thái cài đặt GitLab Runner Engine:" "$STATUS_ENGINE"
printf "  ${BOLD}${WHITE}%-48s${NC} %b\n" "4. Tích hợp môi trường ảo hóa Docker Engine:" "$STATUS_DOCKER"
printf "  ${BOLD}${WHITE}%-48s${NC} %b\n" "5. Cấu hình bảo mật Systemd Service Sandbox:" "$STATUS_SYSTEMD"
printf "  ${BOLD}${WHITE}%-48s${NC} %b\n" "6. Thiết lập phân quyền nghiêm ngặt config:" "$STATUS_PERM"
printf "  ${BOLD}${WHITE}%-48s${NC} %b\n" "7. Trạng thái hoạt động dịch vụ Runner Service:" "$STATUS_SERVICE"
printf "  ${BOLD}${WHITE}%-48s${NC} %b\n" "8. Đăng ký (Register) với GitLab Server:" "$STATUS_REGISTER"
printf "  ${BOLD}${WHITE}%-48s${NC} %b\n" "9. Cronjob tự động dọn dẹp Docker hàng ngày:" "$STATUS_CRON"
echo -e "${BOLD}${CYAN}========================================================================${NC}"

echo -e "\n${BOLD}${GREEN}========================================================================${NC}"
echo -e "                       HOÀN TẤT CHƯƠNG TRÌNH ✅                         "
echo -e "${BOLD}${GREEN}========================================================================${NC}\n"
