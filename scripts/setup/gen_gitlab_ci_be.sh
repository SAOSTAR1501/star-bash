#!/bin/bash
# ==============================================================================
# Script Name   : gen_gitlab_ci_be.sh
# Description   : Backend dynamic Git Pull & Rebuild GitLab CI/CD pipeline generator
# Usage         : Called internally by run.sh Project Manager
# ==============================================================================

domain="$1"
pdir="$2"
target_ci="${pdir}/.gitlab-ci.yml"

# Colors & Formatting inside script
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
BOLD='\033[1m'; CYAN='\033[0;36m'; NC='\033[0m'
OK="${GREEN}[✔]${NC}"; FAIL="${RED}[✘]${NC}"; WARN="${YELLOW}[⚠]${NC}"; INFO="${BLUE}[ℹ]${NC}"

echo -e "\n🦊 CẤU HÌNH PIPELINE CI/CD DỰ ÁN BACKEND (Git Pull & Rebuild trên VPS)..."
echo -e "------------------------------------------------------------------------"

# Lấy danh sách các chi nhánh remote từ repository
echo -e "${INFO} Đang quét các chi nhánh từ remote git (origin)..."
git -C "$pdir" fetch --all --prune &>/dev/null || true

# Tạo mảng chứa danh sách các nhánh remote (bỏ origin/HEAD và xoá tiền tố origin/)
mapfile -t git_branches < <(git -C "$pdir" branch -r | grep -v 'origin/HEAD' | sed 's/^[[:space:]]*origin\///' | sed 's/^[[:space:]]*//' | sort -u)

if [ ${#git_branches[@]} -eq 0 ] || [ -z "${git_branches[0]}" ]; then
    echo -e "${WARN} Không tìm thấy chi nhánh remote nào hoặc thư mục không phải là git repo."
    read -p "👉 Nhập thủ công các chi nhánh muốn cấu hình (Ví dụ: develop,main): " branch_input
    branch_input=$(echo "$branch_input" | tr -d '[:space:]')
    if [ -z "$branch_input" ]; then
        echo -e "${FAIL} Danh sách chi nhánh không được để trống."
        exit 1
    fi
    IFS=',' read -r -a BRANCHES <<< "$branch_input"
else
    echo -e "\n📋 Danh sách các chi nhánh remote tìm thấy:"
    for i in "${!git_branches[@]}"; do
        echo -e "  [$(($i + 1))] ${git_branches[$i]}"
    done
    echo -e "  [m] Nhập thủ công tên chi nhánh khác..."
    
    while true; do
        read -p "👉 Chọn số tương ứng với các chi nhánh, cách nhau bằng dấu phẩy (Ví dụ: 1,2) hoặc chọn [m]: " branch_selection
        branch_selection=$(echo "$branch_selection" | tr -d '[:space:]')
        
        if [ "$branch_selection" = "m" ] || [ "$branch_selection" = "M" ]; then
            read -p "👉 Nhập thủ công các chi nhánh (Ví dụ: develop,main): " branch_input
            branch_input=$(echo "$branch_input" | tr -d '[:space:]')
            if [ -z "$branch_input" ]; then
                echo -e "${FAIL} Danh sách chi nhánh không được để trống."
                continue
            fi
            IFS=',' read -r -a BRANCHES <<< "$branch_input"
            break
        elif [ -n "$branch_selection" ]; then
            # Parse các index được chọn cách nhau bằng dấu phẩy
            IFS=',' read -r -a selected_indices <<< "$branch_selection"
            BRANCHES=()
            valid=true
            for index in "${selected_indices[@]}"; do
                if [[ "$index" =~ ^[0-9]+$ ]] && [ "$index" -ge 1 ] && [ "$index" -le "${#git_branches[@]}" ]; then
                    BRANCHES+=("${git_branches[$(($index - 1))]}")
                else
                    echo -e "${FAIL} Lựa chọn '$index' không hợp lệ."
                    valid=false
                    break
                fi
            done
            if $valid && [ ${#BRANCHES[@]} -gt 0 ]; then
                break
            fi
        else
            echo -e "${FAIL} Vui lòng nhập lựa chọn."
        fi
    done
fi

echo -e "${OK} Chi nhánh được chọn để cấu hình CI/CD: ${GREEN}$(IFS=','; echo "${BRANCHES[*]}")${NC}"

cat <<EOF > "$target_ci"
# ==============================================================================
# GitLab CI/CD Pipeline for Backend (Docker) - Git Pull & Rebuild on VPS
# Project: ${domain}
# Method: SSH Git Pull & trigger deploy.sh
# ==============================================================================

stages:
  - deploy
EOF

for br in "${BRANCHES[@]}"; do
    br_upper=$(echo "$br" | tr '[:lower:]' '[:upper:]' | tr '-' '_' | tr '/' '_')
    cat <<EOF >> "$target_ci"

# --- DEPLOY JOB CHO CHI NHÁNH: ${br} ---
deploy-${br}:
  stage: deploy
  image: alpine:latest
  rules:
    - if: \$CI_COMMIT_BRANCH == "${br}"
  variables:
    ENV_FILE: \$ENV_LOCAL_${br_upper}
    ENV_DOCKER_FILE: \$ENV_DOCKER_${br_upper}
  before_script:
    - apk add --no-cache openssh-client
    - mkdir -p ~/.ssh
    - eval \$(ssh-agent -s)
    - echo "\$SSH_PRIVATE_KEY" | tr -d '\r' | ssh-add -
    - echo -e "Host *\n\tStrictHostKeyChecking no\n\n" > ~/.ssh/config
  script:
    - echo "==> Đang đăng nhập VPS để thực hiện Git Pull và cấu hình môi trường..."
    - ssh deployer@\$VPS_IP "
        cd /home/${domain} &&
        git reset --hard &&
        git checkout -f ${br} &&
        git clean -fd &&
        git pull &&
        echo \"\$ENV_FILE\" > .env &&
        echo \"\$ENV_DOCKER_FILE\" > .env.docker &&
        if [ -f scripts/deploy.sh ]; then bash scripts/deploy.sh; else bash deploy.sh; fi
      "
    - echo "✅ Triển khai thành công trên nhánh ${br}."
EOF
done

chown deployer:deployer "$target_ci" 2>/dev/null || true
echo -e "\n${OK} Đã cấu hình thành công tệp: ${BOLD}${target_ci}${NC}"
echo -e " 🔹 Phương thức: Git Pull & Rebuild trực tiếp trên VPS"
echo -e " 🔹 Thư mục deploy cố định: ${BOLD}/home/${domain}${NC}"
echo -e "\n💡 Hãy đảm bảo user deployer trên VPS có quyền pull code từ Git (hoặc deploy key đã được thêm vào repo)."
