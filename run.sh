#!/bin/bash
# ==============================================================================
# Script Name   : run.sh
# Description   : Smart VPS Command Center — Star-Bash DevOps Suite v2.0
# Author        : Antigravity AI
# Version       : 2.0.0
# Usage         : sudo bash run.sh
# ==============================================================================

# ─── BOOTSTRAP & UTILS ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m\033[1mError:\033[0m Cần chạy với quyền root: \033[1msudo bash run.sh\033[0m"; exit 1
fi

# Tự động cấp quyền thực thi (executable bit) cho toàn bộ các script con trong DevOps Suite
find "$SCRIPT_DIR" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

# Nạp toàn bộ các thư viện Colors, State, Scans và UI Utilities dùng chung
if [ -f "$SCRIPT_DIR/run-util.sh" ]; then
    source "$SCRIPT_DIR/run-util.sh"
else
    echo -e "\033[0;31m[✘] Error:\033[0m Không tìm thấy tệp tin thư viện run-util.sh tại $SCRIPT_DIR"; exit 1
fi

show_smart_dashboard() {
    clear
    scan_infrastructure
    scan_projects
    build_required_actions

    local hostname; hostname=$(hostname 2>/dev/null || echo "vps")
    local public_ip; public_ip=$(curl -s --max-time 2 ifconfig.me || echo "127.0.0.1")
    local os_info; os_info=$(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 || echo "Linux")
    local uptime_info; uptime_info=$(uptime -p 2>/dev/null || echo "up")

    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    print_border_line "      🌟 ${BOLD}${WHITE}STAR-BASH VPS COMMAND CENTER${NC} 🌟        ${YELLOW}v2.0${NC}"
    print_border_line "  Host: ${hostname:0:15}    IP: ${public_ip:0:15}  OS: ${os_info:0:30}"
    print_border_line "  Uptime: $uptime_info"
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"

    # Block REQUIRED ACTIONS
    if [ ${#REQUIRED_ACTIONS[@]} -gt 0 ]; then
        print_border_line " ${RED}🔴 REQUIRED ACTIONS (Cần thực hiện ngay)${NC}"
        for act in "${REQUIRED_ACTIONS[@]}"; do
            print_border_line "   ${YELLOW}→${NC} $act"
        done
        echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    fi

    # Block INFRASTRUCTURE STATUS
    print_border_line " ${BLUE}⚡ INFRASTRUCTURE STATUS${NC}"
    print_border_line "  [A] VPS TOOLS     Node: $S_NODE  Docker: $S_DOCKER  Nginx: $S_NGINX"
    print_border_line "                 PM2: $S_PM2  Certbot: $S_CERTBOT  Compose: $S_COMPOSE"
    print_border_line "  [B] CICD STACK    WARP: $S_WARP ($S_WARP_DETAIL)"
    print_border_line "                 deployer: $S_DEPLOYER  Runner: $S_RUNNER"
    print_border_line "  [C] SECURITY      Firewall: $S_UFW  SSH: $S_SSH_AUTH  RootLogin: $S_SSH_ROOT"
    
    # Block DEPLOYED PROJECTS
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    print_border_line " ${PURPLE}📦 DEPLOYED PROJECTS (${#PROJ_NAMES[@]} sites)${NC}"
    if [ ${#PROJ_NAMES[@]} -eq 0 ]; then
        print_border_line "   ${DIM}Chưa có dự án nào được triển khai trên hệ thống.${NC}"
    else
        for i in "${!PROJ_NAMES[@]}"; do
            local name="${PROJ_NAMES[$i]}"
            local type="${PROJ_TYPES[$i]}"
            local runtime="${PROJ_RUNTIME[$i]}"
            local ssl="${PROJ_SSL[$i]}"
            local cicd="${PROJ_CICD[$i]}"
            
            # Format text line using printf -v
            local line_proj
            printf -v line_proj "   * ${BOLD}${WHITE}%-18s${NC} [%-2s] Status: %b  SSL: %b  CI/CD: %b" "$name" "$type" "$runtime" "$ssl" "$cicd"
            print_border_line "$line_proj"
        done
    fi
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"

    # Block QUICK MENU
    print_border_line " ${GREEN}🏃 MAIN CONTROL CENTER${NC}"
    print_border_line "  [1] Server Setup & Tools Stack    [2] Khởi tạo Frontend Project (FE)"
    print_border_line "  [3] Khởi tạo Backend Project (BE) [4] Quản lý Dự án (Project Manager)"
    print_border_line "  [5] Kiểm tra bảo mật VPS (Audit)  [6] Cấu hình User VPS Deployer SSH"
    print_border_line "  [7] Cài đặt GitLab Runner an toàn  [8] Cấu hình WARP & GitLab Connect"
    print_border_line "  [9] Other Tools & VPS Monitor      [00] Cẩm nang Hướng dẫn (Guidelines)"
    print_border_line "  [0] Thoát chương trình"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
}

# ==============================================================================
# LINKED FLOW & CONTEXTUAL PROMPT
# ==============================================================================

prompt_next() {
    local completed_step="$1"
    NEXT_CHOICE=""
    local prompt_file="$SCRIPT_DIR/setup/prompts/prompt_${completed_step}.sh"
    if [ -f "$prompt_file" ]; then
        source "$prompt_file"
    else
        echo -e "\n$SEP"
        echo -e "${BOLD}${GREEN}✔ Thao tác hoàn thành xuất sắc!${NC}"
        echo -e "$DASH"
        read -r -p "👉 Nhấn Enter để tiếp tục..." _
    fi
}

# ==============================================================================
# PROJECT MANAGER (SUBMENU OPTION 4)
# ==============================================================================

project_manager_menu() {
    while true; do
        scan_projects
        clear
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e "         📦 ${BOLD}${WHITE}STAR-BASH PROJECT MANAGER & LIVE CONTROL CENTER${NC} 📦         "
        echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
        
        if [ ${#PROJ_NAMES[@]} -eq 0 ]; then
            echo -e " ${WARN} Không tìm thấy dự án nào đang chạy."
            read -r -p "👉 Nhấn Enter để quay lại..." _
            return 0
        fi

        echo -e " ${BOLD}${WHITE}Danh sách dự án đang chạy trên VPS:${NC}\n"
        for i in "${!PROJ_NAMES[@]}"; do
            local idx=$(( i + 1 ))
            printf "  [%d] %-20s [%-2s] Status: %s  SSL: %s  CI/CD: %s\n" \
                "$idx" "${PROJ_NAMES[$i]}" "${PROJ_TYPES[$i]}" "${PROJ_RUNTIME[$i]}" "${PROJ_SSL[$i]}" "${PROJ_CICD[$i]}"
        done
        echo -e "\n  [0] Quay lại Menu chính"
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        
        read -r -p "👉 Chọn dự án của bạn để quản trị [0-${#PROJ_NAMES[@]}]: " p_idx
        if [ "$p_idx" = "0" ] || [ -z "$p_idx" ]; then
            return 0
        fi

        if ! [[ "$p_idx" =~ ^[0-9]+$ ]] || [ "$p_idx" -lt 1 ] || [ "$p_idx" -gt "${#PROJ_NAMES[@]}" ]; then
            echo -e "${FAIL} Lựa chọn sai."
            sleep 1
            continue
        fi

        local sel_idx=$(( p_idx - 1 ))
        project_detail_menu "${PROJ_NAMES[$sel_idx]}" "${PROJ_TYPES[$sel_idx]}"
    done
}

project_detail_menu() {
    local domain="$1"
    local type="$2"
    local pdir=""
    
    if [ -d "/home/$domain" ]; then pdir="/home/$domain"; else pdir="/var/www/$domain"; fi

    while true; do
        clear
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e " 📌 ${BOLD}${WHITE}Chi tiết dự án: $domain${NC} [Mode: $type]"
        echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
        
        # Details Scan
        local git_remote; git_remote=$(git -C "$pdir" remote get-url origin 2>/dev/null || echo "None")
        local git_branch; git_branch=$(git -C "$pdir" branch --show-current 2>/dev/null || echo "None")
        local owner; owner=$(stat -c '%U:%G' "$pdir" 2>/dev/null || echo "unknown")
        
        echo -e "  📁 Đường dẫn VPS : ${BOLD}$pdir${NC}"
        echo -e "  🔀 Git Repository: ${BOLD}$git_remote${NC} (${BOLD}$git_branch${NC})"
        echo -e "  🔑 Phân quyền    : ${BOLD}$owner${NC}"
        
        if [ "$type" = "FE" ]; then
            echo -e "  🚀 Web Runtime   : Next.js (PM2)"
            local pm2_out; pm2_out=$(pm2 show "$domain" 2>/dev/null || echo "")
            if echo "$pm2_out" | grep -q "status"; then
                echo -e "  🟢 Trạng thái PM2: ${GREEN}Đang hoạt động (Cluster)${NC}"
            else
                echo -e "  🔴 Trạng thái PM2: ${RED}Chưa được đăng ký khởi chạy${NC}"
            fi
        else
            echo -e "  🐳 Web Runtime   : Backend (Docker)"
            local d_active; d_active=$(docker ps --format '{{.Names}}' | grep -ic "$domain" || echo "0")
            if [ "$d_active" -gt 0 ]; then
                echo -e "  🟢 Docker compose: ${GREEN}Active ($d_active container)${NC}"
            else
                echo -e "  🔴 Docker compose: ${RED}Không có container nào đang chạy${NC}"
            fi
        fi

        local nginx_cfg="/etc/nginx/sites-enabled/$domain"
        if [ -f "$nginx_cfg" ]; then
            echo -e "  🌐 Nginx Routing : ${GREEN}Đã kích hoạt site config${NC}"
        else
            echo -e "  🌐 Nginx Routing : ${RED}Chưa cấu hình hoặc bị tắt${NC}"
        fi

        if [ -d "/etc/letsencrypt/live/$domain" ]; then
            echo -e "  🔒 Chứng chỉ SSL : ${GREEN}Đã cài đặt HTTPS (Certbot)${NC}"
        else
            echo -e "  🔒 Chứng chỉ SSL : ${RED}Chưa đăng ký SSL HTTPS${NC}"
        fi

        if [ -f "$pdir/.gitlab-ci.yml" ]; then
            echo -e "  🦊 GitLab CI/CD  : ${GREEN}Đã tích hợp .gitlab-ci.yml${NC}"
        else
            echo -e "  🦊 GitLab CI/CD  : ${RED}Thiếu cấu hình pipeline${NC}"
        fi

        echo -e "\n${BOLD}${WHITE}Các công cụ quản trị dự án:${NC}"
        echo -e "  [1] ▶  Khởi chạy / Restart ứng dụng (PM2 hoặc Docker)"
        echo -e "  [2] 🔄 Pull Code mới & Triển khai nhanh (git pull & restart)"
        echo -e "  [3] 📄 Xem log ứng dụng trực tiếp (Real-time logs)"
        echo -e "  [4] ⚡ Cấu hình / Cập nhật tệp CI/CD (.gitlab-ci.yml)"
        echo -e "  [5] 🔒 Gia hạn thủ công chứng chỉ SSL Certbot"
        echo -e "  [6] 🔑 Hiển thị Deployer Private Key (Thêm vào GitLab CI/CD)"
        echo -e "  [7] 🗑  Xoá bỏ dự án khỏi VPS (Safe Cleanup)"
        echo -e "  [0] Quay lại danh sách dự án"
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        
        read -r -p "👉 Nhập lựa chọn quản trị [0-7]: " action_idx
        case "$action_idx" in
            0|"") break ;;
            1)
                echo -e "\n🔄 Đang thực hiện Restart..."
                if [ "$type" = "FE" ]; then
                    su - deployer -c "pm2 restart $domain || pm2 start $pdir/ecosystem.config.js"
                else
                    if [ -f "$pdir/deploy.sh" ]; then
                        su - deployer -c "bash $pdir/deploy.sh"
                    else
                        echo -e "${FAIL} Thiếu file $pdir/deploy.sh để chạy BE."
                    fi
                fi
                read -r -p "👉 Done. Nhấn Enter để tiếp tục..." _
                ;;
            2)
                echo -e "\n🔄 Đang Pull code và cập nhật..."
                su - deployer -c "cd $pdir && git pull"
                if [ "$type" = "FE" ]; then
                    su - deployer -c "pm2 restart $domain || pm2 start $pdir/ecosystem.config.js"
                else
                    if [ -f "$pdir/deploy.sh" ]; then
                        su - deployer -c "bash $pdir/deploy.sh"
                    else
                        echo -e "${FAIL} Thiếu file $pdir/deploy.sh để chạy BE."
                    fi
                fi
                read -r -p "👉 Xong. Nhấn Enter để tiếp tục..." _
                ;;
            3)
                echo -e "\n📄 Đang truyền tải log trực tiếp (Nhấn Ctrl+C để thoát)..."
                if [ "$type" = "FE" ]; then
                    sudo -u deployer pm2 logs "$domain" --lines 100
                else
                    local c_name; c_name=$(docker ps --format '{{.Names}}' | grep "$domain" | head -1 || echo "")
                    if [ -n "$c_name" ]; then
                        docker logs -f --tail 100 "$c_name"
                    else
                        echo -e "${FAIL} Không tìm thấy container nào liên quan đến domain để lấy log."
                        read -r -p "👉 Nhấn Enter để tiếp tục..." _
                    fi
                fi
                ;;
            4)
                echo -e "\n🦊 CẤU HÌNH / CẬP NHẬT GITLAB CI/CD CHO DỰ ÁN..."
                echo -e "------------------------------------------------------------------------"
                if [ "$type" = "FE" ]; then
                    if [ -f "$SCRIPT_DIR/setup/gen_gitlab_ci.sh" ]; then
                        bash "$SCRIPT_DIR/setup/gen_gitlab_ci.sh"
                    else
                        echo -e "${FAIL} Không tìm thấy file script $SCRIPT_DIR/setup/gen_gitlab_ci.sh"
                    fi
                else
                    # BE Docker project CI/CD generator
                    local target_ci="${pdir}/.gitlab-ci.yml"
                    local template="${SCRIPT_DIR}/.gitlab-ci-be.yml.example"
                    if [ ! -f "$template" ]; then
                        echo -e "${FAIL} Không tìm thấy tệp mẫu .gitlab-ci-be.yml.example tại thư mục gốc."
                    else
                        echo -e "${INFO} Đang khởi tạo tệp cấu hình CI/CD cho dự án Backend: ${BOLD}$domain${NC}"
                        echo -e ""
                        read -p "👉 Nhập tên nhánh Staging (Mặc định: develop): " stg_branch
                        stg_branch=${stg_branch:-"develop"}
                        
                        read -p "👉 Nhập tên nhánh Production (Mặc định: main): " prod_branch
                        prod_branch=${prod_branch:-"main"}

                        # Create the CI/CD file by replacing placeholders
                        cat "$template" | \
                            sed "s|api.vitech.vn-develop|${domain}-${stg_branch}|g" | \
                            sed "s|api.vitech.vn|${domain}|g" | \
                            sed "s|CI_COMMIT_BRANCH == \"develop\"|CI_COMMIT_BRANCH == \"${stg_branch}\"|g" | \
                            sed "s|CI_COMMIT_BRANCH == \"main\"|CI_COMMIT_BRANCH == \"${prod_branch}\"|g" | \
                            sed "s|build-staging:|build-${stg_branch}:|g" | \
                            sed "s|build-production:|build-${prod_branch}:|g" | \
                            sed "s|deploy-staging:|deploy-${stg_branch}:|g" | \
                            sed "s|deploy-production:|deploy-${prod_branch}:|g" | \
                            sed "s|dependencies:\s*- build-staging|dependencies:\n    - build-${stg_branch}|g" | \
                            sed "s|dependencies:\s*- build-production|dependencies:\n    - build-${prod_branch}|g" \
                            > "$target_ci"
                        
                        chown deployer:deployer "$target_ci" 2>/dev/null || true
                        echo -e "\n${OK} Đã cấu hình thành công tệp: ${BOLD}${target_ci}${NC}"
                        echo -e " 🔹 Nhánh Staging   : ${BOLD}${stg_branch}${NC} → Thư mục deploy: ${BOLD}/home/${domain}-${stg_branch}${NC}"
                        echo -e " 🔹 Nhánh Production: ${BOLD}${prod_branch}${NC} → Thư mục deploy: ${BOLD}/home/${domain}${NC}"
                        echo -e "\n💡 Hãy sao chép Deployer Private Key (chọn mục [6]) để cấu hình GitLab CI/CD Variables."
                    fi
                fi
                read -r -p "\n👉 Nhấn Enter để tiếp tục..." _
                ;;
            5)
                echo -e "\n🔒 Đang chạy gia hạn Certbot SSL..."
                certbot renew --cert-name "$domain"
                read -r -p "👉 Nhấn Enter để tiếp tục..." _
                ;;
            6)
                clear
                echo -e "${BOLD}${CYAN}========================================================================${NC}"
                echo -e " 🔑  ${BOLD}DEPLOYER PRIVATE KEY CHO PROJECT: $domain${NC}"
                echo -e "${BOLD}${CYAN}========================================================================${NC}"
                echo -e " Hãy copy toàn bộ đoạn mã bên dưới và add vào biến ${BOLD}SSH_PRIVATE_KEY${NC}"
                echo -e " tại mục: ${BOLD}GitLab Repository -> Settings -> CI/CD -> Variables${NC}"
                echo -e "$DASH\n"
                
                local key_path=""
                if [ -f "/home/deployer/.ssh/id_rsa_gitlab" ]; then
                    key_path="/home/deployer/.ssh/id_rsa_gitlab"
                elif [ -f "/home/deployer/.ssh/id_ed25519_gitlab_local" ]; then
                    key_path="/home/deployer/.ssh/id_ed25519_gitlab_local"
                fi

                if [ -n "$key_path" ] && [ -f "$key_path" ]; then
                    cat "$key_path"
                    echo -e "\n$DASH"
                    echo -e " IP của VPS cần add vào biến ${BOLD}VPS_IP${NC}: ${BOLD}$(curl -s ifconfig.me || echo "VPS IP")${NC}"
                else
                    echo -e "${FAIL} Không tìm thấy file key Private của deployer. Vui lòng chạy mục [6] ở Menu chính."
                fi
                echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
                read -r -p "👉 Nhấn Enter để quay lại..." _
                ;;
            7)
                read -p "⚠ CẢNH BÁO: Bạn thực sự muốn XOÁ HOÀN TOÀN project $domain khỏi VPS? (y/N): " confirm
                if [[ "$confirm" =~ ^[yY] ]]; then
                    echo -e "\n🗑  Đang dừng và dọn dẹp các service..."
                    if [ "$type" = "FE" ]; then
                        pm2 delete "$domain" 2>/dev/null || true
                    else
                        if [ -f "$pdir/docker-compose.yml" ]; then
                            cd "$pdir" && docker compose down -v 2>/dev/null || true
                        fi
                    fi
                    
                    echo -e "🗑  Đang gỡ bỏ cấu hình Nginx..."
                    rm -f "/etc/nginx/sites-enabled/$domain"
                    rm -f "/etc/nginx/sites-available/$domain"
                    systemctl reload nginx 2>/dev/null || true
                    
                    echo -e "🗑  Đang xoá bỏ thư mục mã nguồn..."
                    rm -rf "$pdir"
                    
                    echo -e "${OK} Đã xoá toàn bộ dữ liệu dự án $domain."
                    sleep 2
                    break
                fi
                ;;
            *)
                echo -e "${FAIL} Lựa chọn không hợp lệ."
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# SUBMENU 1: SERVER SETUP & TOOLS
# ==============================================================================

