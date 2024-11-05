# 🌐 Thorium Browser Installer Scripts

<div align="center">

[![Thorium Browser](https://img.shields.io/badge/Thorium-Browser-blue.svg)](https://thorium.rocks/)
[![Windows Support](https://img.shields.io/badge/Windows-0078D6?style=flat&logo=windows&logoColor=white)](https://github.com/YOUR_USERNAME/thorium-installer)
[![Linux Support](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black)](https://github.com/YOUR_USERNAME/thorium-installer)
[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat&logo=arch-linux&logoColor=white)](https://github.com/YOUR_USERNAME/thorium-installer)

Easy installation scripts for the blazing-fast [Thorium Browser](https://thorium.rocks/) - a Chromium-based browser focused on maximum performance and features.

</div>

## 🚀 Quick Installation

### 🪟 Windows
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; irm https://raw.githubusercontent.com/YOUR_USERNAME/thorium-installer/main/install-thorium.ps1 | iex
```

### 🐧 Linux
#### Debian/Ubuntu/Fedora/RHEL (Binary Installation)
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/thorium-installer/main/install-thorium.sh)"
```

#### Arch Linux and Derivatives (Build from Source)
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/thorium-installer/main/install-thorium.sh)"
```
⚠️ Note: Arch Linux installation builds from source and may take 30+ minutes depending on your system.

## ✨ Features

- 🔍 Automatic CPU architecture detection (AVX2/AVX/SSE4/SSE3)
- 📦 One-click installation and update functionality
- 🧹 Automatic cleanup of old versions
- 🛡️ Error handling and recovery
- 📊 Progress feedback and colored output
- 📂 Support for multiple installation locations
- 🔎 Registry scanning (Windows)
- 📱 Package manager detection (Linux)
- 🏗️ Source build support for Arch Linux

## 📋 Requirements

### Windows Requirements
- ⚡ PowerShell 5.1 or later
- 🔑 Administrator privileges

### Linux Requirements
#### Debian/Ubuntu
- 📦 apt package manager
- 🔧 curl, grep, pkill

#### Fedora/RHEL
- 📦 rpm package manager
- 🔧 curl, grep, pkill

#### Arch Linux
- 📦 pacman package manager
- 🔧 Base development tools
- 💾 At least 10GB free disk space
- 🔨 Required build dependencies:
  - base-devel
  - git
  - python
  - ninja
  - curl
  - nss
  - libxss
  - gtk3
  - libxrandr
  - And other dependencies (automatically installed)

## 📝 Notes

- 🔄 Automatic CPU architecture detection for optimal performance
- 🔍 Smart detection of existing installations
- 🛑 Safe process handling during updates
- 🧹 Automatic cleanup of temporary files
- 🏗️ Source compilation optimized for your CPU architecture (Arch Linux)

## 💬 Support

<div align="center">

[![Issues](https://img.shields.io/badge/Issues-Report_Here-red.svg)](https://github.com/YOUR_USERNAME/thorium-installer/issues)
[![Thorium](https://img.shields.io/badge/Thorium-Official_Repo-orange.svg)](https://github.com/Alex313031/thorium)

**Installation Issues?** Open an issue in this repository  
**Browser Issues?** Visit the [official Thorium repository](https://github.com/Alex313031/thorium)

</div>

## 🏗️ Build Times

Expected build times for Arch Linux installations:
- 💪 High-end CPU (8+ cores): ~30 minutes
- 🏃 Mid-range CPU (4-6 cores): ~45-60 minutes
- 🚶 Entry-level CPU (2-4 cores): 60+ minutes

These times are approximate and depend on your system's specifications and load.