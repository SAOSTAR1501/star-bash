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
echo -e " 🔹 Phương thức: Git Pull & Rebuild trực tiếp trên VPS"
echo -e " 🔹 Thư mục deploy cố định: ${BOLD}/home/${domain}${NC}"
echo -e "\n💡 Hãy đảm bảo user deployer trên VPS có quyền pull code từ Git (hoặc deploy key đã được thêm vào repo)."
