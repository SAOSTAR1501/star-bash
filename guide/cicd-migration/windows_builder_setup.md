# HƯỚNG DẪN CẤU HÌNH CHI TIẾT: MÁY CHỦ BUILDER WINDOWS
> **Vai trò:** Nhận nhiệm vụ nặng biên dịch mã nguồn, đóng gói Docker Image và push lên GitLab Local Registry (`192.168.1.138:5005`).

Tài liệu này hướng dẫn chi tiết từng bước thiết lập trên máy Windows nội bộ của bạn (nằm trong cùng mạng LAN với GitLab Local), từ cài đặt Docker, cấu hình mạng LAN trực tiếp đến thiết lập GitLab Runner chạy chế độ Docker-in-Docker (DinD).

---

## BƯỚC 1: KẾT NỐI MẠNG NỘI BỘ (LAN) TRỰC TIẾP TỚI GITLAB
Vì máy Windows nằm chung mạng nội bộ (LAN) với máy chủ GitLab Local (`192.168.1.138`), bạn **không cần cài đặt hay bật Cloudflare WARP** trên máy Windows này. Kết nối trực tiếp qua LAN giúp tốc độ truyền tải Docker image cực kỳ nhanh và hoàn toàn không bị giới hạn băng thông.

* **Kiểm tra kết nối trực tiếp**: Mở PowerShell trên Windows và chạy lệnh kiểm tra đường truyền LAN:
  ```powershell
  Test-NetConnection -ComputerName 192.168.1.138 -Port 80
  ```
  Nếu kết quả hiển thị `TcpTestSucceeded : True` nghĩa là máy Windows đã kết nối trực tiếp thành công tới GitLab Local.

---

## BƯỚC 2: CÀI ĐẶT VÀ CẤU HÌNH DOCKER DESKTOP