server_setup_menu() {
    local choice
    while true; do
        clear
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e "         ⚙️  ${BOLD}${WHITE}SERVER INITIAL WORKFLOW & UTILITIES SUITE${NC} ⚙️         "
        echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
        echo -e " ${BOLD}${WHITE}Các tùy chọn cài đặt hệ thống VPS:${NC}\n"
        echo -e "  [1] 🚀 ${BOLD}VPS Tool Auto-Installer (setup.sh)${NC}"
        echo -e "       (Cài đặt trọn gói: Node, NPM, Yarn, PM2, Docker, Nginx, Certbot)"
        echo -e "  [2] 🛡️  ${BOLD}VPS Security Audit & Hardening (security_check.sh)${NC}"
        echo -e "       (Quét lỗ hổng bảo mật, cấu hình UFW, bật Fail2Ban, tắt SSH Password)"
        echo -e "  [3] 📊 ${BOLD}Real-time VPS Resource Dashboard (sys_monitor.sh)${NC}"
        echo -e "       (Theo dõi realtime CPU, RAM, Disk, Traffic qua Terminal)"
        echo -e "  [4] 🔔 ${BOLD}Telegram Bot Alerts Configuration (sys_monitor.sh config)${NC}"
        echo -e "       (Cấu hình bot Telegram gửi tin nhắn cảnh báo tự động khi VPS quá tải)"
        echo -e "  [5] ⚡ ${BOLD}Run Instant Check & Send Telegram Alert Test${NC}"
        echo -e "       (Chạy test khẩn cấp hệ thống giám sát & gửi tin test)"
        echo -e "  [0] Quay lại Menu chính"
        echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
        
        read -r -p "👉 Nhập lựa chọn của bạn [0-5]: " choice
        case "$choice" in
            0|"") return 0 ;;
            1)
                if [ -f "$SCRIPT_DIR/setup/setup.sh" ]; then
                    bash "$SCRIPT_DIR/setup/setup.sh"
                else echo -e "${FAIL} Không tìm thấy setup.sh"; fi
                read -r -p "👉 Done. Nhấn Enter..." _
                ;;
            2)
                if [ -f "$SCRIPT_DIR/security/security_check.sh" ]; then
                    bash "$SCRIPT_DIR/security/security_check.sh"
                else echo -e "${FAIL} Không tìm thấy security_check.sh"; fi
                prompt_next "security"
                ;;
            3)
                if [ -f "$SCRIPT_DIR/setup/sys_monitor.sh" ]; then
                    bash "$SCRIPT_DIR/setup/sys_monitor.sh" dashboard
                else echo -e "${FAIL} Không tìm thấy sys_monitor.sh"; fi
                ;;
            4)
                if [ -f "$SCRIPT_DIR/setup/sys_monitor.sh" ]; then
                    bash "$SCRIPT_DIR/setup/sys_monitor.sh" config
                else echo -e "${FAIL} Không tìm thấy sys_monitor.sh"; fi
                read -r -p "👉 Nhấn Enter..." _
                ;;
            5)
                if [ -f "$SCRIPT_DIR/setup/sys_monitor.sh" ]; then
                    bash "$SCRIPT_DIR/setup/sys_monitor.sh" check
                else echo -e "${FAIL} Không tìm thấy sys_monitor.sh"; fi
                read -r -p "👉 Nhấn Enter..." _
                ;;
            *)
                echo -e "${FAIL} Lựa chọn không hợp lệ."
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# SUBMENU 9: OTHER TOOLS
# ==============================================================================

