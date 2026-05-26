# 📝 Changelog

All notable changes to this repository will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - 2026-05-26

### Added
- **`run.sh` Central Orchestrator**: Added a central landing dashboard in the root directory. Users can simply run `sudo bash run.sh` to get an interactive menu and choose between running the VPS Security Audit, the Interactive Site Deployer, or the Quick Site Deployer.
- **`deploy-fe/` Deployment Directory**: Introduced automation scripts to streamline front-end site deployment on VPS environments.
- **`quick_setup_site.sh`**: A command-line argument-based Nginx site configuration script.
  - Generates Nginx reverse proxy configuration at `/etc/nginx/sites-available/` and enables it.
  - Automatically writes PM2 `ecosystem.config.js` in the project directory using custom port.
  - Installs SSL security certificates using Certbot non-interactively.
  - Usage format: `sudo bash quick_setup_site.sh vsoftware.vn 3008 yes-eco`.
- **`interactive_setup_site.sh`**: A premium, step-by-step interactive CLI wizard.
  - Guides users visually through setting domains, port configurations, and generating PM2 ecosystems.
  - **Intelligent Directory Chooser**: Scans the active folder and `/var/www/` for available folders, displaying them as a numbered list to easily select the project root, while still supporting custom inputs.
  - Offers toggles to skip/enable Nginx site configuration and Certbot SSL certificate issuance.

---

## [1.0.0] - 2026-05-26

### Added
- **`security/` Audit Directory**: Established automated diagnostic tools for monitoring and hardening Linux VPS environments.
- **`security_check.sh`**: Core audit script analyzing OS parameters, memory usage, open ports, SSH parameters, brute-force logs, active cryptominers, persistence vectors, and SUID directories.
- **Interactive Hardening Remediation Menu**: Integrated action system inside `security_check.sh` to fix security gaps directly from the terminal:
  - Option 1: Installs and starts `Fail2Ban` to mitigate brute-force SSH logins.
  - Option 2: Configures secure SSH rules (Port swap, `PasswordAuthentication no`, and `PermitRootLogin prohibit-password`) with automated syntax-checks (`sshd -t`) before applying updates.
  - Option 3: Details secure configurations for containerized Docker ports (Docker-UFW bypass solutions).
  - Option 4: Installs advanced security audit tools (`rkhunter`, `chkrootkit`, `clamav`).
  - Option 5: Handles safe system reboots to complete pending RAM updates.
- **`security/README.md`**: Step-by-step instructional guide detailing usage parameters, security levels, and output interpretations.
