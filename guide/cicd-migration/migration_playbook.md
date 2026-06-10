# HƯỚNG DẪN DI CHUYỂN TOÀN DIỆN: CI/CD TẬP TRUNG CHO STAR-BASH SUITE
> **Kiến trúc:** Build tập trung trên Windows Runner (nội bộ) → Push sang GitLab Local Registry → Deploy siêu nhẹ trên VPS qua đường truyền WARP.

Tài liệu này cung cấp toàn bộ playbook dịch chuyển chi tiết, tỉ mỉ từ flow cũ của Star-Bash (VPS tự clone, tự cài Node/NPM, tự build Docker/Next.js) sang mô hình mới tối ưu tài nguyên và bảo mật tuyệt đối.

---

## BẢNG SO SÁNH TRƯỚC VÀ SAU KHI DỊCH CHUYỂN

| Hạng mục | Mô hình Star-Bash cũ | Mô hình Mới tối ưu |
| :--- | :--- | :--- |
| **Nhiệm vụ của VPS** | Cài Runner, kéo code, cài Node/PM2, tự chạy `npm run build` và `docker compose up -d --build`. | Chỉ chạy Container Docker từ image đã nén. Không build, không chứa mã nguồn. |
| **Mức độ tiêu thụ CPU/RAM VPS** | Đỉnh điểm **90% - 100%** (Gây nghẽn, sập web trong lúc build). | Ổn định ở mức **~1-3%** (Chỉ mất vài giây để kéo image về chạy). |
| **Bảo mật mã nguồn** | Thấp. Code gốc nằm trực tiếp trên thư mục `/home/<domain>`. | **Tuyệt đối**. VPS chỉ chứa Dockerfile/docker-compose và env. Không lưu code gốc. |
| **Cơ chế kích hoạt deploy** | Runner dùng SSH Key đăng nhập VPS từ xa (Nguy cơ lộ SSH Key toàn bộ VPS). | **Lightweight Shell Runner** trên VPS tự động kéo job qua HTTPS (Không cần SSH Key). |

---

## PHẦN 1. CẤU HÌNH TRÊN GITLAB LOCAL SERVER (`192.168.1.138`)

Vì toàn bộ hệ thống kết nối nội bộ qua Cloudflare WARP, chúng ta sẽ cấu hình Container Registry chạy trên giao thức HTTP nội bộ để bỏ qua cấu hình SSL phức tạp mà vẫn đảm bảo an toàn tuyệt đối.

### 1. Kích hoạt GitLab Container Registry (HTTP nội bộ)
1. Đăng nhập vào server GitLab Local, mở file `/etc/gitlab/gitlab.rb` bằng quyền root:
   ```bash
   sudo nano /etc/gitlab/gitlab.rb
   ```
2. Tìm và cấu hình các dòng sau để kích hoạt Registry trên cổng `5005`:
   ```ruby
   registry_external_url 'http://192.168.1.138:5005'
   gitlab_rails['registry_enabled'] = true
   ```
3. Lưu lại và thực hiện tái cấu hình GitLab:
   ```bash
   sudo gitlab-ctl reconfigure
   ```

### 2. Tạo Deploy Token (Thay thế hoàn toàn SSH Key và User Deployer cũ)
Để VPS có thể tự động pull image từ registry mà không cần dùng tài khoản cá nhân có quyền cao:
1. Truy cập GitLab UI -> Vào từng repo **Frontend** và **Backend** (hoặc tạo ở cấp Group nếu muốn dùng chung).
2. Vào **Settings** -> **Repository** -> **Deploy tokens**.
3. Điền thông tin tạo mới:
   * **Name**: `vps-deploy-token`
   * **Scopes**: Chỉ tích chọn duy nhất ô **`read_registry`** (chỉ cho phép pull Docker Image).
4. Nhấn **Create deploy token**, sau đó copy lại **Username** và **Password** sinh ra.
5. Truy cập **Settings** -> **CI/CD** -> **Variables**, thêm 2 biến môi trường sau:
   * `DEPLOY_TOKEN_USERNAME` = `<username_của_token>`
   * `DEPLOY_TOKEN_PASSWORD` = `<password_của_token>` (Thiết lập kiểu: `Masked` để ẩn mật khẩu).

---

## PHẦN 2. CẤU HÌNH TRÊN MÁY WINDOWS RUNNER (MÁY CHỦ BUILD TẬP TRUNG)