other_tools_menu() {
    local choice
    while true; do
        clear
        echo -e "${BOLD}${CYAN}========================================================================${NC}"
        echo -e "         🔧 ${BOLD}${WHITE}OTHER DEVOPS UTILITIES & SUPPORT TOOLS${NC} 🔧         "
        echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
        echo -e "  [1] 🦊 ${BOLD}Tạo cấu hình GitLab CI/CD standalone (gen_gitlab_ci.sh)${NC}"
        echo -e "  [2] 🦊 ${BOLD}Test kết nối WARP & GitLab Local Router${NC}"
        echo -e "  [3] 📊 ${BOLD}Interactive FE Site Deployer (Legacy - Step-by-Step)${NC}"
        echo -e "  [4] ⚡ ${BOLD}Quick FE Site Deployer (Legacy - Automated)${NC}"
        echo -e "  [0] Quay lại Menu chính"
        echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
        
        read -r -p "👉 Nhập lựa chọn của bạn [0-4]: " choice
        case "$choice" in
            0|"") return 0 ;;
            1)
                if [ -f "$SCRIPT_DIR/setup/gen_gitlab_ci.sh" ]; then
                    bash "$SCRIPT_DIR/setup/gen_gitlab_ci.sh"
                else echo -e "${FAIL} Không tìm thấy gen_gitlab_ci.sh"; fi
                read -r -p "👉 Nhấn Enter..." _
                ;;
            2)
                echo -e "\n🔍 Đang chạy kiểm tra định tuyến WARP Zero Trust & GitLab..."
                if command -v warp-cli &>/dev/null; then
                    warp-cli status
                    echo -e "\n👉 Thử ping gitlab-local dưới quyền deployer..."
                    sudo -u deployer ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -T gitlab-local 2>&1 | head -n 5
                else
                    echo -e "${FAIL} Chưa cài đặt WARP."
                fi
                read -r -p "👉 Nhấn Enter..." _
                ;;
            3)
                if [ -f "$SCRIPT_DIR/deploy-fe/interactive_setup_site.sh" ]; then
                    bash "$SCRIPT_DIR/deploy-fe/interactive_setup_site.sh"
                else echo -e "${FAIL} Không tìm thấy interactive_setup_site.sh"; fi
                ;;
            4)
                if [ -f "$SCRIPT_DIR/deploy-fe/quick_setup_site.sh" ]; then
                    # Quick FE site deployer wrapper
                    echo -e "\n👉 Nhập thông tin để triển khai nhanh:"
                    read -p "  Domain: " d
                    read -p "  Port: " p
                    if [ -n "$d" ] && [ -n "$p" ]; then
                        bash "$SCRIPT_DIR/deploy-fe/quick_setup_site.sh" "$d" "$p" "yes-eco"
                    else echo -e "${FAIL} Thiếu thông tin."; fi
                else echo -e "${FAIL} Không tìm thấy quick_setup_site.sh"; fi
                read -r -p "👉 Nhấn Enter..." _
                ;;
            *)
                echo -e "${FAIL} Lựa chọn không hợp lệ."
                sleep 1
                ;;
        esac
    done
}

