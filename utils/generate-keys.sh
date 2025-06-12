#!/bin/bash
# Generate security keys for Supercog

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/colors.sh"

# Function to generate ECDSA keys
generate_ecdsa_keys() {
    print_info "Generating ECDSA key pair..."
    
    # Create keys directory
    mkdir -p "$INSTALLER_DIR/keys"
    
    # Generate keys
    openssl ecparam -name prime256v1 -genkey -noout -out "$INSTALLER_DIR/keys/dash_ecdsa_private_key.pem"
    openssl ec -in "$INSTALLER_DIR/keys/dash_ecdsa_private_key.pem" -pubout -out "$INSTALLER_DIR/keys/dash_ecdsa_public_key.pem"
    
    # Convert to base64
    PRIVATE_KEY=$(base64 < "$INSTALLER_DIR/keys/dash_ecdsa_private_key.pem" | tr -d '\n')
    PUBLIC_KEY=$(base64 < "$INSTALLER_DIR/keys/dash_ecdsa_public_key.pem" | tr -d '\n')
    
    # Secure the keys
    chmod 700 "$INSTALLER_DIR/keys"
    chmod 600 "$INSTALLER_DIR/keys"/*.pem
    
    print_success "ECDSA keys generated"
}

# Function to generate credentials master key
generate_master_key() {
    print_info "Generating credentials master key..."
    
    # Generate 32 bytes of random data and base64 encode it
    MASTER_KEY=$(openssl rand -base64 32)
    
    print_success "Master key generated"
}

# Function to update .env file
update_env_file() {
    if [ ! -f "$INSTALLER_DIR/.env" ]; then
        print_error "No .env file found. Please create one from .env.example first."
        return 1
    fi
    
    print_info "Updating .env file..."
    
    # Create backup
    cp "$INSTALLER_DIR/.env" "$INSTALLER_DIR/.env.bak"
    
    # Update DASH keys if empty or missing
    if ! grep -q "^DASH_PRIVATE_KEY=..*" "$INSTALLER_DIR/.env"; then
        if grep -q "^DASH_PRIVATE_KEY=" "$INSTALLER_DIR/.env"; then
            sed -i "s|^DASH_PRIVATE_KEY=.*|DASH_PRIVATE_KEY=$PRIVATE_KEY|" "$INSTALLER_DIR/.env"
        else
            echo "DASH_PRIVATE_KEY=$PRIVATE_KEY" >> "$INSTALLER_DIR/.env"
        fi
        print_success "DASH_PRIVATE_KEY updated"
    else
        print_info "DASH_PRIVATE_KEY already set, skipping"
    fi
    
    if ! grep -q "^DASH_PUBLIC_KEY=..*" "$INSTALLER_DIR/.env"; then
        if grep -q "^DASH_PUBLIC_KEY=" "$INSTALLER_DIR/.env"; then
            sed -i "s|^DASH_PUBLIC_KEY=.*|DASH_PUBLIC_KEY=$PUBLIC_KEY|" "$INSTALLER_DIR/.env"
        else
            echo "DASH_PUBLIC_KEY=$PUBLIC_KEY" >> "$INSTALLER_DIR/.env"
        fi
        print_success "DASH_PUBLIC_KEY updated"
    else
        print_info "DASH_PUBLIC_KEY already set, skipping"
    fi
    
    # Update CREDENTIALS_MASTER_KEY if empty or missing
    if ! grep -q "^CREDENTIALS_MASTER_KEY=..*" "$INSTALLER_DIR/.env"; then
        if grep -q "^CREDENTIALS_MASTER_KEY=" "$INSTALLER_DIR/.env"; then
            sed -i "s|^CREDENTIALS_MASTER_KEY=.*|CREDENTIALS_MASTER_KEY=$MASTER_KEY|" "$INSTALLER_DIR/.env"
        else
            echo "CREDENTIALS_MASTER_KEY=$MASTER_KEY" >> "$INSTALLER_DIR/.env"
        fi
        print_success "CREDENTIALS_MASTER_KEY updated"
    else
        print_info "CREDENTIALS_MASTER_KEY already set, skipping"
    fi
    
    # Remove backup if successful
    rm -f "$INSTALLER_DIR/.env.bak"
}

# Main function
main() {
    print_info "Supercog Security Key Generator"
    echo ""
    
    # Check for .env file
    if [ ! -f "$INSTALLER_DIR/.env" ]; then
        print_error "No .env file found!"
        print_info "Please copy .env.example to .env first:"
        print_info "  cp $INSTALLER_DIR/.env.example $INSTALLER_DIR/.env"
        exit 1
    fi
    
    # Generate keys
    generate_ecdsa_keys
    generate_master_key
    
    # Update .env file
    update_env_file
    
    print_success "All security keys generated successfully"
}

# Parse arguments
case "${1:-generate}" in
    generate)
        main
        ;;
    
    show)
        # Show current keys (for debugging)
        if [ -f "$INSTALLER_DIR/.env" ]; then
            echo "Current keys in .env:"
            grep -E "^(DASH_PRIVATE_KEY|DASH_PUBLIC_KEY|CREDENTIALS_MASTER_KEY)=" "$INSTALLER_DIR/.env" | \
                sed 's/=.*$/=<set>/'
        else
            print_error "No .env file found"
        fi
        ;;
    
    regenerate)
        # Force regeneration of all keys
        print_warning "This will regenerate all security keys!"
        print_warning "Existing encrypted data may become inaccessible."
        read -p "Are you sure? (yes/no) " -r
        if [[ $REPLY == "yes" ]]; then
            # Clear existing keys from .env
            if [ -f "$INSTALLER_DIR/.env" ]; then
                sed -i 's/^DASH_PRIVATE_KEY=.*/DASH_PRIVATE_KEY=/' "$INSTALLER_DIR/.env"
                sed -i 's/^DASH_PUBLIC_KEY=.*/DASH_PUBLIC_KEY=/' "$INSTALLER_DIR/.env"
                sed -i 's/^CREDENTIALS_MASTER_KEY=.*/CREDENTIALS_MASTER_KEY=/' "$INSTALLER_DIR/.env"
            fi
            main
        else
            print_info "Regeneration cancelled"
        fi
        ;;
    
    *)
        echo "Usage: $0 [generate|show|regenerate]"
        echo ""
        echo "Commands:"
        echo "  generate   - Generate missing keys (default)"
        echo "  show       - Show which keys are set"
        echo "  regenerate - Force regenerate all keys (WARNING: data loss risk)"
        ;;
esac
