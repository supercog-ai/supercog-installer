#!/bin/bash

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source colors helper
source "$SCRIPT_DIR/../utils/colors.sh"

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        PRETTY_NAME=$PRETTY_NAME
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
        VER=$(rpm -q --qf "%{VERSION}" centos-release)
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    print_info "Detected OS: $PRETTY_NAME"
}

# Install Docker on Ubuntu/Debian
install_docker_debian() {
    print_info "Installing Docker for $OS..."
    
    # Update package index
    print_info "Updating package index..."
    sudo apt-get update
    
    # Install prerequisites
    print_info "Installing prerequisites..."
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common
    
    # Add Docker's official GPG key
    print_info "Adding Docker GPG key..."
    sudo mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    print_info "Setting up Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index again
    print_info "Updating package index with Docker repository..."
    sudo apt-get update
    
    # Install Docker Engine
    print_info "Installing Docker Engine..."
    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
}

# Install Docker on CentOS/RHEL/Fedora
install_docker_redhat() {
    print_info "Installing Docker for $OS..."
    
    # Remove old versions
    print_info "Removing old Docker versions if present..."
    sudo yum remove -y docker \
        docker-client \
        docker-client-latest \
        docker-common \
        docker-latest \
        docker-latest-logrotate \
        docker-logrotate \
        docker-engine 2>/dev/null || true
    
    # Install prerequisites
    print_info "Installing prerequisites..."
    sudo yum install -y yum-utils device-mapper-persistent-data lvm2
    
    # Add Docker repository
    print_info "Adding Docker repository..."
    if [ "$OS" = "fedora" ]; then
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    else
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi
    
    # Install Docker Engine
    print_info "Installing Docker Engine..."
    if [ "$OS" = "fedora" ]; then
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
}

# Install Docker on Amazon Linux
install_docker_amazon() {
    print_info "Installing Docker for Amazon Linux..."
    
    # Update packages
    sudo yum update -y
    
    # Install Docker
    sudo yum install -y docker
    
    # Install Docker Compose
    print_info "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
}

# Install Docker on Arch Linux
install_docker_arch() {
    print_info "Installing Docker for Arch Linux..."
    
    # Update system
    sudo pacman -Syu --noconfirm
    
    # Install Docker
    sudo pacman -S --noconfirm docker docker-compose
}

# Install Docker on openSUSE
install_docker_suse() {
    print_info "Installing Docker for openSUSE..."
    
    # Install Docker
    sudo zypper install -y docker docker-compose
}

# Configure Docker post-installation
configure_docker() {
    print_info "Configuring Docker post-installation..."
    
    # Create docker group if it doesn't exist
    if ! getent group docker > /dev/null 2>&1; then
        print_info "Creating docker group..."
        sudo groupadd docker
    fi
    
    # Add current user to docker group
    print_info "Adding user '$USER' to docker group..."
    sudo usermod -aG docker $USER
    
    # Configure Docker daemon with better defaults
    print_info "Configuring Docker daemon..."
    sudo mkdir -p /etc/docker
    
    # Create daemon.json with log rotation and other optimizations
    if [ ! -f /etc/docker/daemon.json ]; then
        cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "compress": "true"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "userland-proxy": false
}
EOF
    else
        print_warning "Docker daemon.json already exists, skipping configuration"
    fi
    
    # Start Docker service
    print_info "Starting Docker service..."
    sudo systemctl start docker
    
    # Enable Docker and containerd to start on boot
    print_info "Enabling Docker to start on boot..."
    sudo systemctl enable docker.service
    sudo systemctl enable containerd.service
    
    # Restart Docker to apply configuration
    sudo systemctl restart docker
    
    # Fix permissions for .docker directory if it exists
    if [ -d "$HOME/.docker" ]; then
        print_info "Fixing .docker directory permissions..."
        sudo chown "$USER":"$USER" "$HOME/.docker" -R
        sudo chmod g+rwx "$HOME/.docker" -R
    fi
    
    # Activate docker group for current session
    print_info "Activating docker group for current session..."
    if command -v newgrp &> /dev/null; then
        # Create a flag file to indicate we've already done newgrp
        if [ ! -f "/tmp/.docker_newgrp_done_$" ]; then
            touch "/tmp/.docker_newgrp_done_$"
            print_warning "Activating docker group permissions..."
            # Note: This will create a new shell
            exec newgrp docker
        fi
    fi
}

