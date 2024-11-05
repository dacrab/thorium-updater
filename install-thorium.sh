#!/bin/bash

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error handling setup
set -euo pipefail

# Error handler function
error_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5
    
    echo -e "\n${RED}An error occurred in script${NC}" >&2
    echo -e "${RED}Error on or near line ${line_no}${NC}" >&2
    echo -e "${RED}Last command: ${last_command}${NC}" >&2
    echo -e "${RED}Exit code: ${exit_code}${NC}" >&2
    
    cleanup
    
    echo -e "\n${YELLOW}Press any key to exit...${NC}" >&2
    read -n 1 -s -r
    exit "$exit_code"
}

# Cleanup function
cleanup() {
    if [[ -d "/tmp/thorium-install" ]]; then
        rm -rf "/tmp/thorium-install"
    fi
}

# Set up error and interrupt handlers
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR
trap 'echo -e "\n${YELLOW}Script interrupted by user. Press any key to exit...${NC}" >&2; read -n 1 -s -r; exit 1' SIGINT SIGTERM

# System detection functions
check_requirements() {
    local required_commands=("curl" "grep" "pkill")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        echo -e "${RED}Error: Required commands not found: ${missing_commands[*]}${NC}" >&2
        echo -e "${YELLOW}Please install the missing packages and try again.${NC}" >&2
        exit 1
    fi
}

detect_cpu_architecture() {
    echo -e "${CYAN}Detecting CPU capabilities...${NC}"
    
    if ! [ -f "/proc/cpuinfo" ]; then
        echo -e "${RED}Error: Cannot access CPU information${NC}" >&2
        exit 1
    fi
    
    if grep -q "avx2" /proc/cpuinfo; then
        echo "AVX2"
    elif grep -q "avx" /proc/cpuinfo; then
        echo "AVX"
    elif grep -q "sse4_2\|sse4_1" /proc/cpuinfo; then
        echo "SSE4"
    elif grep -q "sse3" /proc/cpuinfo; then
        echo "SSE3"
    else
        echo -e "${RED}Error: Unsupported CPU architecture${NC}" >&2
        exit 1
    fi
}

# Function to detect package manager
detect_package_manager() {
    if command -v pacman &> /dev/null; then
        echo "pkg"
    elif command -v apt &> /dev/null; then
        echo "deb"
    elif command -v rpm &> /dev/null; then
        echo "rpm"
    else
        echo -e "${RED}Error: No supported package manager found${NC}" >&2
        echo -e "${YELLOW}This script supports: pacman (Arch/Manjaro), apt (Debian/Ubuntu) and rpm (Fedora/RHEL)${NC}" >&2
        exit 1
    fi
}

# Version management functions
get_installed_version() {
    if ! command -v thorium-browser &> /dev/null; then
        echo ""
        return
    fi
    
    timeout 5s thorium-browser --version | grep -oP "Thorium \K[0-9.]+" || {
        echo -e "${YELLOW}Warning: Could not determine current Thorium version${NC}" >&2
        echo ""
    }
}

get_latest_version() {
    local max_retries=3
    local retry_count=0
    local latest_release=""
    
    while [ $retry_count -lt $max_retries ]; do
        latest_release=$(curl -sf "https://api.github.com/repos/Alex313031/Thorium/releases/latest" | grep -oP '"tag_name": "\K[^"]+' || true)
        
        if [ -n "$latest_release" ]; then
            echo "$latest_release"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        echo -e "${YELLOW}Retry $retry_count of $max_retries: Failed to fetch latest version${NC}" >&2
        sleep 2
    done
    
    echo -e "${RED}Error: Failed to fetch latest version after $max_retries attempts${NC}" >&2
    exit 1
}

