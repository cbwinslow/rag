#!/usr/bin/env bash
set -euo pipefail

# setup_dev_environment.sh
# Comprehensive development environment setup script
# Installs Anaconda, development tools, and configures the system

# Configuration
LOG_FILE="/var/log/dev_env_setup.log"
INSTALL_MINICONDA="${INSTALL_MINICONDA:-true}"
INSTALL_DOCKER="${INSTALL_DOCKER:-true}"
INSTALL_NODEJS="${INSTALL_NODEJS:-true}"
INSTALL_RUST="${INSTALL_RUST:-true}"
INSTALL_GO="${INSTALL_GO:-true}"
INSTALL_NEOVIM="${INSTALL_NEOVIM:-true}"
INSTALL_TMUX="${INSTALL_TMUX:-true}"
INSTALL_STARSHIP="${INSTALL_STARSHIP:-true}"
CLONE_REPOS="${CLONE_REPOS:-true}"
SETUP_PYTHON_ENV="${SETUP_PYTHON_ENV:-true}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

error() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

step() {
    echo -e "${PURPLE}🔧 $1${NC}"
    log "STEP: $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Please run as a regular user."
    fi
}

# Detect package manager
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
        UPDATE_CMD="sudo apt update"
        INSTALL_CMD="sudo apt install -y"
    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"
        UPDATE_CMD="sudo dnf check-update || true"
        INSTALL_CMD="sudo dnf install -y"
    elif command -v yum >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"
        UPDATE_CMD="sudo yum check-update || true"
        INSTALL_CMD="sudo yum install -y"
    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"
        UPDATE_CMD="sudo pacman -Sy"
        INSTALL_CMD="sudo pacman -S --noconfirm"
    else
        error "Unsupported package manager"
    fi

    info "Detected package manager: $PACKAGE_MANAGER"
}

# Install system dependencies
install_system_deps() {
    step "Installing system dependencies"

    local packages=(
        curl wget git build-essential
        software-properties-common apt-transport-https
        ca-certificates gnupg lsb-release
        unzip zip tar gzip bzip2 xz-utils
        htop tree jq ncdu
        tmux neovim
        python3 python3-pip python3-venv
        nodejs npm
    )

    case $PACKAGE_MANAGER in
        apt)
            $UPDATE_CMD
            $INSTALL_CMD "${packages[@]}"
            ;;
        dnf|yum)
            $INSTALL_CMD "${packages[@]}"
            ;;
        pacman)
            $UPDATE_CMD
            $INSTALL_CMD "${packages[@]}"
            ;;
    esac

    success "System dependencies installed"
}

# Install Miniconda
install_miniconda() {
    if [[ "$INSTALL_MINICONDA" != "true" ]]; then
        info "Skipping Miniconda installation"
        return
    fi

    step "Installing Miniconda"

    if command -v conda >/dev/null 2>&1; then
        warning "Conda already installed, skipping"
        return
    fi

    local arch=$(uname -m)
    local conda_url=""

    case $arch in
        x86_64)
            conda_url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
            ;;
        aarch64)
            conda_url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh"
            ;;
        *)
            error "Unsupported architecture: $arch"
            ;;
    esac

    info "Downloading Miniconda from: $conda_url"

    local installer="/tmp/miniconda_installer.sh"
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$installer" "$conda_url"
    else
        wget -O "$installer" "$conda_url"
    fi

    chmod +x "$installer"
    bash "$installer" -b -p "$HOME/miniconda3"

    # Initialize conda
    "$HOME/miniconda3/bin/conda" init bash
    source "$HOME/.bashrc"

    success "Miniconda installed"
}

# Install Docker
install_docker() {
    if [[ "$INSTALL_DOCKER" != "true" ]]; then
        info "Skipping Docker installation"
        return
    fi

    step "Installing Docker"

    if command -v docker >/dev/null 2>&1; then
        warning "Docker already installed, skipping"
        return
    fi

    case $PACKAGE_MANAGER in
        apt)
            # Add Docker's official GPG key
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg

            # Add the repository to Apt sources
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

            $UPDATE_CMD
            $INSTALL_CMD docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        dnf|yum)
            $INSTALL_CMD docker docker-compose
            ;;
        pacman)
            $INSTALL_CMD docker docker-compose
            ;;
    esac

    # Add user to docker group
    sudo usermod -aG docker "$USER"
    sudo systemctl enable docker
    sudo systemctl start docker

    success "Docker installed"
}