show_guidelines() {
    clear
    echo -e "${BOLD}${CYAN}========================================================================${NC}"
    echo -e "       📖 ${BOLD}${WHITE}CẨM NANG HƯỚNG DẪN QUY TRÌNH DEVOPS CHUẨN - STAR-BASH SUITE${NC} 📖       "
    echo -e "${BOLD}${CYAN}========================================================================${NC}\n"
    
    echo -e "${BOLD}${WHITE}1. THIẾT LẬP SERVER BAN ĐẦU (Chỉ chạy một lần duy nhất)${NC}"
    echo -e "   Để setup một VPS hoàn toàn mới và liên kết nó với GitLab local:"
    echo -e "   👉 ${BOLD}Bước 1:${NC} Chọn ${BOLD}[8]${NC} trên Main Menu để cài đặt Cloudflare WARP client."
    echo -e "          - Đăng nhập tài khoản Team Zero Trust của bạn."
    echo -e "          - Copy SSH Public Key hiển thị dán vào mục SSH Keys trên GitLab cá nhân."
    echo -e "   👉 ${BOLD}Bước 2:${NC} Chọn ${BOLD}[6]${NC} trên Main Menu để sinh user hạn chế quyền ${BOLD}deployer${NC}."
    echo -e "          - Tài khoản này sẽ là chủ sở hữu mã nguồn ứng dụng, tránh dùng root nguy hiểm."
    echo -e "   👉 ${BOLD}Bước 3:${NC} Chọn ${BOLD}[7]${NC} trên Main Menu cài đặt GitLab Runner an toàn."
    echo -e "          - Runner chạy trực tiếp dưới quyền của user gitlab-runner biệt lập."
    echo -e "   👉 ${BOLD}Bước 4:${NC} Chọn ${BOLD}[1] → [2]${NC} để chạy Security Hardening (UFW Firewall, SSH key-only, Fail2Ban)."
    echo -e ""
    
    echo -e "${BOLD}${WHITE}2. QUY TRÌNH KHỞI TẠO VÀ DEPLOY PROJECT MỚI${NC}"
    echo -e "   👉 ${BOLD}Đối với Frontend (Next.js / PM2 Cluster Mode):${NC} Chọn mục ${BOLD}[2]${NC}"
    echo -e "          - Nhập domain riêng chạy ứng dụng Next.js."
    echo -e "          - Script tự động clone, sinh file PM2 ecosystem.config.js chế độ Cluster,"
    echo -e "            cài đặt Nginx reverse proxy và đăng ký SSL Certbot miễn phí (chỉ dùng root domain)."
    echo -e "          - Khởi chạy lần đầu: ${BOLD}su - deployer -c \"pm2 start /home/domain/ecosystem.config.js && pm2 save\"${NC}"
    echo -e "   👉 ${BOLD}Đối với Backend (Docker Compose):${NC} Chọn mục ${BOLD}[3]${NC}"
    echo -e "          - Nhập domain riêng, cổng host chạy container, lệnh run compose đặc thù."
    echo -e "          - Script tự động clone, cấp nhóm docker cho deployer, tạo deploy.sh chạy an toàn,"
    echo -e "            cấu hình Nginx routing proxy và đăng ký SSL Certbot (chỉ dùng root domain)."
    echo -e "          - Khởi chạy lần đầu: ${BOLD}su - deployer -c \"bash /home/domain/deploy.sh\"${NC}"
    echo -e ""
    
    echo -e "${BOLD}${WHITE}3. TỰ ĐỘNG HÓA PIPELINE CI/CD LÊN GITLAB${NC}"
    echo -e "   Để kích hoạt cơ chế push-to-deploy tự động khi viết code:"
    echo -e "   👉 ${BOLD}Bước A:${NC} Vào GitLab Repository của bạn → Settings → CI/CD → Variables."
    echo -e "   👉 ${BOLD}Bước B:${NC} Thêm 4 biến môi trường:"
    echo -e "          - ${BOLD}VPS_IP${NC}              IP Public của VPS."
    echo -e "          - ${BOLD}SSH_PRIVATE_KEY${NC}     Lấy khóa Private Key của user deployer (vào mục ${BOLD}[4]${NC}"
    echo -e "                                  chọn project, chọn ${BOLD}[6]${NC} để hiển thị nhanh)."
    echo -e "          - ${BOLD}ENV_LOCAL_DEVELOP${NC}   Nội dung file .env cho môi trường Staging (nhánh develop)."
    echo -e "          - ${BOLD}ENV_LOCAL_PRODUCTION${NC}  Nội dung file .env cho môi trường Production (nhánh main)."
    echo -e "   👉 ${BOLD}Bước C:${NC} Commit tệp tin ${BOLD}.gitlab-ci.yml${NC} đã được tự động tạo ở gốc dự án lên GitLab."
    echo -e "          - Từ đây, mỗi khi push code lên develop/main, server sẽ tự động build và chạy."
    echo -e ""
    echo -e "${BOLD}${CYAN}========================================================================${NC}"
    read -r -p "👉 Nhấn Enter để quay lại Dashboard..." _
}