# Function to download and install Thorium
install_thorium() {
    local arch=$1
    local pkg_type=$2
    local version=$3
    local temp_dir="/tmp/thorium-install"
    
    # Create temp directory
    mkdir -p "$temp_dir"
    cd "$temp_dir" || exit 1
    
    # Remove the 'M' prefix from version if present
    version="${version#M}"
    
    if [ "$pkg_type" = "pkg" ]; then
        echo -e "${YELLOW}Note: Building from source on Arch Linux may take 30+ minutes depending on your system${NC}"
        echo -e "${YELLOW}Note: You'll need at least 10GB of free disk space for the build process${NC}"
        
        # For Arch Linux, we'll build from source
        echo -e "${CYAN}Installing build dependencies...${NC}"
        sudo pacman -Sy --needed --noconfirm base-devel git python ninja curl nss libxss gtk3 libxrandr \
            cups dbus libgnome-keyring alsa-lib xdg-utils libcups libdrm snappy jsoncpp \
            fontconfig libxml2 libxslt minizip nspr nss re2 speech-dispatcher pciutils \
            libpulse || {
            echo -e "${RED}Error: Failed to install build dependencies${NC}" >&2
            exit 1
        }

        # Download source code
        local source_url="https://github.com/Alex313031/Thorium/archive/refs/tags/M${version}.tar.gz"
        echo -e "${CYAN}Downloading source code...${NC}"
        if ! curl -L --retry 3 --retry-delay 2 -o "thorium-source.tar.gz" "$source_url"; then
            echo -e "${RED}Error: Failed to download source code${NC}" >&2
            exit 1
        }

        # Extract source
        tar xf thorium-source.tar.gz
        cd "Thorium-M${version}" || exit 1

        # Create build directory and set up environment
        mkdir -p build
        cd build || exit 1

        # Configure build based on CPU architecture
        echo -e "${CYAN}Configuring build for ${arch}...${NC}"
        
        local build_args=()
        case "$arch" in
            "AVX2")
                build_args+=("--enable-avx2")
                ;;
            "AVX")
                build_args+=("--enable-avx")
                ;;
            "SSE4")
                build_args+=("--enable-sse4")
                ;;
            "SSE3")
                build_args+=("--enable-sse3")
                ;;
        esac

        # Run configure script with appropriate flags
        ../configure.sh "${build_args[@]}" || {
            echo -e "${RED}Error: Build configuration failed${NC}" >&2
            exit 1
        }

        # Build Thorium
        echo -e "${CYAN}Building Thorium (this will take a while)...${NC}"
        ninja -C out/Release thorium || {
            echo -e "${RED}Error: Build failed${NC}" >&2
            exit 1
        }

        echo -e "${CYAN}Installing Thorium...${NC}"
        # Remove old installation if exists
        sudo rm -rf /opt/thorium || true
        
        # Install the built binary and resources
        sudo mkdir -p /opt/thorium
        sudo cp -r out/Release/* /opt/thorium/
        
        # Create symbolic link
        sudo ln -sf /opt/thorium/thorium-browser /usr/bin/thorium-browser

        # Create desktop entry
        cat << EOF | sudo tee /usr/share/applications/thorium-browser.desktop
[Desktop Entry]
Version=1.0
Name=Thorium Browser
Comment=Browse the World Wide Web
GenericName=Web Browser
Keywords=Internet;WWW;Browser;Web;Explorer
Exec=/usr/bin/thorium-browser %U
Terminal=false
X-MultipleArgs=false
Type=Application
Icon=/opt/thorium/product_logo_256.png
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
EOF

    elif [ "$pkg_type" = "deb" ]; then
        # Existing deb installation logic...
        # ... [keep existing deb installation code]
    else
        # Existing rpm installation logic...
        # ... [keep existing rpm installation code]
    fi
    
    # Verify installation
    if ! command -v thorium-browser &> /dev/null; then
        echo -e "${RED}Error: Installation verification failed${NC}" >&2
        exit 1
    fi
    
    # Cleanup
    cd - > /dev/null
    cleanup
}

# Function to close Thorium processes
close_thorium() {
    echo -e "\n${CYAN}Closing Thorium browser...${NC}"
    
    # Kill all Thorium processes
    pkill -f "thorium" || true
    pkill -f "thorium-browser" || true
    
    # Wait for processes to close
    local max_wait=10
    local count=0
    while pgrep -f "thorium" > /dev/null && [ $count -lt $max_wait ]; do
        echo "Waiting for Thorium to close... ($count/$max_wait)"
        sleep 1
        count=$((count + 1))
    done
    
    # Force kill if still running
    if pgrep -f "thorium" > /dev/null; then
        echo -e "${YELLOW}Force closing Thorium...${NC}"
        pkill -9 -f "thorium" || true
        pkill -9 -f "thorium-browser" || true
        sleep 2
    fi
}

# Function to compare versions
compare_versions() {
    local current=$1
    local latest=$2
    
    # Remove 'M' prefix and any non-version characters
    current=$(echo "$current" | sed 's/^M//' | grep -oP '[0-9.]+')
    latest=$(echo "$latest" | sed 's/^M//' | grep -oP '[0-9.]+')
    
    if [ "$current" = "$latest" ]; then
        return 0
    fi
    return 1
}

# Main execution
main() {
    echo -e "${CYAN}=== Thorium Browser Installer/Updater ===${NC}"
    echo "----------------------------------------"
    
    check_requirements
    
    CPU_ARCH=$(detect_cpu_architecture)
    PKG_TYPE=$(detect_package_manager)
    
    echo -e "${CYAN}System Information:${NC}"
    echo "CPU Architecture: $CPU_ARCH"
    echo "Package Type: $PKG_TYPE"
    
    CURRENT_VERSION=$(get_installed_version)
    LATEST_VERSION=$(get_latest_version)
    
    if [ -n "$CURRENT_VERSION" ]; then
        echo -e "\n${CYAN}Current Thorium Installation:${NC}"
        echo "Version: $CURRENT_VERSION"
        
        if compare_versions "$CURRENT_VERSION" "$LATEST_VERSION"; then
            echo -e "\n${GREEN}You are already running the latest version of Thorium!${NC}"
            echo -e "${GREEN}Version: $CURRENT_VERSION${NC}"
            exit 0
        fi
        
        echo -e "\n${YELLOW}New version available: $LATEST_VERSION${NC}"
        read -rp "Would you like to update? (Y/n) " response
        if [[ "$response" =~ ^[Nn]$ ]]; then
            exit 0
        fi
        
        close_thorium
    else
        echo -e "\n${CYAN}Installing Thorium Browser...${NC}"
        echo -e "Detected CPU Architecture: ${GREEN}$CPU_ARCH${NC}"
        echo -e "Installing version: ${GREEN}$LATEST_VERSION${NC}"
        read -rp "Would you like to proceed with installation? (Y/n) " response
        if [[ "$response" =~ ^[Nn]$ ]]; then
            exit 0
        fi
    fi
    
    install_thorium "$CPU_ARCH" "$PKG_TYPE" "$LATEST_VERSION"
    
    echo -e "\n${GREEN}Installation/Update complete!${NC}"
    echo "----------------------------------------"
}

# Run main function
main "$@"