Máy Windows nội bộ của công ty sẽ chịu toàn bộ tải trọng của quá trình build mã nguồn, đóng gói Docker Image và push lên GitLab.

### 1. Cấu hình Docker Engine để nhận diện GitLab Local
Vì GitLab Registry chạy HTTP (`http://192.168.1.138:5005`), Docker trên Windows mặc định sẽ chặn kết nối không bảo mật này. Bạn cần thêm nó vào **Insecure Registries**.

* **Nếu sử dụng Docker Desktop**:
  1. Mở **Docker Desktop** -> Chọn biểu tượng răng cưa **Settings** -> Chọn **Docker Engine**.
  2. Bổ sung IP Registry vào cấu hình JSON:
     ```json
     {
       "insecure-registries": [
         "192.168.1.138:5005"
       ],
       "builder": {
         "gc": {
           "defaultKeepStorage": "20GB",
           "enabled": true
         }
       }
     }
     ```
  3. Nhấn **Apply & restart**.

* **Nếu chạy Docker trực tiếp trên WSL2 (Không cài Docker Desktop)**:
  1. Sửa file `/etc/docker/daemon.json` bên trong môi trường WSL2:
     ```json
     {
       "insecure-registries": ["192.168.1.138:5005"]
     }
     ```
  2. Chạy lệnh: `sudo systemctl restart docker`.

### 2. Thiết lập GitLab Runner trên Windows
1. Tạo thư mục `C:\GitLab-Runner`, tải file thực thi `gitlab-runner.exe` chính thức của Windows đặt vào đây.
2. Mở **PowerShell (Administrator)**, chạy lệnh đăng ký Runner:
   ```powershell
   cd C:\GitLab-Runner
   .\gitlab-runner.exe register
   ```
   * **GitLab URL**: `http://192.168.1.138` (hoặc domain nội bộ của bạn).
   * **Registration Token**: Lấy từ GitLab Admin Area -> Runners.
   * **Description**: `Windows Heavy Builder`
   * **Tags**: `windows-build`, `heavy-builder`
   * **Executor**: Chọn **`docker`**.
   * **Default Docker Image**: `docker:24.0.7` (hoặc bản mới nhất).
3. Sau khi đăng ký xong, sửa file cấu hình `C:\GitLab-Runner\config.toml` của Windows Runner để hỗ trợ cơ chế build Docker-in-Docker (DinD):
   ```toml
   [[runners]]
     name = "Windows Heavy Builder"
     url = "http://192.168.1.138"
     token = "YOUR_RUNNER_TOKEN"
     executor = "docker"
     [runners.custom_build_dir]
     [runners.docker]
       tls_verify = false
       image = "docker:24.0.7"
       privileged = true   # <--- BẮT BUỘC đặt true để chạy được Docker-in-Docker
       disable_entrypoint_overwrite = false
       oom_kill_disable = false
       disable_cache = false
       volumes = ["/cache", "/var/run/docker.sock:/var/run/docker.sock"] # Mount socket để dùng chung engine nếu cần
   ```
4. Cài đặt Runner thành dịch vụ hệ thống của Windows và khởi chạy:
   ```powershell
   .\gitlab-runner.exe install
   .\gitlab-runner.exe start
   ```

---

## PHẦN 3. CẤU HÌNH VÀ TỐI ƯU BẢO MẬT TRÊN CÁC VPS

Chúng ta sẽ tận dụng chính script `setup_gitlab_runner.sh` sẵn có của bạn trên VPS nhưng chuyển đổi cấu hình từ chạy build nặng sang **Shell Executor siêu nhẹ để deploy**.

### 1. Giữ lại và Cấu hình Lightweight Runner trên VPS
1. Trên VPS, chạy lại script `setup_gitlab_runner.sh` để reset và cài đặt một Runner sạch sẽ dưới quyền user `gitlab-runner` (Không root).
2. Khi đăng ký Runner (Register):
   * **URL**: `http://192.168.1.138` (Nhận qua WARP).
   * **Executor**: Chọn **`shell`** (Đây là điểm mấu chốt! Shell executor tiêu thụ cực kỳ ít tài nguyên, chỉ khoảng vài MB RAM).
   * **Tags**: Đặt tag riêng biệt cho từng VPS, ví dụ: `deploy-vps-prod-1`, `deploy-vps-prod-2`...
3. Cấp quyền thực thi Docker cho user `gitlab-runner` của VPS (đã có sẵn trong script cũ của bạn):
   ```bash
   sudo usermod -aG docker gitlab-runner
   sudo systemctl restart gitlab-runner
   ```

