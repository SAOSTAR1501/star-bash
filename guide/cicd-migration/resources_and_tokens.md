# Bản đồ Tài nguyên & Token trong Hệ thống CI/CD mới

Tài liệu này hệ thống hóa toàn bộ các yêu cầu về **Tài nguyên phần cứng**, **Cổng mạng (Ports)**, **Tài khoản hệ thống** và các loại **Token / Biến CI/CD** cần thiết cho từng thành phần trong luồng CI/CD tối ưu mới.

---

## 1. Bản đồ Yêu cầu cho Từng Thành phần

### 🦊 A. GitLab Local Server (`192.168.1.138`)
Đóng vai trò là trung tâm điều phối pipeline, quản lý mã nguồn và lưu trữ Docker Image (Container Registry).

* **Tài nguyên & Cổng mạng (Ports)**:
  * **Cổng `80` / `443`**: Giao diện Web GitLab UI và API (WARP access).
  * **Cổng `2222`**: Kết nối Git clone/pull qua SSH (cấu hình trong Star-Bash).
  * **Cổng `5005`**: Cổng dịch vụ **Container Registry** (để Windows push và VPS pull image).
  * **Ổ cứng (Disk Space)**: Cần nhiều dung lượng (khuyên dùng tối thiểu >50GB trống) vì Registry sẽ lưu trữ nhiều phiên bản Docker Image theo thời gian.
* **Tokens & Quyền hạn cần cấp**:
  * **Runner Registration Token**: Lấy tại mục *Admin Area -> CI/CD -> Runners* (dùng để liên kết các máy Windows và VPS Runner vào GitLab).
  * **Deploy Tokens**: Tạo trực tiếp tại từng dự án với quyền **`read_registry`** để cấp quyền pull image an toàn cho VPS.

---

### 🖥️ B. Máy Windows Runner (Central Builder)
Đóng vai trò là máy chủ biên dịch và đóng gói Docker Image thô thành sản phẩm hoàn chỉnh.

* **Tài nguyên & Cổng mạng (Ports)**:
  * **Phần cứng**: Cần cấu hình mạnh (tối thiểu 4-8 Cores CPU, 8-16GB RAM) để xử lý compile code Next.js/Docker nhanh chóng mà không bị nghẽn.
  * **Phần mềm**: Cài đặt **Docker Desktop** (hoặc chạy Docker Engine trực tiếp trong **WSL2**).
  * **Mạng**: Kết nối trực tiếp qua mạng LAN nội bộ tới GitLab Local (`192.168.1.138`) thông qua cổng `80` (API) và `5005` (Registry) mà không cần qua Cloudflare WARP (giúp tối ưu băng thông và giảm độ trễ tối đa).
* **Tokens & Quyền hạn cần cấp**:
  * Liên kết với GitLab bằng **Runner Registration Token** (đăng ký với tag `windows-build`).
  * **`$CI_JOB_TOKEN`**: Đây là token tự động sinh ra theo từng Job trong GitLab CI. Windows Runner sẽ tự động dùng token này để login vào Registry và push image lên mà bạn không cần phải tạo thủ công.

---

### ☁️ C. Các Máy chủ VPS (Deployer siêu nhẹ)
Đóng vai trò là môi trường vận hành chạy sản phẩm cuối, tuyệt đối không tham gia biên dịch.

* **Tài nguyên & Cổng mạng (Ports)**:
  * **Phần cứng**: Cực kỳ nhẹ nhàng (1-2 Cores, 1-2GB RAM vẫn chạy mượt mà). VPS không tốn tài nguyên cho quá trình build nữa.
  * **Phần mềm**: Chỉ cần cài đặt **Docker Engine** (không cần cài Node.js, NPM, PM2 trực tiếp nếu đã Docker hóa).
  * **Mạng**: Kích hoạt Cloudflare WARP để kết nối nội bộ tới Registry cổng `5005` qua WARP.
* **Tokens & Quyền hạn cần cấp**:
  * Liên kết VPS Runner bằng **Runner Registration Token** (đăng ký với tag dạng `deploy-vps-prod-1`, chọn executor là `shell`).
  * **Tài khoản hệ thống**: User chạy runner trên VPS là `gitlab-runner` (không root) và bắt buộc phải nằm trong group `docker` (`usermod -aG docker gitlab-runner`).

---

## 2. Bảng Quản lý Tập trung Các Biến CI/CD (GitLab Variables)

Để luồng CI/CD chạy tự động và an toàn, bạn hãy cấu hình các biến sau trên giao diện GitLab UI tại mục **`Settings -> CI/CD -> Variables`** cho từng dự án:

| Tên biến (Variable Key) | Loại (Type) | Giá trị cần điền (Value) | Phạm vi áp dụng | Mục đích sử dụng |
| :--- | :--- | :--- | :--- | :--- |
| **`DEPLOY_TOKEN_USERNAME`** | `Variable` | Username của Deploy Token vừa tạo | Toàn bộ các nhánh | Dùng để VPS login vào Registry lấy image về. |
| **`DEPLOY_TOKEN_PASSWORD`** | `Variable` (Masked) | Password của Deploy Token | Toàn bộ các nhánh | Mật khẩu giải mã registry (Cần chọn *Masked* để ẩn đi). |
| **`ENV_LOCAL_MAIN`** | `File` hoặc `Variable` | Nội dung file `.env` của nhánh `main` | Nhánh `main` / `master` | File môi trường thực tế khi chạy dự án. |
| **`ENV_LOCAL_DEVELOP`** | `File` hoặc `Variable` | Nội dung file `.env` của nhánh `develop` | Nhánh `develop` | File môi trường chạy thử nghiệm. |
| **`ENV_DOCKER_MAIN`** | `File` hoặc `Variable` | Nội dung file `.env.docker` của nhánh `main` | Nhánh `main` (Dành cho BE) | Các cấu hình đặc thù dành riêng cho Docker. |

---

## 3. Bản tóm tắt luồng quyền hạn bảo mật (Security Privilege Matrix)

| Tiến trình (Process) | Quyền hạn mô hình cũ | Quyền hạn mô hình mới | Đánh giá mức độ an toàn |
| :--- | :--- | :--- | :--- |
| **Docker Build** | Chạy trực tiếp trên VPS với quyền `root` / `sudo` của user deployer | Chạy độc lập trên container của máy Windows Runner | **An toàn tuyệt đối** (VPS không còn nguy cơ bị tấn công leo thang đặc quyền qua docker socket trong lúc build). |
| **Đăng nhập Registry** | Sử dụng tài khoản GitLab cá nhân | Sử dụng Deploy Token giới hạn quyền `read_registry` | **Rất an toàn** (Nếu VPS bị lộ token, hacker cũng chỉ có thể đọc image của dự án đó, không thể đẩy code độc hại lên và không thể xem source code gốc). |
| **Ghi file `.env`** | Dùng giao thức `scp` truyền file qua mạng | Shell Runner ghi trực tiếp cục bộ trên VPS | **An toàn** (Tránh việc truyền dữ liệu nhạy cảm qua mạng internet hoặc SSH). |
