<div align="center">

# 🚀 Burp Suite Professional — Automated Setup & Launcher

[![Platform](https://img.shields.io/badge/Platform-Kali%20Linux%20%7C%20Debian%20%7C%20Ubuntu%20%7C%20Arch%20%7C%20Fedora-1793d1?style=for-the-badge&logo=linux&logoColor=white)](https://www.kali.org/)
[![Java](https://img.shields.io/badge/Runtime-Oracle%20JDK%2023-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)](https://www.oracle.com/java/)
[![Shell](https://img.shields.io/badge/Script-Bash%205.0+-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Burp Suite](https://img.shields.io/badge/Burp%20Suite-v2023.3.3%20%7C%20v2025.12.3-FF6633?style=for-the-badge&logo=portswigger&logoColor=white)](https://portswigger.net/burp)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)

**An all-in-one automation script and comprehensive manual guide for installing, configuring, and launching Burp Suite Professional on modern Linux distributions.**

[✨ Quick Start](#-quick-start) • [✨ Features](#-features) • [📋 System Requirements](#-system-requirements--compatibility) • [🚀 Automated Setup](#-method-1-automated-1-click-installation-recommended) • [📖 Manual Setup](#-method-2-complete-manual-step-by-step-guide) • [🔑 Activation](#-activation-walkthrough) • [🖥️ Usage](#-how-to-launch-burp-suite-pro) • [❓ Troubleshooting](#-troubleshooting--faq)

</div>

---

## 📑 Table of Contents

- [✨ Quick Start](#-quick-start)
- [✨ Features](#-features)
- [📋 System Requirements & Compatibility](#-system-requirements--compatibility)
- [🚀 Method 1: Automated 1‑Click Installation (Recommended)](#-method-1-automated-1-click-installation-recommended)
  - [Step 1: Clone the Repository](#1-clone-the-repository)
  - [Step 2: Run the Installer](#2-run-the-installer)
- [📖 Method 2: Complete Manual Step‑by‑Step Guide](#-method-2-complete-manual-step-by-step-guide)
  - [Step 1: Install Oracle JDK 23](#step-1--install--configure-oracle-jdk-23)
  - [Step 2: Prepare Directories & Download JARs](#step-2--prepare-directory--download-burp-suite--keygen)
  - [Step 3: Launch Keygen & Activate](#step-3--launch-keygen--activate-burp-suite)
  - [Step 4: Create Startup Script, Symlink & Desktop Shortcut](#step-4--create-startup-script-symlink--desktop-shortcut)
- [🔑 Activation Walkthrough](#-activation-walkthrough)
- [🖥️ How to Launch Burp Suite Pro](#-how-to-launch-burp-suite-pro)
- [📁 Repository & Directory Layout](#-repository--directory-layout)
- [🔍 Verification & Diagnostics](#-verification--diagnostics)
- [⚙️ Advanced JVM Configuration](#-advanced-jvm-configuration--performance-tuning)
- [❓ Troubleshooting & FAQ](#-troubleshooting--faq)
- [🤝 Contributing](#-contributing)
- [📜 Disclaimer & License](#-disclaimer)

---

## ✨ Quick Start

> **The fastest way to get Burp Suite Professional up and running**

```bash
git clone https://github.com/your-username/burpsuite-pro-setup.git
cd burpsuite-pro-setup
sudo bash burp-pro-setup.sh
