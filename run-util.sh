#!/bin/bash
# ==============================================================================
# Script Name   : run-util.sh
# Description   : Core Utilities & Scanning Engines for Star-Bash DevOps Suite
# Author        : Antigravity AI
# Version       : 2.0.0
# ==============================================================================

# ─── COLORS & ICONS ──────────────────────────────────────────────────────────
RED=$'\033[0;31m';   GREEN=$'\033[0;32m';  YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m';  PURPLE=$'\033[0;35m'; CYAN=$'\033[0;36m'
BOLD=$'\033[1m';     DIM=$'\033[2m';       WHITE=$'\033[1;37m'; NC=$'\033[0m'

OK="${GREEN}[✔]${NC}"; FAIL="${RED}[✘]${NC}"; WARN="${YELLOW}[⚠]${NC}"; INFO="${BLUE}[ℹ]${NC}"
SEP="${BOLD}${CYAN}========================================================================${NC}"
DASH="${BOLD}${CYAN}------------------------------------------------------------------------${NC}"

# ─── GLOBAL STATE ────────────────────────────────────────────────────────────
S_NODE=""; S_NPM=""; S_PM2=""; S_DOCKER=""; S_COMPOSE=""; S_NGINX=""; S_CERTBOT=""
S_WARP=""; S_WARP_DETAIL=""; S_DEPLOYER=""; S_DEPLOYER_DETAIL=""; S_RUNNER=""; S_RUNNER_DETAIL=""
S_UFW=""; S_SSH_AUTH=""; S_SSH_ROOT=""; S_FAIL2BAN=""; S_NGINX_HEADERS=""
declare -a PROJ_NAMES=() PROJ_TYPES=() PROJ_RUNTIME=() PROJ_NGINX=()
declare -a PROJ_SSL=() PROJ_CICD=() PROJ_OWNER=()
declare -a REQUIRED_ACTIONS=()
SKIP_USERS=("deployer" "ubuntu" "debian" "root" "gitlab-runner" "www-data" "git" "nobody" "pi" "ec2-user")

# ─── FORMATTING & UI UTILITIES ────────────────────────────────────────────────
print_border_line() {
    local text="$1"
    local esc=$'\e'
    local clean; clean=$(echo -n "$text" | sed "s/${esc}\[[0-9;]*[a-zA-Z]//g")
    local visual_len=${#clean}
    local pad=$(( 70 - visual_len ))
    if [ "$pad" -lt 0 ]; then pad=0; fi
    printf "${BOLD}${CYAN}║${NC}%b%*s${BOLD}${CYAN}║${NC}\n" "$text" "$pad" ""
}

# ─── INFRASTRUCTURE SCAN ENGINE ──────────────────────────────────────────────
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
    S_PM2=$(sudo -u deployer pm2 -v 2>/dev/null || pm2 -v 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "${RED}✘${NC}")
    # PM2 check optimization: make sure we output green ifPM2 is available
    if command -v pm2 &>/dev/null; then
        local pm2_v; pm2_v=$(sudo -u deployer pm2 -v 2>/dev/null || pm2 -v 2>/dev/null)
        S_PM2="${GREEN}${pm2_v:-ok}${NC}"
    else
        S_PM2="${RED}✘${NC}"
    fi
    
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

# ─── PROJECTS SCAN ENGINE ────────────────────────────────────────────────────
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
                        local pm2_status; pm2_status=$(sudo -u deployer pm2 jlist 2>/dev/null || pm2 jlist 2>/dev/null)
                        pm2_status=$(echo "$pm2_status" | grep -oP "\"name\":\"$name\".*?\"status\":\"[a-z]+\"" | head -1 || echo "")
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
