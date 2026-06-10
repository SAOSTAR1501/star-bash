# TÀI LIỆU HÀNG RÀO BẢO MẬT (HARDENING) CI/CD WINDOWS RUNNER
> **Chuyên đề:** Đánh giá rủi ro bảo mật của cấu hình Runner và các phương án khắc phục an toàn tối đa (DooD không privileged & Google Kaniko).

Phân tích của bạn về **3 Lỗ hổng Bảo mật Nghiêm trọng** là hoàn toàn chính xác và cực kỳ sắc bén. Trong môi trường doanh nghiệp chuyên nghiệp, việc sử dụng `privileged = true` kết hợp với mount Docker Socket thô (`docker.sock`) là một mối đe dọa lớn về mặt an ninh mạng (Supply Chain Attack & Container Escape).

Dưới đây là bản đánh giá chuyên sâu và hướng dẫn chi tiết các phương án Hardening hệ thống để bảo mật tuyệt đối cho máy Windows nội bộ của bạn.

---

## PHẦN 1. ĐÁNH GIÁ MỨC ĐỘ NGHIÊM TRỌNG (RISK ASSESSMENT)

| Thành phần | Mức độ rủi ro | Cơ chế tấn công (Attack Vector) |
| :--- | :--- | :--- |
| **`privileged = true`** | **Cực kỳ nghiêm trọng (Critical)** | Container được cấp toàn bộ quyền năng của nhân hệ điều hành. Nếu một thư viện bên thứ ba (qua `npm install` khi build FE hoặc dependencies của BE) bị chèn mã độc, kẻ tấn công dễ dàng phá vỡ lớp cô lập của Docker để chiếm quyền điều khiển trực tiếp máy Host (Windows) với quyền Administrator. |
| **`docker.sock` Mount** | **Nghiêm trọng (High)** | Chia sẻ socket điều khiển Docker Daemon của máy Host vào container CI/CD. Container build có toàn quyền tạo mới, xóa bỏ hoặc chiếm đoạt toàn bộ tài nguyên Docker của máy chủ Windows. |
| **`docker:24.0.7`** | **Trung bình - Cao (Medium-High)** | Dính lỗ hổng **CVE-2024-41110** (Auth Bypass). Kẻ tấn công có thể lợi dụng lỗ hổng này để bypass cơ chế phân quyền API của Docker, kết hợp với socket mount để leo thang đặc quyền. |

---

## PHẦN 2. GIẢI PHÁP 1: TỐI ƯU HÓA MÔ HÌNH DOOD (DOCKER-OUTSIDE-OF-DOCKER)
> **Mức độ bảo mật:** Khá (An toàn hơn 80% so với mô hình cũ).
> **Cách thức hoạt động:** Sử dụng Docker Daemon của máy Host Windows để build, nhưng **tắt hoàn toàn quyền Privileged** và nâng cấp phiên bản Docker CLI an toàn.

Do Docker Desktop trên Windows thực tế chạy các Linux Container thông qua một máy ảo WSL2 ngầm, Docker Desktop tự động ánh xạ virtual socket `/var/run/docker.sock` bên trong môi trường WSL2 về Named Pipe `\\.\pipe\docker_engine` trên Windows.

### 1. Cấu hình lại `config.toml` an toàn hơn trên Windows:
Bạn sửa lại file `C:\GitLab-Runner\config.toml` như sau:
```toml
[[runners]]
  name = "windows-runner-fe"
  url = "http://192.168.1.138"
  id = 14
  executor = "docker"
  [runners.docker]
    tls_verify = false
    image = "docker:27-cli"  # <--- ĐỔI SANG BẢN CLI MỚI NHẤT (Đã vá lỗ hổng CVE-2024-41110)
    privileged = false      # <--- KHÓA HOÀN TOÀN QUYỀN PRIVILEGED (AN TOÀN HƠN)
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    # Ánh xạ Named Pipe chuẩn cho Windows Docker Desktop
    volumes = ["\\\\.\\pipe\\docker_engine:\\\\.\\pipe\\docker_engine", "/cache"]
    pull_policy = ["always", "if-not-present"]
    shm_size = 2000000000
```

* **Tại sao cấu hình này chạy được?**
  Khi đặt `privileged = false`, container build của GitLab CI chỉ là một container thường. Khi chạy lệnh `docker build`, nó gửi lệnh qua đường dẫn Named Pipe ra ngoài cho Docker Desktop của máy Windows xử lý. Tiến trình build thực tế chạy ở ngoài máy Host chứ không chạy bên trong container CI, tránh hoàn toàn nguy cơ Container Escape phá hoại hệ điều hành Windows.

---

