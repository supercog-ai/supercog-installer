#!/bin/bash
# Setup env file and configure API keys

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source colors
source "$SCRIPT_DIR/../../utils/colors.sh"

# Function to validate API key format
validate_api_key() {
    local key=$1
    local type=$2
    
    case $type in
        openai)
            # OpenAI keys typically start with sk-
            if [[ $key =~ ^sk-[a-zA-Z0-9]{48}$ ]] || [[ $key =~ ^sk-proj-[a-zA-Z0-9]{48}$ ]]; then
                return 0
            else
                print_warning "Note: OpenAI API keys typically start with 'sk-' or 'sk-proj-'"
                return 0  # Still allow it
            fi
            ;;
        claude)
            # Claude keys have various formats
            if [[ ${#key} -gt 20 ]]; then
                return 0
            else
                print_warning "API key seems too short"
                return 1
            fi
            ;;
    esac
}

# Function to update a key in .env
update_env_key() {
    local key_name=$1
    local key_value=$2
    
    # Escape special characters for sed
    local escaped_value=$(printf '%s\n' "$key_value" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    # Update or add the key
    if grep -q "^${key_name}=" "$INSTALLER_DIR/.env"; then
        sed -i "s|^${key_name}=.*|${key_name}=${escaped_value}|" "$INSTALLER_DIR/.env"
    else
        echo "${key_name}=${escaped_value}" >> "$INSTALLER_DIR/.env"
    fi
}

# Function to setup environment file
setup_environment_file() {
    print_info "Setting up environment configuration..."
    
    # Check if .env.example exists
    if [ ! -f "$INSTALLER_DIR/.env.example" ]; then
        print_error ".env.example file not found!"
        print_info "Please ensure you have the complete Supercog installer package"
        return 1
    fi
    
    # Check if .env already exists
    if [ -f "$INSTALLER_DIR/.env" ]; then
        print_warning ".env file already exists"
        
        # Show current configuration summary (without sensitive data)
        echo ""
        echo "Current configuration includes:"
        grep -E "^(ENV|DEBUG|ENGINE_URL|DATABASE_URL|REGISTRY_URL)=" "$INSTALLER_DIR/.env" | \
            sed 's/=.*$/=<configured>/' | sed 's/^/  /'
        
        # Check if API keys are already configured
        local has_keys=false
        if grep -q "^OPENAI_API_KEY=..*" "$INSTALLER_DIR/.env" || grep -q "^CLAUDE_INTERNAL_API_KEY=..*" "$INSTALLER_DIR/.env"; then
            has_keys=true
            echo ""
            grep -E "^(OPENAI_API_KEY|CLAUDE_INTERNAL_API_KEY)=" "$INSTALLER_DIR/.env" | \
                sed 's/=.*$/=<configured>/' | sed 's/^/  /'
        fi
        echo ""
        
        read -p "Do you want to recreate the .env file? (y/N) " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Create backup
            backup_dir="$INSTALLER_DIR/backups"
            mkdir -p "$backup_dir"
            backup_file="$backup_dir/.env.backup.$(date +%Y%m%d_%H%M%S)"
            
            cp "$INSTALLER_DIR/.env" "$backup_file"
            print_success "Existing .env backed up to: $backup_file"
            
            # Copy example to .env
            cp "$INSTALLER_DIR/.env.example" "$INSTALLER_DIR/.env"
            print_success ".env file created from template"
        else
            # Keep existing file but still offer to update API keys
            print_info "Keeping existing .env file"
            return 0
        fi
    else
        # Create new .env from example
        cp "$INSTALLER_DIR/.env.example" "$INSTALLER_DIR/.env"
        print_success ".env file created from template"
    fi
    
    # Set appropriate permissions
    chmod 600 "$INSTALLER_DIR/.env"
    print_info "Set restricted permissions on .env file"
    
    return 0
}

# Function to configure API keys
configure_api_keys() {
    echo ""
    print_info "Configuring AI API Keys"
    echo ""
    print_warning "Supercog requires at least one AI API key to function."
    echo ""
    echo "Supported AI providers:"
    echo "  • OpenAI (GPT Models)"
    echo "  • Anthropic Claude"
    echo ""
    
    # Check existing keys
    local has_openai=false
    local has_claude=false
    
    if grep -q "^OPENAI_API_KEY=..*" "$INSTALLER_DIR/.env"; then
        has_openai=true
        print_success "OpenAI API key is already configured"
    fi
    
    if grep -q "^CLAUDE_INTERNAL_API_KEY=..*" "$INSTALLER_DIR/.env"; then
        has_claude=true
        print_success "Claude API key is already configured"
    fi
    
    # If both keys exist, ask if user wants to update
    if [ "$has_openai" = true ] && [ "$has_claude" = true ]; then
        echo ""
        read -p "Do you want to update any API keys? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "API keys unchanged"
            return 0
        fi
    fi
    
    # Configure keys
    echo ""
    echo "Which AI API would you like to configure?"
    echo "1) OpenAI (GPT models)"
    echo "2) Claude (Anthropic)"
    echo "3) Both"
    echo "4) Skip for now"
    
    read -p "Enter your choice (1-4): " choice
    
    case $choice in
        1)            
            read -s -p "Enter your OpenAI API key: " openai_key
            if [ -n "$openai_key" ]; then
                if validate_api_key "$openai_key" "openai"; then
                    update_env_key "OPENAI_API_KEY" "$openai_key"
                    print_success "OpenAI API key configured"
                fi
            else
                print_warning "No OpenAI key provided"
            fi
            ;;
            
        2)
            read -s -p "Enter your Claude API key: " claude_key
            if [ -n "$claude_key" ]; then
                if validate_api_key "$claude_key" "claude"; then
                    update_env_key "CLAUDE_INTERNAL_API_KEY" "$claude_key"
                    print_success "Claude API key configured"
                fi
            else
                print_warning "No Claude key provided"
            fi
            ;;
            
        3) 
            read -s -p "Enter your OpenAI API key (or press Enter to skip): " openai_key
            if [ -n "$openai_key" ]; then
                if validate_api_key "$openai_key" "openai"; then
                    update_env_key "OPENAI_API_KEY" "$openai_key"
                    print_success "OpenAI API key configured"
                fi
            else
                print_info "Skipping OpenAI key"
            fi

            read -s -p "Enter your Claude API key (or press Enter to skip): " claude_key
            if [ -n "$claude_key" ]; then
                if validate_api_key "$claude_key" "claude"; then
                    update_env_key "CLAUDE_INTERNAL_API_KEY" "$claude_key"
                    print_success "Claude API key configured"
                fi
            else
                print_info "Skipping Claude key"
            fi
            ;;
            
        4)
            print_warning "Skipping API key configuration"
            ;;
            
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
    
    return 0
}