# Install Node.js and npm
install_nodejs() {
    if [[ "$INSTALL_NODEJS" != "true" ]]; then
        info "Skipping Node.js installation"
        return
    fi

    step "Installing Node.js and npm"

    if command -v node >/dev/null 2>&1; then
        warning "Node.js already installed, skipping"
        return
    fi

    # Install Node.js 20.x
    case $PACKAGE_MANAGER in
        apt)
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            $INSTALL_CMD nodejs
            ;;
        dnf|yum)
            curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
            $INSTALL_CMD nodejs
            ;;
        pacman)
            $INSTALL_CMD nodejs npm
            ;;
    esac

    success "Node.js installed"
}

# Install Rust
install_rust() {
    if [[ "$INSTALL_RUST" != "true" ]]; then
        info "Skipping Rust installation"
        return
    fi

    step "Installing Rust"

    if command -v rustc >/dev/null 2>&1; then
        warning "Rust already installed, skipping"
        return
    fi

    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"

    success "Rust installed"
}

# Install Go
install_go() {
    if [[ "$INSTALL_GO" != "true" ]]; then
        info "Skipping Go installation"
        return
    fi

    step "Installing Go"

    if command -v go >/dev/null 2>&1; then
        warning "Go already installed, skipping"
        return
    fi

    local go_version="1.21.5"
    local arch=$(uname -m)
    local go_url=""

    case $arch in
        x86_64)
            go_url="https://go.dev/dl/go${go_version}.linux-amd64.tar.gz"
            ;;
        aarch64)
            go_url="https://go.dev/dl/go${go_version}.linux-arm64.tar.gz"
            ;;
        *)
            error "Unsupported architecture for Go: $arch"
            ;;
    esac

    info "Downloading Go from: $go_url"

    local go_tar="/tmp/go.tar.gz"
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$go_tar" "$go_url"
    else
        wget -O "$go_tar" "$go_url"
    fi

    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$go_tar"
    rm "$go_tar"

    # Add Go to PATH
    echo 'export PATH=$PATH:/usr/local/go/bin' >> "$HOME/.bashrc"
    export PATH=$PATH:/usr/local/go/bin

    success "Go installed"
}

# Install development tools
install_dev_tools() {
    step "Installing development tools"

    # Install tmux
    if [[ "$INSTALL_TMUX" == "true" ]]; then
        if ! command -v tmux >/dev/null 2>&1; then
            $INSTALL_CMD tmux
            success "tmux installed"
        else
            info "tmux already installed"
        fi
    fi

    # Install neovim
    if [[ "$INSTALL_NEOVIM" == "true" ]]; then
        if ! command -v nvim >/dev/null 2>&1; then
            case $PACKAGE_MANAGER in
                apt)
                    $INSTALL_CMD neovim
                    ;;
                dnf|yum)
                    $INSTALL_CMD neovim
                    ;;
                pacman)
                    $INSTALL_CMD neovim
                    ;;
            esac
            success "neovim installed"
        else
            info "neovim already installed"
        fi
    fi

    # Install starship prompt
    if [[ "$INSTALL_STARSHIP" == "true" ]]; then
        if ! command -v starship >/dev/null 2>&1; then
            curl -sS https://starship.rs/install.sh | sh -s -- -y
            echo 'eval "$(starship init bash)"' >> "$HOME/.bashrc"
            success "starship installed"
        else
            info "starship already installed"
        fi
    fi
}

# Setup Python environment
setup_python_env() {
    if [[ "$SETUP_PYTHON_ENV" != "true" ]]; then
        info "Skipping Python environment setup"
        return
    fi

    step "Setting up Python development environment"

    # Source conda if available
    if [[ -f "$HOME/miniconda3/bin/conda" ]]; then
        source "$HOME/miniconda3/bin/conda" 'shell.bash' 'hook' 2>/dev/null || true
    fi

    # Create development environment
    if command -v conda >/dev/null 2>&1; then
        conda create -n dev python=3.11 -y
        conda activate dev

        # Install common development packages
        conda install -y numpy pandas matplotlib jupyter scikit-learn tensorflow pytorch
        pip install black flake8 mypy pytest ipython

        success "Python development environment created"
    else
        warning "Conda not available, skipping Python environment setup"
    fi
}

# Clone useful repositories
clone_repositories() {
    if [[ "$CLONE_REPOS" != "true" ]]; then
        info "Skipping repository cloning"
        return
    fi

    step "Cloning useful repositories"

    local repos_dir="$HOME/repos"
    mkdir -p "$repos_dir"
    cd "$repos_dir"

    # Clone useful repositories
    local repos=(
        "https://github.com/junegunn/fzf.git"
        "https://github.com/BurntSushi/ripgrep.git"
        "https://github.com/sharkdp/fd.git"
        "https://github.com/sharkdp/bat.git"
        "https://github.com/ogham/exa.git"
    )

    for repo in "${repos[@]}"; do
        local repo_name=$(basename "$repo" .git)
        if [[ ! -d "$repo_name" ]]; then
            git clone "$repo" "$repo_name"
            success "Cloned $repo_name"
        else
            info "$repo_name already exists"
        fi
    done

    cd "$HOME"
}

