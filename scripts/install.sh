#!/bin/bash
# Main installation script for Supercog

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"

# Source colors
source "$SCRIPT_DIR/../utils/colors.sh"

# Version
VERSION=$(cat "$INSTALLER_DIR/VERSION")

print_header() {
    echo ""
    echo "╔════════════════════════════════════╗"
    echo "║     Supercog Installer v$VERSION     ║"
    echo "╚════════════════════════════════════╝"
    echo ""
}

# Check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_error "Please do not run this script as root"
        print_info "The script will use sudo when necessary"
        exit 1
    fi
}

# Install Docker
install_docker() {
    if command -v docker &> /dev/null; then
        print_success "Docker is already installed"
        return 0
    fi
    
    print_info "Installing Docker..."
    "$SCRIPT_DIR/install-docker.sh" || {
        print_error "Docker installation failed"
        exit 1
    }
}

# Create directory structure
create_directories() {
    print_info "Creating directory structure..."
    
    local dirs=(
        "logs"
        "backups"
        "keys"
        "local_data/sc_localfiles"
        "local_data/tools"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$INSTALLER_DIR/$dir"
    done
    
    print_success "Directories created"
}

# Setup environment file
setup_environment() {
    print_info "Setting up environment..."
    
    if [ -f "$INSTALLER_DIR/.env" ]; then
        print_warning ".env file already exists"
        read -p "Do you want to recreate it? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
        backup_file="$INSTALLER_DIR/backups/.env.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$INSTALLER_DIR/.env" "$backup_file"
        print_info "Existing .env backed up to $backup_file"
    fi
    
    cp "$INSTALLER_DIR/.env.example" "$INSTALLER_DIR/.env"
    
    # Generate security keys
    print_info "Generating security keys..."
    "$SCRIPT_DIR/generate-keys.sh"
    
    print_success "Environment configured"
    print_warning "Please edit .env file to customize your configuration"
}

# Setup API keys
setup_api_keys() {
    print_info "Configuring AI API Keys..."
    echo ""
    print_warning "Supercog requires at least one AI API key to function."
    echo ""
    
    # Check if any API key is already set
    local has_key=false
    if grep -q "^OPENAI_API_KEY=..*" "$INSTALLER_DIR/.env"; then
        print_success "OpenAI API key is already configured"
        has_key=true
    fi
    if grep -q "^CLAUDE_INTERNAL_API_KEY=..*" "$INSTALLER_DIR/.env"; then
        print_success "Claude API key is already configured"
        has_key=true
    fi
    
    if [ "$has_key" = true ]; then
        read -p "Do you want to add/update API keys? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    # Ask which API to configure
    echo "Which AI API would you like to configure?"
    echo "1) OpenAI (GPT models)"
    echo "2) Claude (Anthropic)"
    echo "3) Both"
    echo "4) Skip for now"
    
    read -p "Enter your choice (1-4): " choice
    
    case $choice in
        1)
            read -p "Enter your OpenAI API key: " openai_key
            if [ -n "$openai_key" ]; then
                sed -i "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=$openai_key|" "$INSTALLER_DIR/.env"
                print_success "OpenAI API key configured"
            fi
            ;;
        2)
            read -p "Enter your Claude API key: " claude_key
            if [ -n "$claude_key" ]; then
                sed -i "s|^CLAUDE_INTERNAL_API_KEY=.*|CLAUDE_INTERNAL_API_KEY=$claude_key|" "$INSTALLER_DIR/.env"
                print_success "Claude API key configured"
            fi
            ;;
        3)
            read -p "Enter your OpenAI API key: " openai_key
            if [ -n "$openai_key" ]; then
                sed -i "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=$openai_key|" "$INSTALLER_DIR/.env"
                print_success "OpenAI API key configured"
            fi
            
            read -p "Enter your Claude API key: " claude_key
            if [ -n "$claude_key" ]; then
                sed -i "s|^CLAUDE_INTERNAL_API_KEY=.*|CLAUDE_INTERNAL_API_KEY=$claude_key|" "$INSTALLER_DIR/.env"
                print_success "Claude API key configured"
            fi
            ;;
        4)
            print_warning "No API keys configured. Supercog will not function without at least one API key."
            print_info "You can add API keys later by editing the .env file"
            ;;
        *)
            print_error "Invalid choice"
            setup_api_keys  # Recurse
            ;;
    esac
    
    # Verify at least one key is set
    local final_check=false
    if grep -q "^OPENAI_API_KEY=..*" "$INSTALLER_DIR/.env" || grep -q "^CLAUDE_INTERNAL_API_KEY=..*" "$INSTALLER_DIR/.env"; then
        final_check=true
    fi
    
    if [ "$final_check" = false ]; then
        print_error "WARNING: No API keys configured!"
        print_error "Supercog requires at least one API key to function."
        print_info "Please edit $INSTALLER_DIR/.env and add either:"
        print_info "  - OPENAI_API_KEY=your-key-here"
        print_info "  - CLAUDE_INTERNAL_API_KEY=your-key-here"
        echo ""
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Initialize databases
init_databases() {
    print_info "Initializing databases..."
    
    cd "$INSTALLER_DIR"
    
    # Start only postgres first
    docker compose up -d postgres
    
    # Wait for postgres to be ready
    print_info "Waiting for PostgreSQL to start..."
    local max_attempts=30
    local attempt=0
    
    while ! docker compose exec -T postgres pg_isready -U pguser &>/dev/null; do
        attempt=$((attempt + 1))
        if [ $attempt -eq $max_attempts ]; then
            print_error "PostgreSQL failed to start"
            docker compose logs postgres
            exit 1
        fi
        sleep 2
    done
    
    print_success "PostgreSQL is ready"
    
    # Create databases
    print_info "Creating databases..."
    docker compose exec -T postgres psql -U pguser -d postgres < "$SCRIPT_DIR/postgres-init/01-monster_dashboard.sql"
    docker compose exec -T postgres psql -U pguser -d postgres < "$SCRIPT_DIR/postgres-init/02-monster_engine.sql"
    docker compose exec -T postgres psql -U pguser -d postgres < "$SCRIPT_DIR/postgres-init/03-monster_credentials.sql"
    docker compose exec -T postgres psql -U pguser -d postgres < "$SCRIPT_DIR/postgres-init/04-monster_rag.sql"
    
    print_success "Databases initialized"
}