# Main function
main() {
    print_info "Setting up Supercog environment and API keys"
    echo ""
    
    # Setup environment file
    setup_environment_file
    
    # Configure API keys
    configure_api_keys
    
    # Final verification
    echo ""
    print_info "Verifying configuration..."
    
    # Check .env file
    if [ -f "$INSTALLER_DIR/.env" ]; then
        print_success "✓ Environment file configured"
    else
        print_error "✗ Environment file missing"
        exit 1
    fi
    
    # Check API keys
    local final_has_key=false
    if grep -q "^OPENAI_API_KEY=..*" "$INSTALLER_DIR/.env"; then
        print_success "✓ OpenAI API key configured"
        final_has_key=true
    fi
    
    if grep -q "^CLAUDE_INTERNAL_API_KEY=..*" "$INSTALLER_DIR/.env"; then
        print_success "✓ Claude API key configured"
        final_has_key=true
    fi
    
    if [ "$final_has_key" = false ]; then
        echo ""
        print_error "WARNING: No API keys configured!"
        print_error "Supercog requires at least one API key to function."
        echo ""
        echo "You can add API keys later by editing $INSTALLER_DIR/.env"
        echo "Add either:"
        echo "  OPENAI_API_KEY=your-key-here"
        echo "  CLAUDE_INTERNAL_API_KEY=your-key-here"
        echo ""
        read -p "Do you want to continue without API keys? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Generate security keys
    print_info "Generating security keys..."
    if [ -x "$SCRIPT_DIR/../../utils/generate-keys.sh" ]; then
        "$SCRIPT_DIR/../../utils/generate-keys.sh"
    else
        print_error "generate-keys.sh not found or not executable"
        print_info "Please run ./utils/generate-keys.sh manually"
        exit 1
    fi
    
    print_success "Environment setup complete!"

    echo ""
    echo "Next step: Configure access to the registry using ./scripts/install/04-configure-registry.sh"
    
    exit 0
}

# Run main function
main "$@"
