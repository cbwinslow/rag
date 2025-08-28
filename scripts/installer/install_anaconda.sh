#!/usr/bin/env bash
set -euo pipefail

# install_anaconda.sh
# Install Anaconda for Linux
# Usage: bash install_anaconda.sh [install_path] [python_version]

# Default values
INSTALL_PATH="${1:-$HOME/anaconda3}"
PYTHON_VERSION="${2:-3}"
LOG_FILE="$HOME/anaconda_install.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Error function
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success function
success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
    log "SUCCESS: $1"
}

# Info function
info() {
    echo -e "${BLUE}INFO: $1${NC}"
    log "INFO: $1"
}

# Warning function
warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
    log "WARNING: $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    error "This script should not be run as root. Please run as a regular user."
fi

# Check system requirements
check_requirements() {
    info "Checking system requirements..."

    # Check if we're on Linux
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        error "This script is designed for Linux systems only."
    fi

    # Check architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH_SUFFIX="x86_64"
            ;;
        aarch64)
            ARCH_SUFFIX="aarch64"
            ;;
        *)
            error "Unsupported architecture: $ARCH. Anaconda supports x86_64 and aarch64."
            ;;
    esac

    # Check available disk space (need at least 5GB)
    AVAILABLE_SPACE=$(df "$HOME" | tail -1 | awk '{print $4}')
    if [[ $AVAILABLE_SPACE -lt 5242880 ]]; then  # 5GB in KB
        error "Insufficient disk space. Need at least 5GB available."
    fi

    # Check if curl or wget is available
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        error "Neither curl nor wget is available. Please install one of them."
    fi

    success "System requirements check passed"
}

# Get the latest Anaconda version
get_anaconda_url() {
    info "Fetching latest Anaconda version information..."

    # Anaconda installer URLs follow this pattern
    BASE_URL="https://repo.anaconda.com/archive"

    # Try to get the latest version
    if command -v curl >/dev/null 2>&1; then
        LATEST_VERSION=$(curl -s "$BASE_URL/" | grep -o 'Anaconda3-[0-9]\+\.[0-9]\+-[0-9]\+-Linux' | head -1 | sed 's/Anaconda3-//' | sed 's/-Linux//')
    elif command -v wget >/dev/null 2>&1; then
        LATEST_VERSION=$(wget -q -O - "$BASE_URL/" | grep -o 'Anaconda3-[0-9]\+\.[0-9]\+-[0-9]\+-Linux' | head -1 | sed 's/Anaconda3-//' | sed 's/-Linux//')
    fi

    if [[ -z "$LATEST_VERSION" ]]; then
        # Fallback to a known recent version
        warning "Could not fetch latest version, using fallback version"
        LATEST_VERSION="2024.06-1"
    fi

    INSTALLER_URL="$BASE_URL/Anaconda$PYTHON_VERSION-$LATEST_VERSION-Linux-$ARCH_SUFFIX.sh"
    info "Using Anaconda version: $LATEST_VERSION"
    info "Download URL: $INSTALLER_URL"
}

# Download Anaconda installer
download_installer() {
    info "Downloading Anaconda installer..."

    INSTALLER_FILE="/tmp/anaconda_installer.sh"

    if [[ -f "$INSTALLER_FILE" ]]; then
        warning "Installer file already exists, removing..."
        rm -f "$INSTALLER_FILE"
    fi

    if command -v curl >/dev/null 2>&1; then
        if ! curl -L -o "$INSTALLER_FILE" "$INSTALLER_URL"; then
            error "Failed to download Anaconda installer using curl"
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -O "$INSTALLER_FILE" "$INSTALLER_URL"; then
            error "Failed to download Anaconda installer using wget"
        fi
    fi

    # Verify download
    if [[ ! -f "$INSTALLER_FILE" ]] || [[ ! -s "$INSTALLER_FILE" ]]; then
        error "Downloaded file is empty or missing"
    fi

    # Check if file is executable
    chmod +x "$INSTALLER_FILE"

    success "Anaconda installer downloaded successfully"
}

# Install Anaconda
install_anaconda() {
    info "Installing Anaconda to: $INSTALL_PATH"

    # Check if path already exists
    if [[ -d "$INSTALL_PATH" ]]; then
        warning "Installation path already exists: $INSTALL_PATH"
        read -p "Do you want to remove it and reinstall? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_PATH"
        else
            error "Installation cancelled by user"
        fi
    fi

    # Run the installer
    info "Running Anaconda installer..."
    if ! bash "$INSTALLER_FILE" -b -p "$INSTALL_PATH"; then
        error "Anaconda installation failed"
    fi

    success "Anaconda installed successfully"
}

