# 🛡️ Star-Bash VPS Security & Health Audit Tool

A professional, high-performance Bash script designed to run automated security audits, process healthchecks, and integrity scans on Linux VPS instances. It analyzes configuration flaws, active malware indicators, network exposure, persistence vectors, and abnormal system parameters.

---

## ✨ Features

- **📊 System & OS Identification**: Collects platform parameters, virtualization layer, uptime, and kernel info.
- **⚡ Performance & Metric Anomalies**: Flags extreme CPU load factors, high RAM usage, partition constraints, and lists top system-consuming processes.
- **🔌 Network & Socket Audits**: Extracts active open ports (TCP/UDP), associated system services, and verifies firewall layers (`ufw`, `firewalld`, `iptables`).
- **🔑 SSH & Authentication Hardening**: Checks critical configuration rules in SSH (`PermitRootLogin`, custom port usage, key-based settings) and extracts failed login rates and brute-force IPs.
- **🪲 Malware & Crypto-miner Detection**: Scans for active processes executing out of temporary directories, targets popular mining signatures (`xmrig`, etc.), and reports open deleted file descriptors.
- **🔄 Persistence & Cron Audits**: Parses system-wide/user crontabs and checks core environment hooks for suspicious shell redirects.
- **🛡️ Privilege Escalation Vector Audits**: Highlights system directories containing world-writable binaries or passwordless `sudo` authorizations.
- **📝 Automatic Logging**: Generates persistent `.log` reports with timestamps in the local directory under `./security_logs/`.
- **🛠️ Interactive Remediation & Hardening**: Provides a guided command-line menu at the end of the scan to automatically fix security issues (Install Fail2Ban, Change SSH ports and disable password authentication, Install security audit tools, and perform secure service reboots).

---

## 🚀 Quick Start Guide

### 1. Upload the Script to Your VPS
You can copy the script contents or use `scp` or `curl` to fetch it directly:
```bash
# Example using scp from your local computer
scp d:/script/star-bash/security/security_check.sh user@vps_ip:/tmp/
```
Or simply create a file on your VPS and paste the content:
```bash
nano security_check.sh
```

### 2. Make the Script Executable
Give execution rights to the script on your VPS:
```bash
chmod +x security_check.sh
```

### 3. Run the Security Audit
Execute the script using root permissions (`sudo` is highly recommended to fetch sensitive system configs and raw authorization logs):
```bash
sudo ./security_check.sh
```

---

## 📁 File Structure

```text
d:\script\star-bash\security\
├── security_check.sh   # Core audit script (Bash)
└── README.md           # Documentation and Guide
```

---

## 🎨 Interactive CLI Output Example

The script features a beautifully styled, color-coded interactive layout:
- `[✔] Success/Secure`: Core configurations are robust and standard rules are followed.
- `[ℹ] Info`: Basic parameters or diagnostic metrics.
- `[⚠] Warning`: Potential gaps in configurations or elevated metrics (e.g., SSH standard port).
- `[✘] Critical`: Severe security risks (e.g., root password logins permitted or process anomalies).
