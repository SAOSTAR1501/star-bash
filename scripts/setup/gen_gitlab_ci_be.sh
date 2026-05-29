#!/bin/bash
# ==============================================================================
# Script Name   : gen_gitlab_ci_be.sh
# Description   : Backend dynamic branch-based GitLab CI/CD pipeline generator
# Usage         : Called internally by run.sh Project Manager
# ==============================================================================

domain="$1"
pdir="$2"
target_ci="${pdir}/.gitlab-ci.yml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
template="${SCRIPT_DIR}/scripts/setup/templates/.gitlab-ci-be.yml.example"

# Colors & Formatting inside sourced or executed script
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
BOLD='\033[1m'; CYAN='\033[0;36m'; NC='\033[0m'
OK="${GREEN}[✔]${NC}"; FAIL="${RED}[✘]${NC}"; WARN="${YELLOW}[⚠]${NC}"; INFO="${BLUE}[ℹ]${NC}"

echo -e "\n⚙️  CHỌN PHƯƠNG THỨC TRIỂN KHAI CI/CD CHO BACKEND DOCKER:"
echo -e "  [1] Nén & Đẩy gói build từ GitLab Runner (Artifact-based)"
echo -e "       (Khuyên dùng: Bảo mật cao, không cần lưu thông tin Git credentials trên VPS)"
echo -e "  [2] Git Pull & Rebuild trực tiếp trên VPS (Lightweight)"
echo -e "       (Tiết kiệm tài nguyên: SSH vào VPS tự động pull code mới và chạy docker/npm)"

local ci_method=""
while true; do
    read -p "👉 Lựa chọn của bạn [1-2]: " ci_method
    if [ "$ci_method" = "1" ] || [ "$ci_method" = "2" ]; then
        break
    else
        echo -e "${FAIL} Lựa chọn không hợp lệ. Vui lòng nhập 1 hoặc 2."
    fi
done

if [ "$ci_method" = "1" ]; then
    if [ ! -f "$template" ]; then
        echo -e "${FAIL} Không tìm thấy tệp mẫu .gitlab-ci-be.yml.example tại thư mục templates."
        exit 1
    fi
    
    echo -e "\n${INFO} Đang khởi tạo tệp cấu hình CI/CD (Artifact-based) cho dự án Backend: ${BOLD}$domain${NC}"
    echo -e ""
    read -p "👉 Nhập tên nhánh Staging (Mặc định: develop): " stg_branch
    stg_branch=${stg_branch:-"develop"}
    
    read -p "👉 Nhập tên nhánh Production (Mặc định: main): " prod_branch
    prod_branch=${prod_branch:-"main"}

    local stg_upper; stg_upper=$(echo "$stg_branch" | tr '[:lower:]' '[:upper:]' | tr '-' '_' | tr '/' '_')
    local prod_upper; prod_upper=$(echo "$prod_branch" | tr '[:lower:]' '[:upper:]' | tr '-' '_' | tr '/' '_')

    # Create the CI/CD file by replacing placeholders
    cat "$template" | \
        sed "s|api.vitech.vn-develop|${domain}|g" | \
        sed "s|api.vitech.vn|${domain}|g" | \
        sed "s|CI_COMMIT_BRANCH == \"develop\"|CI_COMMIT_BRANCH == \"${stg_branch}\"|g" | \
        sed "s|CI_COMMIT_BRANCH == \"main\"|CI_COMMIT_BRANCH == \"${prod_branch}\"|g" | \
        sed "s|build-staging:|build-${stg_branch}:|g" | \
        sed "s|build-production:|build-${prod_branch}:|g" | \
        sed "s|deploy-staging:|deploy-${stg_branch}:|g" | \
        sed "s|deploy-production:|deploy-${prod_branch}:|g" | \
        sed "s|dependencies:\s*- build-staging|dependencies:\n    - build-${stg_branch}|g" | \
        sed "s|dependencies:\s*- build-production|dependencies:\n    - build-${prod_branch}|g" | \
        sed "s|ENV_LOCAL_DEVELOP|ENV_LOCAL_${stg_upper}|g" | \
        sed "s|ENV_LOCAL_PRODUCTION|ENV_LOCAL_${prod_upper}|g" \
        > "$target_ci"
    
    chown deployer:deployer "$target_ci" 2>/dev/null || true
    echo -e "\n${OK} Đã cấu hình thành công tệp: ${BOLD}${target_ci}${NC}"
    echo -e " 🔹 Phương thức     : Nén & Đóng gói từ GitLab Runner (Artifact-based)"
    echo -e " 🔹 Nhánh Staging   : ${BOLD}${stg_branch}${NC} → Thư mục deploy: ${BOLD}/home/${domain}${NC} (Biến env: ${BOLD}ENV_LOCAL_${stg_upper}${NC})"
    echo -e " 🔹 Nhánh Production: ${BOLD}${prod_branch}${NC} → Thư mục deploy: ${BOLD}/home/${domain}${NC} (Biến env: ${BOLD}ENV_LOCAL_${prod_upper}${NC})"
    echo -e "\n💡 Hãy sao chép Deployer Private Key (chọn mục [6]) để cấu hình GitLab CI/CD Variables."
else
    # Git Pull & Rebuild directly on VPS
    echo -e "\n${INFO} Đang khởi tạo tệp cấu hình CI/CD (Git Pull & Rebuild) cho dự án Backend: ${BOLD}$domain${NC}"
    read -p "👉 Nhập các chi nhánh muốn cấu hình CI/CD, cách nhau bằng dấu phẩy (Ví dụ: develop,main): " branch_input
    branch_input=$(echo "$branch_input" | tr -d '[:space:]')
    
    if [ -z "$branch_input" ]; then
        echo -e "${FAIL} Danh sách chi nhánh không được để trống."
        exit 1
    fi
    
    IFS=',' read -r -a BRANCHES <<< "$branch_input"
    
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
        local br_upper; br_upper=$(echo "$br" | tr '[:lower:]' '[:upper:]' | tr '-' '_' | tr '/' '_')
        cat <<EOF >> "$target_ci"

# --- DEPLOY JOB CHO CHI NHÁNH: ${br} ---
deploy-${br}:
  stage: deploy
  image: alpine:latest
  rules:
    - if: \$CI_COMMIT_BRANCH == "${br}"
  before_script:
    - apk add --no-cache openssh-client
    - mkdir -p ~/.ssh
    - eval \$(ssh-agent -s)
    - echo "\$SSH_PRIVATE_KEY" | tr -d '\r' | ssh-add -
    - echo -e "Host *\n\tStrictHostKeyChecking no\n\n" > ~/.ssh/config
  script:
    - echo "==> Đang đăng nhập VPS để thực hiện Git Pull và khởi chạy dịch vụ..."
    - ssh deployer@\$VPS_IP "cd /home/${domain} && git checkout ${br} && git pull && bash deploy.sh"
    - echo "✅ Triển khai thành công trên nhánh ${br}."
EOF
    done
    
    chown deployer:deployer "$target_ci" 2>/dev/null || true
    echo -e "\n${OK} Đã cấu hình thành công tệp: ${BOLD}${target_ci}${NC}"
    echo -e " 🔹 Phương thức: Git Pull & Rebuild trên VPS"
    echo -e " 🔹 Thư mục deploy cố định: ${BOLD}/home/${domain}${NC}"
    echo -e "\n💡 Hãy đảm bảo user deployer trên VPS có quyền pull code từ Git (hoặc deploy key đã được thêm vào repo)."
fi
