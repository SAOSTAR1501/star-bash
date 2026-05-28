#!/bin/bash
# ==============================================================================
# Script Name   : run.sh
# Description   : Smart VPS Command Center — Star-Bash DevOps Suite v2.0
# Author        : Antigravity AI
# Version       : 2.0.0
# Usage         : sudo bash run.sh
# ==============================================================================

# ─── COLORS & ICONS ──────────────────────────────────────────────────────────
RED=$'\033[0;31m';   GREEN=$'\033[0;32m';  YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m';  PURPLE=$'\033[0;35m'; CYAN=$'\033[0;36m'
BOLD=$'\033[1m';     DIM=$'\033[2m';       WHITE=$'\033[1;37m'; NC=$'\033[0m'

OK="${GREEN}[✔]${NC}"; FAIL="${RED}[✘]${NC}"; WARN="${YELLOW}[⚠]${NC}"; INFO="${BLUE}[ℹ]${NC}"
SEP="${BOLD}${CYAN}========================================================================${NC}"
DASH="${BOLD}${CYAN}------------------------------------------------------------------------${NC}"

# ─── BOOTSTRAP ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}Error:${NC} Cần chạy với quyền root: ${BOLD}sudo bash run.sh${NC}"; exit 1
fi

# ─── GLOBAL STATE (populated by scan functions) ──────────────────────────────
S_NODE=""; S_NPM=""; S_PM2=""; S_DOCKER=""; S_COMPOSE=""; S_NGINX=""; S_CERTBOT=""
S_WARP=""; S_WARP_DETAIL=""; S_DEPLOYER=""; S_DEPLOYER_DETAIL=""; S_RUNNER=""; S_RUNNER_DETAIL=""
S_UFW=""; S_SSH_AUTH=""; S_SSH_ROOT=""; S_FAIL2BAN=""; S_NGINX_HEADERS=""
declare -a PROJ_NAMES=() PROJ_TYPES=() PROJ_RUNTIME=() PROJ_NGINX=()
declare -a PROJ_SSL=() PROJ_CICD=() PROJ_OWNER=()
declare -a REQUIRED_ACTIONS=()
NEXT_CHOICE=""
SKIP_USERS=("deployer" "ubuntu" "debian" "root" "gitlab-runner" "www-data" "git" "nobody" "pi" "ec2-user")

# ==============================================================================
# SCAN ENGINE
# ==============================================================================

scan_tool() {
    # Usage: scan_tool <cmd> [version_cmd] [service_name]
    local cmd="$1" ver_cmd="${2:-}" svc="${3:-}"
    if ! command -v "$cmd" &>/dev/null; then echo "${RED}✘${NC}"; return; fi
    if [ -n "$svc" ] && ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo "${YELLOW}stopped${NC}"; return
    fi
    local v=""
    [ -n "$ver_cmd" ] && v=$(eval "$ver_cmd" 2>/dev/null | grep -oP '[\d]+\.[\d.]+' | head -1)
    echo "${GREEN}${v:-ok}${NC}"
}

scan_infrastructure() {
    S_NODE=$(scan_tool "node" "node -v")
    S_NPM=$(scan_tool "npm" "npm -v")
    S_PM2=$(scan_tool "pm2" "pm2 -v")
    S_CERTBOT=$(scan_tool "certbot" "certbot --version")

    if command -v nginx &>/dev/null; then
        if systemctl is-active --quiet nginx 2>/dev/null; then
            local v; v=$(nginx -v 2>&1 | grep -oP '[\d.]+' | head -1)
            S_NGINX="${GREEN}${v:-ok}${NC}"
        else S_NGINX="${YELLOW}stopped${NC}"; fi
    else S_NGINX="${RED}✘${NC}"; fi

    if command -v docker &>/dev/null; then
        if systemctl is-active --quiet docker 2>/dev/null; then
            local v; v=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "ok")
            S_DOCKER="${GREEN}${v}${NC}"
        else S_DOCKER="${YELLOW}stopped${NC}"; fi
    else S_DOCKER="${RED}✘${NC}"; fi

    if docker compose version &>/dev/null 2>&1; then
        local v; v=$(docker compose version 2>/dev/null | grep -oP '[\d.]+' | head -1)
        S_COMPOSE="${GREEN}${v:-ok}${NC}"
    elif command -v docker-compose &>/dev/null; then S_COMPOSE="${YELLOW}standalone${NC}"
    else S_COMPOSE="${RED}✘${NC}"; fi

    # WARP
    if ! command -v warp-cli &>/dev/null; then
        S_WARP="${RED}✘${NC}"; S_WARP_DETAIL="Chưa cài đặt"
    else
        local reg; reg=$(warp-cli registration show 2>/dev/null || echo "")
        if ! echo "$reg" | grep -q "Account type: Team"; then
            S_WARP="${RED}✘${NC}"; S_WARP_DETAIL="Chưa liên kết Zero Trust Team"
        elif warp-cli status 2>/dev/null | grep -qi "Connected"; then
            S_WARP="${GREEN}✔${NC}"; S_WARP_DETAIL="Connected to Zero Trust"
        else S_WARP="${YELLOW}⚠${NC}"; S_WARP_DETAIL="Đã đăng ký nhưng chưa kết nối"; fi
    fi

    # Deployer
    if ! getent passwd deployer &>/dev/null; then
        S_DEPLOYER="${RED}✘${NC}"; S_DEPLOYER_DETAIL="User chưa tồn tại"
    else
        local issues=""
        local key_ok=false
        for kf in "/home/deployer/.ssh/id_rsa_gitlab" "/home/deployer/.ssh/id_ed25519_gitlab_local"; do
            [ -f "$kf" ] && key_ok=true && break
        done
        $key_ok || issues="no-SSH-key"
        id deployer 2>/dev/null | grep -q "(docker)" || issues="${issues:+$issues,}not-in-docker-group"
        
        if [ -n "$issues" ]; then
            S_DEPLOYER="${YELLOW}⚠${NC}"; S_DEPLOYER_DETAIL="Cần cấu hình ($issues)"
        else
            S_DEPLOYER="${GREEN}✔${NC}"; S_DEPLOYER_DETAIL="Sẵn sàng cho CI/CD"
        fi
    fi

    # Runner
    if ! command -v gitlab-runner &>/dev/null; then
        S_RUNNER="${RED}✘${NC}"; S_RUNNER_DETAIL="Chưa cài đặt"
    else
        if systemctl is-active --quiet gitlab-runner 2>/dev/null; then
            local count; count=$(gitlab-runner list 2>&1 | grep -c "Executor" || echo "0")
            S_RUNNER="${GREEN}✔${NC}"; S_RUNNER_DETAIL="Đang chạy ($count active)"
        else
            S_RUNNER="${YELLOW}stopped${NC}"; S_RUNNER_DETAIL="Service không hoạt động"
        fi
    fi

    # Security Posture
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then S_UFW="${GREEN}on${NC}"; else S_UFW="${YELLOW}off${NC}"; fi
    
    if [ -f "/etc/ssh/sshd_config" ]; then
        if grep -qE "^PasswordAuthentication\s+no" /etc/ssh/sshd_config; then S_SSH_AUTH="${GREEN}key-only${NC}"; else S_SSH_AUTH="${YELLOW}password-ok${NC}"; fi
        if grep -qE "^PermitRootLogin\s+no" /etc/ssh/sshd_config; then S_SSH_ROOT="${GREEN}disabled${NC}"; else S_SSH_ROOT="${YELLOW}enabled${NC}"; fi
    else
        S_SSH_AUTH="${RED}✘${NC}"; S_SSH_ROOT="${RED}✘${NC}"
    fi

    if systemctl is-active --quiet fail2ban 2>/dev/null; then S_FAIL2BAN="${GREEN}active${NC}"; else S_FAIL2BAN="${RED}✘${NC}"; fi
}

scan_projects() {
    PROJ_NAMES=(); PROJ_TYPES=(); PROJ_RUNTIME=(); PROJ_NGINX=(); PROJ_SSL=(); PROJ_CICD=(); PROJ_OWNER=()
    local search_paths=("/home" "/var/www")
    local scanned_dirs=()

    for base in "${search_paths[@]}"; do
        [ -d "$base" ] || continue
        for pdir in "$base"/*; do
            [ -d "$pdir" ] || continue
            local name; name=$(basename "$pdir")
            
            # Skip system/default folders
            for skip in "${SKIP_USERS[@]}"; do [[ "$name" == "$skip" ]] && continue 2; done
            [[ "$name" == "html" ]] && continue
            
            # Simple domain validation or .git / config files
            if [[ "$name" =~ \.[a-zA-Z]{2,} ]] || [ -d "$pdir/.git" ] || [ -f "$pdir/ecosystem.config.js" ] || [ -f "$pdir/deploy.sh" ]; then
                # Avoid duplicates if /home and /var/www point to same directory
                for sd in "${scanned_dirs[@]}"; do [[ "$sd" == "$pdir" ]] && continue 2; done
                scanned_dirs+=("$pdir")

                PROJ_NAMES+=("$name")

                # Type & PM2/Docker Runtime status
                local type="FE"
                local runtime="${RED}down${NC}"
                
                if [ -f "$pdir/deploy.sh" ] || [ -f "$pdir/docker-compose.yml" ]; then
                    type="BE"
                    if command -v docker &>/dev/null; then
                        # Check running containers related to project directory
                        local d_cnt; d_cnt=$(docker ps --format '{{.Names}}' | grep -ic "$name" || echo "0")
                        if [ "$d_cnt" -gt 0 ]; then
                            runtime="${GREEN}up ($d_cnt containers)${NC}"
                        else
                            runtime="${RED}down${NC}"
                        fi
                    else
                        runtime="${RED}no docker${NC}"
                    fi
                else
                    type="FE"
                    if command -v pm2 &>/dev/null; then
                        local pm2_status; pm2_status=$(pm2 jlist 2>/dev/null | grep -oP "\"name\":\"$name\".*?\"status\":\"[a-z]+\"" | head -1 || echo "")
                        if echo "$pm2_status" | grep -q "online"; then
                            runtime="${GREEN}running${NC}"
                        elif [ -f "$pdir/ecosystem.config.js" ]; then
                            runtime="${RED}stopped${NC}"
                        else
                            runtime="${YELLOW}unmanaged${NC}"
                        fi
                    else
                        runtime="${RED}no pm2${NC}"
                    fi
                fi
                PROJ_TYPES+=("$type")
                PROJ_RUNTIME+=("$runtime")

                # Nginx
                if [ -f "/etc/nginx/sites-enabled/$name" ]; then
                    PROJ_NGINX+=("${GREEN}enabled${NC}")
                elif [ -f "/etc/nginx/sites-available/$name" ]; then
                    PROJ_NGINX+=("${YELLOW}disabled${NC}")
                else
                    PROJ_NGINX+=("${RED}none${NC}")
                fi

                # SSL
                if [ -d "/etc/letsencrypt/live/$name" ] || [ -f "/etc/letsencrypt/live/$name/fullchain.pem" ]; then
                    local exp_date; exp_date=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$name/fullchain.pem" 2>/dev/null | cut -d= -f2 || echo "")
                    if [ -n "$exp_date" ]; then
                        local exp_epoch; exp_epoch=$(date -d "$exp_date" +%s 2>/dev/null || echo "0")
                        local now_epoch; now_epoch=$(date +%s)
                        local diff=$(( (exp_epoch - now_epoch) / 86400 ))
                        if [ "$diff" -le 0 ]; then
                            PROJ_SSL+=("${RED}expired${NC}")
                        elif [ "$diff" -le 15 ]; then
                            PROJ_SSL+=("${YELLOW}${diff}d warn${NC}")
                        else
                            PROJ_SSL+=("${GREEN}${diff}d OK${NC}")
                        fi
                    else
                        PROJ_SSL+=("${GREEN}active${NC}")
                    fi
                else
                    PROJ_SSL+=("${RED}none${NC}")
                fi

                # CI/CD
                if [ -f "$pdir/.gitlab-ci.yml" ]; then
                    PROJ_CICD+=("${GREEN}configured${NC}")
                else
                    PROJ_CICD+=("${RED}missing${NC}")
                fi

                # Ownership
                local owner; owner=$(stat -c '%U' "$pdir" 2>/dev/null || echo "root")
                if [ "$owner" = "deployer" ]; then
                    PROJ_OWNER+=("${GREEN}deployer${NC}")
                else
                    PROJ_OWNER+=("${RED}${owner}${NC}")
                fi
            fi
        done
    done
}

build_required_actions() {
    REQUIRED_ACTIONS=()
    # 1. WARP check
    if ! command -v warp-cli &>/dev/null || ! warp-cli registration show 2>/dev/null | grep -q "Account type: Team"; then
        REQUIRED_ACTIONS+=("[8] Cấu hình WARP & GitLab Connection (Thiếu kết nối Zero Trust)")
    fi
    # 2. Deployer check
    if ! getent passwd deployer &>/dev/null; then
        REQUIRED_ACTIONS+=("[6] Khởi tạo tài khoản hạn chế 'deployer' (Chưa có user)")
    fi
    # 3. GitLab Runner check
    if ! command -v gitlab-runner &>/dev/null; then
        REQUIRED_ACTIONS+=("[7] Thiết lập GitLab Runner an toàn (Chưa cài đặt runner)")
    fi
    # 4. Security checks
    if [ "$S_UFW" = "${YELLOW}off${NC}" ]; then
        REQUIRED_ACTIONS+=("[5] Kích hoạt và thiết lập Firewall bảo mật VPS (UFW đang OFF)")
    fi
}

# ==============================================================================
# UI RENDER ENGINE
# ==============================================================================

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
    echo -e "${BOLD}${CYAN}║${NC}      🌟 ${BOLD}${WHITE}STAR-BASH VPS COMMAND CENTER${NC} 🌟        ${YELLOW}v2.0${NC}                 ${BOLD}${CYAN}║${NC}"
    printf "${BOLD}${CYAN}║${NC}  Host: %-13s IP: %-15s OS: %-22s ${BOLD}${CYAN}║${NC}\n" "${hostname:0:13}" "${public_ip:0:15}" "${os_info:0:22}"
    printf "${BOLD}${CYAN}║${NC}  %-64s ${BOLD}${CYAN}║${NC}\n" "Uptime: $uptime_info"
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"

    # Block REQUIRED ACTIONS
    if [ ${#REQUIRED_ACTIONS[@]} -gt 0 ]; then
        echo -e "${BOLD}${CYAN}║${NC} ${RED}🔴 REQUIRED ACTIONS (Cần thực hiện ngay)${NC}                             ${BOLD}${CYAN}║${NC}"
        for act in "${REQUIRED_ACTIONS[@]}"; do
            local pad=$(( 65 - ${#act} ))
            printf "${BOLD}${CYAN}║${NC}   ${YELLOW}→${NC} %b%*s ${BOLD}${CYAN}║${NC}\n" "$act" "$pad" ""
        done
        echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    fi

    # Block INFRASTRUCTURE STATUS
    echo -e "${BOLD}${CYAN}║${NC} ${BLUE}⚡ INFRASTRUCTURE STATUS${NC}                                              ${BOLD}${CYAN}║${NC}"
    
    local line_tools=" [A] VPS TOOLS     Node: $S_NODE  Docker: $S_DOCKER  Nginx: $S_NGINX"
    local raw_tools=" [A] VPS TOOLS     Node: ok  Docker: ok  Nginx: ok"
    local pad_t=$(( 65 - ${#raw_tools} ))
    printf "${BOLD}${CYAN}║${NC}%b%*s${BOLD}${CYAN}║${NC}\n" "$line_tools" "$pad_t" ""

    local raw_tools_2="                PM2: ok  Certbot: ok  Compose: ok"
    local line_tools_2="                PM2: $S_PM2  Certbot: $S_CERTBOT  Compose: $S_COMPOSE"
    printf "${BOLD}${CYAN}║${NC}%b%*s${BOLD}${CYAN}║${NC}\n" "$line_tools_2" "$pad_t" ""

    local line_cicd=" [B] CICD STACK    WARP: $S_WARP ($S_WARP_DETAIL)"
    local raw_cicd=" [B] CICD STACK    WARP: x (Chưa liên kết Zero Trust Team)"
    local pad_cicd=$(( 65 - ${#raw_cicd} ))
    printf "${BOLD}${CYAN}║${NC}%b%*s${BOLD}${CYAN}║${NC}\n" "$line_cicd" "$pad_cicd" ""

    local line_cicd2="                deployer: $S_DEPLOYER  Runner: $S_RUNNER"
    local raw_cicd2="                deployer: x  Runner: x"
    local pad_cicd2=$(( 65 - ${#raw_cicd2} ))
    printf "${BOLD}${CYAN}║${NC}%b%*s${BOLD}${CYAN}║${NC}\n" "$line_cicd2" "$pad_cicd2" ""

    local line_sec=" [C] SECURITY      Firewall: $S_UFW  SSH: $S_SSH_AUTH  RootLogin: $S_SSH_ROOT"
    local raw_sec=" [C] SECURITY      Firewall: off  SSH: key-only  RootLogin: disabled"
    local pad_sec=$(( 65 - ${#raw_sec} ))
    printf "${BOLD}${CYAN}║${NC}%b%*s${BOLD}${CYAN}║${NC}\n" "$line_sec" "$pad_sec" ""

    # Block DEPLOYED PROJECTS
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}${CYAN}║${NC} ${PURPLE}📦 DEPLOYED PROJECTS (${#PROJ_NAMES[@]} sites)${NC}                                         ${BOLD}${CYAN}║${NC}"
    if [ ${#PROJ_NAMES[@]} -eq 0 ]; then
        echo -e "${BOLD}${CYAN}║${NC}   ${DIM}Chưa có dự án nào được triển khai trên hệ thống.${NC}                   ${BOLD}${CYAN}║${NC}"
    else
        for i in "${!PROJ_NAMES[@]}"; do
            local name="${PROJ_NAMES[$i]}"
            local type="${PROJ_TYPES[$i]}"
            local runtime="${PROJ_RUNTIME[$i]}"
            local ssl="${PROJ_SSL[$i]}"
            local cicd="${PROJ_CICD[$i]}"
            
            # Format text line
            local line_proj="   * ${BOLD}${WHITE}%-18s${NC} [%-2s] Status: %b  SSL: %b  CI/CD: %b"
            # Strip colors for alignment calculation
            local raw_proj="   * $name [$type] Status: running  SSL: 90d OK  CI/CD: configured"
            local pad_p=$(( 65 - ${#raw_proj} ))
            
            printf "${BOLD}${CYAN}║${NC}"
            printf "$line_proj" "$name" "$type" "$runtime" "$ssl" "$cicd"
            printf "%*s${BOLD}${CYAN}║${NC}\n" "$pad_p" ""
        done
    fi
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"

    # Block QUICK MENU
    echo -e "${BOLD}${CYAN}║${NC} ${GREEN}🏃 MAIN CONTROL CENTER${NC}                                                ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  [1] Server Setup & Tools Stack    [2] Khởi tạo Frontend Project (FE)   ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  [3] Khởi tạo Backend Project (BE) [4] Quản lý Dự án (Project Manager)   ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  [5] Kiểm tra bảo mật VPS (Audit)  [6] Cấu hình User VPS Deployer SSH    ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  [7] Cài đặt GitLab Runner an toàn  [8] Cấu hình WARP & GitLab Connect   ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  [9] Other Tools & VPS Monitor      [00] Cẩm nang Hướng dẫn (Guidelines) ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  [0] Thoát chương trình                                                 ${BOLD}${CYAN}║${NC}"
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
                    pm2 logs "$domain" --lines 100
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
                    echo -e "\n👉 Thử ping gitlab-local..."
                    ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -T gitlab-local 2>&1 | head -n 5
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