### 2. Cấu hình Docker Insecure Registry trên VPS
Để Docker trên VPS có thể pull từ cổng `5005` qua WARP:
1. Mở file `/etc/docker/daemon.json` trên VPS:
   ```bash
   sudo nano /etc/docker/daemon.json
   ```
2. Cấu hình y hệt như sau:
   ```json
   {
     "insecure-registries": ["192.168.1.138:5005"]
   }
   ```
3. Khởi động lại Docker:
   ```bash
   sudo systemctl restart docker
   ```

### 3. HẠNG MỤC CẦN LOẠI BỎ (REMOVE) TRÊN VPS ĐỂ BẢO MẬT TỐI ĐA

> [!WARNING]
> Để giữ cho VPS được an toàn tuyệt đối và dọn sạch các "rác" tài nguyên từ mô hình cũ, hãy thực hiện các bước dọn dẹp sau:

1. **Xóa hoàn toàn mã nguồn gốc (Source Code) khỏi VPS**:
   * Ở mô hình cũ, code được clone về thư mục `/home/<domain>`.
   * **Hành động**: Xóa thư mục `.git` và mã nguồn thô trên VPS. Môi trường mới chỉ cần file `docker-compose.yml` và thư mục cấu hình.
   ```bash
   # Ví dụ xóa repo code thô nhưng giữ lại các file config tĩnh cần thiết
   cd /home/<domain>
   rm -rf .git/ .next/ node_modules/ src/ components/ pages/ package.json package-lock.json
   ```
2. **Gỡ bỏ Node.js, NPM, Yarn và PM2 cài trực tiếp trên VPS (Nếu đã chuyển FE sang Docker)**:
   * Không còn cần chạy Node trực tiếp trên VPS nữa, gỡ bỏ để tránh xung đột phiên bản và giải phóng RAM:
   ```bash
   sudo npm uninstall -g pm2
   sudo apt-get remove --purge -y nodejs npm
   sudo apt-get autoremove -y
   ```
3. **Thu hồi quyền và Xóa SSH Deploy Keys**:
   * Mô hình cũ yêu cầu SSH Private Key lưu trên GitLab CI/CD Variables để SSH vào VPS. Mô hình mới dựa trên cơ chế kéo (Pull) của Shell Runner nên **không cần kết nối SSH từ ngoài vào nữa**.
   * **Hành động 1**: Truy cập GitLab -> **Settings** -> **CI/CD** -> **Variables** -> **Xóa hoàn toàn biến `SSH_PRIVATE_KEY`**.
   * **Hành động 2**: Mở file `/home/deployer/.ssh/authorized_keys` trên VPS và xóa dòng key SSH công khai liên quan đến GitLab CI.
   * **Hành động 3**: Xóa luôn private key cũ của deployer trên VPS nếu có: `rm -f /home/deployer/.ssh/id_rsa_gitlab*`.

---

## PHẦN 4. THAY ĐỔI CẤU TRÚC PROJECT VÀ FILE `.gitlab-ci.yml` CHUẨN

Dưới đây là cách thiết lập lại cho dự án Backend và dự án Frontend để hoạt động theo luồng mới.

### 1. Dành cho dự án BACKEND (Docker / Docker Compose)

#### A. Cấu trúc file `docker-compose.yml` trên VPS (Lưu tại `/home/<domain>/docker-compose.yml`)
Không còn dùng cờ build thô nữa. Trỏ trực tiếp tới registry nội bộ qua WARP:
```yaml
version: '3.8'

services:
  backend-api:
    image: 192.168.1.138:5005/vitechgroup/backend-api:latest # <--- Trỏ tới Registry nội bộ
    container_name: backend-api-prod
    restart: always
    ports:
      - "8080:8080"
    env_file:
      - .env
      - .env.docker
```