# Setup environment
setup_environment() {
    info "Setting up Anaconda environment..."

    # Source conda
    CONDA_SETUP="$INSTALL_PATH/bin/conda"
    if [[ ! -f "$CONDA_SETUP" ]]; then
        error "Conda executable not found at: $CONDA_SETUP"
    fi

    # Initialize conda for common shells
    SHELLS=("bash" "zsh" "fish")
    for shell in "${SHELLS[@]}"; do
        shell_rc="$HOME/.${shell}rc"
        if [[ -f "$shell_rc" ]]; then
            info "Initializing conda for $shell..."

            # Remove existing conda initialization if present
            sed -i '/# >>> conda initialize >>>/,/# <<< conda initialize <<</d' "$shell_rc" 2>/dev/null || true

            # Add new conda initialization
            cat >> "$shell_rc" << EOF

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="\$('$INSTALL_PATH/bin/conda' 'shell.$shell' 'hook' 2> /dev/null)"
if [ \$? -eq 0 ]; then
    eval "\$__conda_setup"
else
    if [ -f "$INSTALL_PATH/etc/profile.d/conda.sh" ]; then
        . "$INSTALL_PATH/etc/profile.d/conda.sh"
    else
        export PATH="$INSTALL_PATH/bin:\$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<
EOF
        fi
    done

    # Add to PATH in current session
    export PATH="$INSTALL_PATH/bin:$PATH"

    success "Environment setup completed"
}

# Verify installation
verify_installation() {
    info "Verifying Anaconda installation..."

    # Source conda in current session
    source "$INSTALL_PATH/etc/profile.d/conda.sh" 2>/dev/null || export PATH="$INSTALL_PATH/bin:$PATH"

    # Check conda command
    if ! command -v conda >/dev/null 2>&1; then
        error "conda command not found after installation"
    fi

    # Check conda info
    if ! conda info >/dev/null 2>&1; then
        error "conda info command failed"
    fi

    # Check python
    if ! command -v python >/dev/null 2>&1; then
        error "python command not found"
    fi

    # Check pip
    if ! command -v pip >/dev/null 2>&1; then
        error "pip command not found"
    fi

    success "Anaconda installation verified successfully"
}

# Create post-installation instructions
create_post_install_info() {
    info "Creating post-installation information..."

    cat << EOF

${GREEN}🎉 Anaconda installation completed successfully!${NC}

${BLUE}Installation Details:${NC}
- Location: $INSTALL_PATH
- Python Version: $PYTHON_VERSION
- Architecture: $ARCH_SUFFIX

${BLUE}Next Steps:${NC}
1. ${YELLOW}Restart your terminal${NC} or run: ${GREEN}source ~/.bashrc${NC}
2. Verify installation: ${GREEN}conda --version${NC}
3. Update conda: ${GREEN}conda update conda${NC}
4. Create your first environment: ${GREEN}conda create -n myenv python=3.9${NC}

${BLUE}Useful Commands:${NC}
- List environments: ${GREEN}conda env list${NC}
- Activate environment: ${GREEN}conda activate <env_name>${NC}
- Deactivate: ${GREEN}conda deactivate${NC}
- Install packages: ${GREEN}conda install <package>${NC}
- Search packages: ${GREEN}conda search <package>${NC}

${BLUE}Documentation:${NC}
- Official docs: https://docs.conda.io/
- Anaconda docs: https://docs.anaconda.com/

${YELLOW}Installation log saved to: $LOG_FILE${NC}

EOF
}

# Cleanup
cleanup() {
    info "Cleaning up temporary files..."
    rm -f "/tmp/anaconda_installer.sh"
    success "Cleanup completed"
}

# Main installation process
main() {
    echo -e "${BLUE}🚀 Anaconda Installer for Linux${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""

    # Create log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    log "Starting Anaconda installation"
    log "Install path: $INSTALL_PATH"
    log "Python version: $PYTHON_VERSION"

    check_requirements
    get_anaconda_url
    download_installer
    install_anaconda
    setup_environment
    verify_installation
    create_post_install_info
    cleanup

    log "Anaconda installation completed successfully"
    success "Installation completed! Please restart your terminal or run 'source ~/.bashrc'"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [install_path] [python_version]"
            echo ""
            echo "Arguments:"
            echo "  install_path    Installation directory (default: \$HOME/anaconda3)"
            echo "  python_version  Python version (2 or 3, default: 3)"
            echo ""
            echo "Examples:"
            echo "  $0                          # Install to ~/anaconda3 with Python 3"
            echo "  $0 /opt/anaconda3           # Install to /opt/anaconda3"
            echo "  $0 ~/miniconda3 3           # Install to ~/miniconda3 with Python 3"
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Run main installation
main "$@"