# Configure registry access
configure_registry() {
    print_info "Configuring registry access..."
    
    read -p "Do you want to configure registry access now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$SCRIPT_DIR/configure-registry.sh"
    else
        print_warning "You can configure registry later with: ./scripts/configure-registry.sh"
    fi
}

# Start services
start_services() {
    print_info "Starting all services..."
    
    cd "$INSTALLER_DIR"
    docker compose up -d
    
    # Wait for services to be healthy
    print_info "Waiting for services to be ready..."
    
    local services=("postgres" "redis" "minio" "triggersvc" "engine" "dashboard")
    for service in "${services[@]}"; do
        print_info "Checking $service..."
        local max_attempts=60
        local attempt=0
        
        while ! docker compose ps | grep -E "${service}.*healthy" &>/dev/null; do
            attempt=$((attempt + 1))
            if [ $attempt -eq $max_attempts ]; then
                print_warning "$service is taking longer than expected"
                break
            fi
            sleep 2
        done
    done
    
    print_success "All services started"
}

# Create completion marker
mark_installation_complete() {
    cat > "$INSTALLER_DIR/.installed" <<EOF
INSTALL_DATE=$(date -I)
VERSION=$VERSION
EOF
}

# Main installation flow
main() {
    print_header
    
    # Pre-installation checks
    check_root
    
    # Check if already installed
    if [ -f "$INSTALLER_DIR/.installed" ]; then
        print_warning "Supercog appears to be already installed"
        print_info "Installation info:"
        cat "$INSTALLER_DIR/.installed"
        echo
        read -p "Do you want to reinstall? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Run installation steps
    install_docker
    create_directories
    setup_environment
    setup_api_keys
    configure_registry
    init_databases
    start_services
    mark_installation_complete
    
    # Show completion message
    print_success "Installation completed successfully!"
    echo ""
    echo "Supercog is now running!"
    echo ""
    echo "Access points:"
    echo "  • Dashboard: http://localhost:3000"
    echo "  • Engine API: http://localhost:8080"
    echo "  • MinIO Console: http://localhost:9001"
    echo ""
    echo "Useful commands:"
    echo "  • Check status: docker compose ps"
    echo "  • View logs: docker compose logs -f [service]"
    echo "  • Stop services: docker compose down"
    echo "  • Update Supercog: ./scripts/update-supercog.sh"
    echo "  • Health check: ./scripts/health-check.sh"
    echo ""
    echo "Documentation: $INSTALLER_DIR/docs/"
    echo ""
}

# Run main function
main "$@"
