#!/bin/bash
# Configure Docker registry access

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source colors
source "$SCRIPT_DIR/../../utils/colors.sh"

# Default registry URL
DEFAULT_REGISTRY="supercog-registry.fly.dev"

# Function to update a key in .env
update_env_key() {
    local key_name=$1
    local key_value=$2
    
    # Escape special characters for sed
    local escaped_value=$(printf '%s\n' "$key_value" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    # Update or add the key
    if grep -q "^${key_name}=" "$INSTALLER_DIR/.env"; then
        # Handle both macOS and Linux sed
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^${key_name}=.*|${key_name}=${escaped_value}|" "$INSTALLER_DIR/.env"
        else
            sed -i "s|^${key_name}=.*|${key_name}=${escaped_value}|" "$INSTALLER_DIR/.env"
        fi
    else
        echo "${key_name}=${escaped_value}" >> "$INSTALLER_DIR/.env"
    fi
}

print_info "Supercog Registry Configuration"
echo ""

# Check if .env exists
if [ ! -f "$INSTALLER_DIR/.env" ]; then
    print_error ".env file not found!"
    print_info "Please run ./scripts/install/03-setup-environment-and-keys.sh first"
    exit 1
fi

# Skip if user doesn't want to configure registry
print_info "Registry configuration is optional but recommended for pulling Supercog images."
echo ""
read -p "Do you want to configure registry access now? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Skipping registry configuration"
    print_info "You can configure it later by running this script again"
    exit 0
fi

# Load current registry URL from .env if exists
if [ -f "$INSTALLER_DIR/.env" ]; then
    source "$INSTALLER_DIR/.env"
    CURRENT_REGISTRY="${REGISTRY_URL:-$DEFAULT_REGISTRY}"
else
    CURRENT_REGISTRY="$DEFAULT_REGISTRY"
fi

# Check if registry credentials already exist
if grep -q "^REGISTRY_USERNAME=..*" "$INSTALLER_DIR/.env" && grep -q "^REGISTRY_PASSWORD=..*" "$INSTALLER_DIR/.env"; then
    print_success "Registry credentials are already configured"
    echo "Current registry: $CURRENT_REGISTRY"
    echo ""
    read -p "Do you want to update registry configuration? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Registry configuration unchanged"
        exit 0
    fi
fi

# Get registry URL
read -p "Registry URL [$CURRENT_REGISTRY]: " REGISTRY_URL
REGISTRY_URL=${REGISTRY_URL:-$CURRENT_REGISTRY}

# Get credentials
read -p "Username: " REGISTRY_USERNAME
read -s -p "Password: " REGISTRY_PASSWORD
echo

# Test login
print_info "Testing registry connection..."
if echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" -u "$REGISTRY_USERNAME" --password-stdin; then
    print_success "Successfully authenticated with registry"
else
    print_error "Failed to authenticate with registry"
    exit 1
fi

# Save configuration to .env
print_info "Saving configuration..."

# Update .env file
update_env_key "REGISTRY_URL" "$REGISTRY_URL"
update_env_key "REGISTRY_USERNAME" "$REGISTRY_USERNAME"
update_env_key "REGISTRY_PASSWORD" "$REGISTRY_PASSWORD"

print_success "Registry configured successfully"
print_info "Registry credentials saved to .env file"
print_warning "Keep your .env file secure as it contains sensitive credentials"
echo ""
print_info "You can now pull images from $REGISTRY_URL"

echo ""
echo "Next step: Initialize the Supercog databases: ./scripts/install/05-init-databases.sh"