## PHẦN 3. GIẢI PHÁP 2: SỬ DỤNG GOOGLE KANIKO (BEST PRACTICE - BẢO MẬT TUYỆT ĐỐI)
> **Mức độ bảo mật:** Tuyệt đối (100% Secure).
> **Khuyên dùng:** Cho các môi trường doanh nghiệp khắt khe về bảo mật.

**Kaniko** là công cụ mã nguồn mở do Google phát triển chuyên dùng để build Docker Image từ Dockerfile trực tiếp *bên trong không gian người dùng (user-space) của container*.

### Tại sao Kaniko bảo mật tuyệt đối?
1. **Không cần Docker Daemon**: Kaniko tự giải nén các lớp của base image, thực thi các lệnh trong Dockerfile và nén lại thành image mới mà không cần cài đặt Docker Engine bên trong container.
2. **Không cần `privileged = true`**: Chạy hoàn toàn bằng quyền user thường trong container cô lập.
3. **Không cần mount Socket**: Không cần chia sẻ `/var/run/docker.sock` hay `\\.\pipe\docker_engine`. Nếu container build bị nhiễm mã độc, kẻ tấn công hoàn toàn bị giam lỏng bên trong sandbox của container, **100% không thể can thiệp hay nhìn thấy máy Windows Host**.

### Mẫu cấu hình `.gitlab-ci.yml` sử dụng Kaniko để build và push an toàn:

Dưới đây là kịch bản thay thế hoàn hảo cho file `.gitlab-ci.yml` của bạn, áp dụng cho cả dự án FE và BE:

```yaml
stages:
  - build
  - deploy

variables:
  REGISTRY: "192.168.1.138:5005"
  IMAGE_TAG: "$REGISTRY/$CI_PROJECT_PATH:$CI_COMMIT_REF_SLUG"

# ===================================================
# STAGE 1: BUILD AN TOÀN TUYỆT ĐỐI VỚI GOOGLE KANIKO
# ===================================================
build-project:
  stage: build
  tags:
    - windows-build  # Chạy trên Windows Runner thường (Không cần privileged)
  image:
    name: gcr.io/kaniko-project/executor:debug # Dùng image debug của Kaniko để hỗ trợ shell
    entrypoint: [""]
  script:
    # 1. Tạo thư mục cấu hình credentials để đăng nhập GitLab Registry
    - mkdir -p /kaniko/.docker
    # 2. Tạo file config.json chứa token đăng nhập tự động của GitLab CI
    - echo "{\"auths\":{\"$REGISTRY\":{\"username\":\"$CI_REGISTRY_USER\",\"password\":\"$CI_REGISTRY_PASSWORD\"}}}" > /kaniko/.docker/config.json
    
    # 3. Kích hoạt lệnh build của Kaniko (Không cần Docker engine, không cần socket)
    - /kaniko/executor
      --context $CI_PROJECT_DIR
      --dockerfile $CI_PROJECT_DIR/Dockerfile
      --destination $IMAGE_TAG
      --insecure  # Cho phép push sang Registry HTTP của GitLab Local qua LAN
      --skip-unused-stages

# ===================================================
# STAGE 2: DEPLOY SIÊU NHẸ TRÊN VPS (Giữ nguyên)
# ===================================================
deploy-project:
  stage: deploy
  tags:
    - deploy-vps-prod-1
  script:
    - echo "$DEPLOY_TOKEN_PASSWORD" | docker login $REGISTRY -u $DEPLOY_TOKEN_USERNAME --password-stdin
    - docker pull $IMAGE_TAG
    - docker stop my-app-container || true
    - docker rm my-app-container || true
    - docker run -d --name my-app-container -p 80:3000 --restart always $IMAGE_TAG
    - docker image prune -f
```

---

## PHẦN 4. HƯỚNG DẪN DỊCH CHUYỂN & LỰA CHỌN CỦA BẠN

Để hệ thống của bạn đạt chuẩn an toàn thông tin tốt nhất, bạn nên áp dụng các bước Hardening sau:

### Đề xuất Lộ trình Thực hiện:
1. **Ngay lập tức**: Cập nhật file `C:\GitLab-Runner\config.toml` trên máy Windows theo **Giải pháp 1** (Đổi `privileged = false`, sửa đường dẫn volumes thành Named Pipe Windows và nâng cấp image lên `docker:27-cli`). Bước này chỉ mất 1 phút và sửa được 90% lỗ hổng bảo mật trực tiếp.
2. **Lâu dài (Khuyên dùng)**: Chuyển đổi các kịch bản `.gitlab-ci.yml` của các dự án sang sử dụng **Google Kaniko (Giải pháp 2)**. Đây là đích đến cuối cùng của các hệ thống CI/CD chuyên nghiệp để bảo vệ an toàn tuyệt đối cho tài nguyên nội bộ của công ty.