1. Tải và cài đặt [Docker Desktop cho Windows](https://www.docker.com/products/docker-desktop/). Trong quá trình cài đặt, chọn tích hợp **WSL2 (Windows Subsystem for Linux)**.
2. Sau khi cài đặt thành công, mở Docker Desktop -> Click biểu tượng bánh răng **Settings** ở góc trên bên phải.
3. Chọn thẻ **Docker Engine**.
4. Thêm địa chỉ Registry nội bộ HTTP vào cấu hình JSON dưới khóa `"insecure-registries"` để cho phép push image qua HTTP LAN:
   ```json
   {
     "builder": {
       "gc": {
         "defaultKeepStorage": "20GB",
         "enabled": true
       }
     },
     "experimental": false,
     "insecure-registries": [
       "192.168.1.138:5005"
     ]
   }
   ```
5. Click **Apply & restart** ở góc dưới cùng bên phải để áp dụng cấu hình.

---

## BƯỚC 3: CÀI ĐẶT GITLAB RUNNER TRÊN WINDOWS

1. Tạo một thư mục cố định tại gốc ổ cứng C đặt tên là `GitLab-Runner`:
   ```powershell
   New-Item -Path "C:\" -Name "GitLab-Runner" -ItemType "Directory" -Force
   ```
2. Tải tệp thực thi GitLab Runner chính thức phiên bản Windows 64-bit:
   * URL tải trực tiếp: [gitlab-runner-windows-amd64.exe](https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-windows-amd64.exe)
   * Lưu tệp này vào thư mục `C:\GitLab-Runner` và đổi tên tệp thành `gitlab-runner.exe`.
3. Mở **PowerShell với quyền Administrator** và chuyển vào thư mục vừa tạo:
   ```powershell
   cd C:\GitLab-Runner
   ```

---

## BƯỚC 4: ĐĂNG KÝ RUNNER VỚI GITLAB LOCAL

1. Chạy lệnh đăng ký trong PowerShell quyền Administrator:
   ```powershell
   .\gitlab-runner.exe register
   ```
2. Điền đầy đủ các thông tin cấu hình tương tác thực tế như sau:
   * **Enter the GitLab instance URL**: Điền `http://192.168.1.138` (địa chỉ GitLab Local LAN).
   * **Enter the registration token**: Dán token đăng ký lấy từ GitLab UI.
   * **Enter a name for the runner (description)**: Điền `windows-runner-fe` (hoặc tên máy tính của bạn).
   * **Enter tags for the runner**: Nhập **`windows-build,heavy-builder`** (ngăn cách bằng dấu phẩy, dùng để điều phối công việc build).
   * **Enter optional maintenance note**: Nhấn [Enter] để bỏ qua.
   * **Enter an executor**: Nhập **`docker`**.
   * **Enter the default Docker image**: Nhập **`docker:24.0.7`** (image nền chạy đóng gói).

---

## BƯỚC 5: CẤU HÌNH CONFIG.TOML (BẮT BUỘC ĐỂ BUILD DOCKER)

Sau khi đăng ký thành công, bạn **bắt buộc** phải chỉnh sửa file cấu hình để cho phép chạy Docker-in-Docker (DinD).

1. Mở file **`C:\GitLab-Runner\config.toml`** bằng Notepad.
2. Cập nhật và lưu lại file cấu hình chuẩn xác như sau:

```toml
concurrent = 2  # Cho phép build tối đa 2 job song song (FE và BE) cùng lúc
check_interval = 0
shutdown_timeout = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "windows-runner-fe"
  url = "http://192.168.1.138"
  id = 14
  token = "YOUR_SECRET_TOKEN"  # Giữ nguyên token tự sinh ra của bạn
  token_obtained_at = 2026-05-30T03:53:25Z
  token_expires_at = 0001-01-01T00:00:00Z
  executor = "docker"
  [runners.cache]
    MaxUploadedArchiveSize = 0
    [runners.cache.s3]
      AssumeRoleMaxConcurrency = 0
    [runners.cache.gcs]
    [runners.cache.azure]
  [runners.docker]
    tls_verify = false
    image = "docker:24.0.7"
    privileged = true   # <--- ĐẶT TRUE ĐỂ CẤP QUYỀN BUILD IMAGE
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    volumes = ["/cache", "/var/run/docker.sock:/var/run/docker.sock"] # <--- MOUNT DOCKER SOCKET ĐỂ DÙNG CHUNG ENGINE
    pull_policy = ["always", "if-not-present"]  # <--- TỐI ƯU PULL IMAGE NỀN TRÊN MẠNG LAN
    volume_keep = false
    shm_size = 2000000000  # Cấp thêm 2GB Shared Memory tránh crash khi Next.js build nặng
    network_mtu = 0
```

---

## BƯỚC 6: CÀI ĐẶT RUNNER DƯỚI DẠNG WINDOWS SERVICE

Để Runner tự động khởi chạy cùng hệ thống Windows và chạy ngầm bảo mật:

1. **Cài đặt dịch vụ vào Windows (Bắt buộc phải chạy trước)**:
   ```powershell
   .\gitlab-runner.exe install
   ```
   > [!CAUTION]
   > Nếu bạn không chạy lệnh `install` trước mà chạy trực tiếp lệnh `restart` hoặc `start`, hệ thống sẽ báo lỗi:
   > `FATAL: Failed to restart gitlab-runner: The specified service does not exist as an installed service.`

2. **Khởi chạy dịch vụ ngầm**:
   ```powershell
   .\gitlab-runner.exe start
   ```

3. **Kiểm tra trạng thái hoạt động**:
   ```powershell
   .\gitlab-runner.exe status
   ```
   *Nếu hiển thị: `Runtime platform ... Service is running` là thành công!*

4. **Lưu ý sau này**: Nếu bạn thay đổi file `config.toml`, hãy khởi động lại bằng lệnh:
   ```powershell
   .\gitlab-runner.exe restart
   ```

---

## BƯỚC 7: KIỂM TRA ĐĂNG KÝ TRÊN GITLAB UI

1. Truy cập vào trang quản trị GitLab Local của bạn bằng trình duyệt.
2. Đi tới phần **Admin Area** -> **Runners** (hoặc Dự án của bạn -> **Settings** -> **CI/CD** -> **Runners**).
3. Bạn sẽ nhìn thấy Runner **Windows Heavy Builder** hiển thị với trạng thái chấm màu xanh lá cây tượng trưng cho hoạt động trực tuyến (Online) và có đầy đủ các tag `windows-build` và `heavy-builder`.

Máy Windows của bạn đã hoàn thành thiết lập và sẵn sàng nhận mọi công việc build mã nguồn nặng nhọc nhất từ hệ thống!
