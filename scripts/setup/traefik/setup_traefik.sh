#!/bin/bash
# ==============================================================================
# Script Name   : setup_traefik.sh
# Description   : Automated Traefik Proxy Installer & Network Creator
# Author        : Antigravity AI
# Version       : 1.0.0
# Compatibility : Ubuntu, Debian
# ==============================================================================

# Define Colors for Terminal Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

TICK="${GREEN}[✔]${NC}"
CROSS="${RED}[✘]${NC}"
INFO="${BLUE}[ℹ]${NC}"

TARGET_DIR="/home/traefik"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}${BOLD}Lỗi:${NC} Script này phải được chạy với quyền ${BOLD}root${NC} (hoặc sử dụng sudo)."
        exit 1
    fi
}

check_docker() {
    echo -e "${INFO} Đang kiểm tra cài đặt Docker..."
    if ! command -v docker &>/dev/null; then
        echo -e "${CROSS} Không tìm thấy Docker trên hệ thống! Vui lòng chạy setup.sh cài đặt docker trước."
        exit 1
    fi
    echo -e "${TICK} Docker đã được cài đặt."
}

create_web_network() {
    echo -e "${INFO} Đang kiểm tra docker network 'web'..."
    if docker network inspect web &>/dev/null; then
        echo -e "${TICK} Docker network 'web' đã tồn tại."
    else
        echo -e "${INFO} Đang tạo docker network 'web' (external)..."
        if docker network create web >> /dev/null; then
            echo -e "${TICK} Tạo docker network 'web' thành công."
        else
            echo -e "${CROSS} Tạo docker network 'web' thất bại!"
            exit 1
        fi
    fi
}

setup_traefik_directories() {
    echo -e "${INFO} Đang khởi tạo thư mục Traefik tại ${TARGET_DIR}..."
    mkdir -p "${TARGET_DIR}"
    
    # Tạo file acme.json trống nếu chưa tồn tại và phân quyền 600
    if [ ! -f "${TARGET_DIR}/acme.json" ]; then
        touch "${TARGET_DIR}/acme.json"
        chmod 600 "${TARGET_DIR}/acme.json"
        echo -e "${TICK} Đã khởi tạo tệp acme.json và chmod 600 thành công."
    else
        chmod 600 "${TARGET_DIR}/acme.json"
        echo -e "${TICK} Tệp acme.json đã tồn tại, cập nhật chmod 600 thành công."
    fi
}

copy_configs() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    
    echo -e "${INFO} Đang đồng bộ các tệp cấu hình Traefik..."
    if [ -f "${script_dir}/docker-compose.yml" ] && [ -f "${script_dir}/traefik.yml" ]; then
        cp "${script_dir}/docker-compose.yml" "${TARGET_DIR}/docker-compose.yml"
        cp "${script_dir}/traefik.yml" "${TARGET_DIR}/traefik.yml"
        echo -e "${TICK} Đồng bộ cấu hình Traefik thành công."
    else
        # Trường hợp chạy trực tiếp độc lập không qua git, tự sinh file config
        echo -e "${YELLOW}[!] Không tìm thấy tệp cấu hình mẫu. Đang tự tạo tệp cấu hình mặc định...${NC}"
        
        cat <<EOF > "${TARGET_DIR}/docker-compose.yml"
services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - ./acme.json:/acme.json
    networks:
      - web

networks:
  web:
    external: true
EOF

        cat <<EOF > "${TARGET_DIR}/traefik.yml"
api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: web

certificatesResolvers:
  letsencrypt-prod:
    acme:
      email: saostar1501@gmail.com
      storage: acme.json
      httpChallenge:
        entryPoint: web
EOF
        echo -e "${TICK} Đã tự động sinh cấu hình Traefik mặc định thành công."
    fi
}

start_traefik() {
    echo -e "${INFO} Đang khởi chạy container Traefik..."
    cd "${TARGET_DIR}"
    if docker compose up -d; then
        echo -e "${TICK} Khởi chạy Traefik thành công!"
        echo -e "${GREEN}${BOLD}======================================================================${NC}"
        echo -e "${GREEN}${BOLD} Traefik và Docker Network 'web' đã được cấu hình thành công!${NC}"
        echo -e "${GREEN}${BOLD}======================================================================${NC}"
    else
        echo -e "${CROSS} Khởi chạy Traefik thất bại. Vui lòng kiểm tra lại Docker compose logs."
        exit 1
    fi
}

main() {
    check_root
    check_docker
    create_web_network
    setup_traefik_directories
    copy_configs
    start_traefik
}

main "$@"