# Install Docker Compose standalone (if needed)
install_docker_compose_standalone() {
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_info "Installing Docker Compose standalone..."
        
        # Get latest version
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        
        if [ -z "$COMPOSE_VERSION" ]; then
            COMPOSE_VERSION="v2.23.0"  # Fallback version
        fi
        
        # Download and install
        sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        
        # Create symlink for docker compose command
        sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi
}

# Verify installation
verify_installation() {
    print_info "Verifying Docker installation..."
    
    # Check Docker version
    if docker --version &> /dev/null; then
        print_success "Docker installed: $(docker --version)"
    else
        print_error "Docker installation failed"
        return 1
    fi
    
    # Check Docker Compose
    if docker compose version &> /dev/null; then
        print_success "Docker Compose installed: $(docker compose version)"
    elif docker-compose --version &> /dev/null; then
        print_success "Docker Compose installed: $(docker-compose --version)"
    else
        print_warning "Docker Compose not found, attempting to install..."
        install_docker_compose_standalone
    fi
    
    # Test Docker without sudo (if group is active)
    print_info "Testing Docker installation..."
    if groups | grep -q docker; then
        # Group is active, test without sudo
        if docker run --rm hello-world &> /dev/null; then
            print_success "Docker is working correctly (no sudo required)"
        else
            print_warning "Docker test failed, you may need to log out and back in"
            print_info "Testing with sudo..."
            if sudo docker run --rm hello-world &> /dev/null; then
                print_success "Docker works with sudo"
                print_warning "Please log out and back in to use Docker without sudo"
            else
                print_error "Docker test failed even with sudo"
                return 1
            fi
        fi
    else
        # Group not active yet, test with sudo
        if sudo docker run --rm hello-world &> /dev/null; then
            print_success "Docker is working (sudo required until you log out/in)"
            print_warning "You need to log out and back in to use Docker without sudo"
        else
            print_error "Docker test failed"
            return 1
        fi
    fi
    
    # Check if Docker is enabled to start on boot
    if systemctl is-enabled docker.service &> /dev/null; then
        print_success "Docker is enabled to start on boot"
    else
        print_warning "Docker is not enabled to start on boot"
    fi
}

# Main installation function
main() {
    print_info "Docker Installation Script"
    echo "=========================="
    echo ""
    
    # Check if already installed
    if command -v docker &> /dev/null; then
        print_warning "Docker is already installed: $(docker --version)"
        read -p "Do you want to reinstall? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Detect OS
    detect_os
    
    # Install based on OS
    case $OS in
        ubuntu|debian|raspbian)
            install_docker_debian
            ;;
        centos|rhel|rocky|almalinux)
            install_docker_redhat
            ;;
        fedora)
            install_docker_redhat
            ;;
        amzn)
            install_docker_amazon
            ;;
        arch|manjaro)
            install_docker_arch
            ;;
        opensuse|sles)
            install_docker_suse
            ;;
        *)
            print_error "Unsupported OS: $OS"
            print_info "Please install Docker manually following the official documentation:"
            print_info "https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
    
    # Configure Docker
    configure_docker
    
    # Install Docker Compose if needed
    install_docker_compose_standalone
    
    # Verify installation
    verify_installation
    
    # Success message
    print_success "Docker installation completed!"
    echo ""
    
    # Check if user needs to log out
    if ! groups | grep -q docker; then
        print_warning "IMPORTANT: You need to log out and back in for group changes to take effect."
        print_info "After logging out and back in, you can run Docker commands without sudo."
        echo ""
        print_info "Alternative options:"
        print_info "  1. Log out and log back in (recommended)"
        print_info "  2. Run: newgrp docker (temporary fix for current session)"
        print_info "  3. Restart your system"
    else
        print_success "You can now run Docker commands without sudo!"
    fi
    
    echo ""
    print_info "Docker is configured to:"
    print_info "  ✓ Start automatically on boot"
    print_info "  ✓ Run without sudo (after re-login)"
    print_info "  ✓ Use log rotation (max 3 files of 10MB each)"
    print_info "  ✓ Use overlay2 storage driver"
    echo ""
    print_info "To test Docker after re-login, run:"
    print_info "  docker run hello-world"
    echo ""
}

# Run main function
main "$@"