# Setup dotfiles and configurations
setup_configurations() {
    step "Setting up configurations"

    # Create common directories
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/projects"
    mkdir -p "$HOME/workspace"

    # Setup git configuration
    if [[ ! -f "$HOME/.gitconfig" ]]; then
        git config --global user.name "Your Name"
        git config --global user.email "your.email@example.com"
        git config --global core.editor "nvim"
        git config --global init.defaultBranch "main"
        success "Git configured"
    fi

    # Setup bash aliases
    cat >> "$HOME/.bashrc" << 'EOF'

# Development aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Development functions
function mkcd() {
    mkdir -p "$1" && cd "$1"
}

function extract() {
    if [ -f $1 ]; then
        case $1 in
            *.tar.bz2)   tar xjf $1     ;;
            *.tar.gz)    tar xzf $1     ;;
            *.bz2)       bunzip2 $1     ;;
            *.rar)       unrar e $1     ;;
            *.gz)        gunzip $1      ;;
            *.tar)       tar xf $1      ;;
            *.tbz2)      tar xjf $1     ;;
            *.tgz)       tar xzf $1     ;;
            *.zip)       unzip $1       ;;
            *.Z)         uncompress $1  ;;
            *.7z)        7z x $1        ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}
EOF

    success "Configurations setup"
}

# Main installation function
main() {
    echo -e "${CYAN}🚀 Development Environment Setup${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo ""

    # Create log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    log "Starting development environment setup"

    check_root
    detect_package_manager
    install_system_deps
    install_miniconda
    install_docker
    install_nodejs
    install_rust
    install_go
    install_dev_tools
    setup_python_env
    clone_repositories
    setup_configurations

    echo ""
    echo -e "${GREEN}🎉 Development environment setup completed!${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Restart your terminal or run: ${CYAN}source ~/.bashrc${NC}"
    echo "2. If you installed Docker, log out and back in for group changes"
    echo "3. Configure your git settings: ${CYAN}git config --global user.name \"Your Name\"${NC}"
    echo "4. Configure your git settings: ${CYAN}git config --global user.email \"your.email@example.com\"${NC}"
    echo ""
    echo -e "${YELLOW}Installation log: $LOG_FILE${NC}"

    log "Development environment setup completed successfully"
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [options]

Options:
  --help              Show this help message
  --no-miniconda      Skip Miniconda installation
  --no-docker         Skip Docker installation
  --no-nodejs         Skip Node.js installation
  --no-rust           Skip Rust installation
  --no-go             Skip Go installation
  --no-neovim         Skip Neovim installation
  --no-tmux           Skip tmux installation
  --no-starship       Skip starship installation
  --no-repos          Skip repository cloning
  --no-python-env     Skip Python environment setup

Environment variables:
  INSTALL_MINICONDA  Install Miniconda (default: true)
  INSTALL_DOCKER     Install Docker (default: true)
  INSTALL_NODEJS     Install Node.js (default: true)
  INSTALL_RUST       Install Rust (default: true)
  INSTALL_GO         Install Go (default: true)
  INSTALL_NEOVIM     Install Neovim (default: true)
  INSTALL_TMUX       Install tmux (default: true)
  INSTALL_STARSHIP   Install starship (default: true)
  CLONE_REPOS        Clone useful repositories (default: true)
  SETUP_PYTHON_ENV   Setup Python development environment (default: true)

Examples:
  $0                          # Install everything
  $0 --no-docker --no-rust    # Skip Docker and Rust
  INSTALL_DOCKER=false $0     # Skip Docker using environment variable

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            exit 0
            ;;
        --no-miniconda)
            INSTALL_MINICONDA=false
            shift
            ;;
        --no-docker)
            INSTALL_DOCKER=false
            shift
            ;;
        --no-nodejs)
            INSTALL_NODEJS=false
            shift
            ;;
        --no-rust)
            INSTALL_RUST=false
            shift
            ;;
        --no-go)
            INSTALL_GO=false
            shift
            ;;
        --no-neovim)
            INSTALL_NEOVIM=false
            shift
            ;;
        --no-tmux)
            INSTALL_TMUX=false
            shift
            ;;
        --no-starship)
            INSTALL_STARSHIP=false
            shift
            ;;
        --no-repos)
            CLONE_REPOS=false
            shift
            ;;
        --no-python-env)
            SETUP_PYTHON_ENV=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main installation
main