# ==============================================================================
# MAIN DISPATCHER & LOOP
# ==============================================================================

dispatch_choice() {
    local choice="$1"
    case "$choice" in
        00) show_guidelines ;;
        1)  server_setup_menu ;;
        2)
            if [ -f "$SCRIPT_DIR/setup/orchestrate_fe_project.sh" ]; then
                bash "$SCRIPT_DIR/setup/orchestrate_fe_project.sh"
            else
                echo -e "${FAIL} orchestrate_fe_project.sh không tìm thấy"; sleep 2
            fi
            prompt_next "fe_project"
            ;;
        3)
            if [ -f "$SCRIPT_DIR/setup/orchestrate_be_project.sh" ]; then
                bash "$SCRIPT_DIR/setup/orchestrate_be_project.sh"
            else
                echo -e "${FAIL} orchestrate_be_project.sh không tìm thấy"; sleep 2
            fi
            prompt_next "be_project"
            ;;
        4)  project_manager_menu ;;
        5)
            if [ -f "$SCRIPT_DIR/security/security_check.sh" ]; then
                bash "$SCRIPT_DIR/security/security_check.sh"
            else
                echo -e "${FAIL} security_check.sh không tìm thấy"; sleep 2
            fi
            prompt_next "security"
            ;;
        6)
            if [ -f "$SCRIPT_DIR/setup/setup_vps_deployer.sh" ]; then
                bash "$SCRIPT_DIR/setup/setup_vps_deployer.sh"
            else
                echo -e "${FAIL} setup_vps_deployer.sh không tìm thấy"; sleep 2
            fi
            prompt_next "deployer"
            ;;
        7)
            if [ -f "$SCRIPT_DIR/setup/setup_gitlab_runner.sh" ]; then
                bash "$SCRIPT_DIR/setup/setup_gitlab_runner.sh"
            else
                echo -e "${FAIL} setup_gitlab_runner.sh không tìm thấy"; sleep 2
            fi
            prompt_next "runner"
            ;;
        8)
            if [ -f "$SCRIPT_DIR/setup/setup_warp_gitlab.sh" ]; then
                bash "$SCRIPT_DIR/setup/setup_warp_gitlab.sh"
            else
                echo -e "${FAIL} setup_warp_gitlab.sh không tìm thấy"; sleep 2
            fi
            prompt_next "warp"
            ;;
        9)  other_tools_menu ;;
        0)
            echo -e "\n${BOLD}${GREEN}Cảm ơn đã dùng Star-Bash Suite. Tạm biệt!${NC}\n"
            exit 0
            ;;
        "")  ;; # Empty enter, redraw dashboard
        *)
            echo -e "${FAIL} Lựa chọn không hợp lệ: '${choice}'"
            sleep 1
            ;;
    esac
}

main_loop() {
    local pending=""
    while true; do
        if [ -z "$pending" ]; then
            show_smart_dashboard
            read -r -p $'\n👉 Nhập lựa chọn của bạn [0-9, 00]: ' pending
            pending="${pending// /}" # trim whitespace
        fi
        local current="$pending"
        pending=""
        NEXT_CHOICE=""
        dispatch_choice "$current"
        
        # If dispatcher set NEXT_CHOICE (linked flow chain), carry it over
        [ -n "$NEXT_CHOICE" ] && pending="$NEXT_CHOICE"
    done
}

main_loop "$@"