#### B. Cấu hình file `.gitlab-ci.yml` chuẩn cho Backend:
```yaml
stages:
  - build
  - deploy

variables:
  REGISTRY: "192.168.1.138:5005"
  IMAGE_TAG: "$REGISTRY/$CI_PROJECT_PATH:$CI_COMMIT_REF_SLUG"

# ---------------------------------------------
# PHA 1: BUILD IMAGE (Chạy trên máy Windows nội bộ mạnh)
# ---------------------------------------------
build-backend:
  stage: build
  tags:
    - windows-build  # <-- Gọi Windows Heavy Builder
  image: docker:24.0.7
  services:
    - docker:24.0.7-dind
  script:
    - docker build --pull -t $IMAGE_TAG .
    - docker push $IMAGE_TAG

# ---------------------------------------------
# PHA 2: DEPLOY SIÊU NHẸ (Chạy trực tiếp trên VPS qua Shell Runner)
# ---------------------------------------------
deploy-backend:
  stage: deploy
  tags:
    - deploy-vps-prod-1 # <-- Gọi Shell Runner trên VPS cụ thể
  variables:
    # Lấy file môi trường động theo nhánh từ GitLab CI Variables
    ENV_LOCAL: $ENV_LOCAL_MAIN
    ENV_DOCKER: $ENV_DOCKER_MAIN
  script:
    # 1. Ghi tệp tin môi trường cục bộ trực tiếp trên VPS
    - echo "$ENV_LOCAL" > /home/$CI_PROJECT_NAME/.env
    - echo "$ENV_DOCKER" > /home/$CI_PROJECT_NAME/.env.docker
    
    # 2. Đăng nhập registry và pull image mới qua WARP
    - echo "$DEPLOY_TOKEN_PASSWORD" | docker login $REGISTRY -u $DEPLOY_TOKEN_USERNAME --password-stdin
    
    # 3. Kéo và restart dịch vụ bằng docker-compose
    - cd /home/$CI_PROJECT_NAME
    - docker compose pull
    - docker compose up -d --remove-orphans
    
    # 4. Dọn dẹp rác hệ thống tránh đầy ổ cứng VPS
    - docker image prune -f
```

---

### 2. Dành cho dự án FRONTEND (Docker hóa Next.js thay thế PM2)

Để triển khai Next.js mượt mà không gặp lỗi dung lượng artifact nặng, chúng ta sẽ chuyển đổi Next.js sang chế độ build **Standalone** chạy trong Docker container.

#### A. Cấu hình `next.config.js` trong code Frontend
Thêm dòng `output: 'standalone'` để Next.js tự động gom các tệp tối thiểu cần thiết để chạy mà không cần thư mục `node_modules` khổng lồ:
```javascript
module.exports = {
  output: 'standalone',
}
```

#### B. Tạo file `Dockerfile` chuẩn cho Frontend Next.js (Lưu ở thư mục gốc dự án FE)
Sử dụng Multi-stage build để giảm dung lượng Docker Image từ ~1GB xuống chỉ còn **~120MB**:
```dockerfile
# Stage 1: Install dependencies & build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --prefer-offline
COPY . .
RUN npm run build

# Stage 2: Runner
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy các tệp tối thiểu từ builder
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
ENV PORT=3000
CMD ["node", "server.js"]
```

#### C. Cấu hình file `.gitlab-ci.yml` chuẩn cho Frontend:
```yaml
stages:
  - build
  - deploy

variables:
  REGISTRY: "192.168.1.138:5005"
  IMAGE_TAG: "$REGISTRY/$CI_PROJECT_PATH:$CI_COMMIT_REF_SLUG"

# ---------------------------------------------
# PHA 1: BUILD IMAGE (Chạy trên Windows Runner)
# ---------------------------------------------
build-frontend:
  stage: build
  tags:
    - windows-build # <-- Dùng Windows Runner
  image: docker:24.0.7
  services:
    - docker:24.0.7-dind
  script:
    # Copy biến env của dự án vào làm .env.production trước khi đóng gói
    - echo "$ENV_LOCAL_MAIN" > .env.production
    - docker build --pull -t $IMAGE_TAG .
    - docker push $IMAGE_TAG

# ---------------------------------------------
# PHA 2: DEPLOY SIÊU NHẸ (Chạy trên VPS qua Shell Runner)
# ---------------------------------------------
deploy-frontend:
  stage: deploy
  tags:
    - deploy-vps-prod-1 # <-- Shell Runner trên VPS
  script:
    # 1. Đăng nhập registry qua WARP
    - echo "$DEPLOY_TOKEN_PASSWORD" | docker login $REGISTRY -u $DEPLOY_TOKEN_USERNAME --password-stdin
    
    # 2. Dừng và xóa Container FE cũ
    - docker stop frontend-prod || true
    - docker rm frontend-prod || true
    
    # 3. Pull image mới và khởi chạy
    - docker pull $IMAGE_TAG
    - docker run -d --name frontend-prod -p 80:3000 --restart always $IMAGE_TAG
    
    # 4. Dọn dẹp
    - docker image prune -f
```
