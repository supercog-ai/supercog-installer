#!/bin/bash
# Configure Docker registry access with htpasswd authentication

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"

# Source colors
source "$SCRIPT_DIR/../utils/colors.sh"

# Default registry URL
DEFAULT_REGISTRY="supercog-registry.fly.dev"

print_info "Supercog Registry Configuration"
echo ""

# Get registry URL
read -p "Registry URL [$DEFAULT_REGISTRY]: " REGISTRY_URL
REGISTRY_URL=${REGISTRY_URL:-$DEFAULT_REGISTRY}

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

# Save configuration
print_info "Saving configuration..."

# Update .env file
if [ -f "$INSTALLER_DIR/.env" ]; then
    cp "$INSTALLER_DIR/.env" "$INSTALLER_DIR/.env.tmp"
    
    # Update or add registry URL
    if grep -q "^REGISTRY_URL=" "$INSTALLER_DIR/.env.tmp"; then
        sed -i "s|^REGISTRY_URL=.*|REGISTRY_URL=$REGISTRY_URL|" "$INSTALLER_DIR/.env.tmp"
    else
        echo "REGISTRY_URL=$REGISTRY_URL" >> "$INSTALLER_DIR/.env.tmp"
    fi
    
    mv "$INSTALLER_DIR/.env.tmp" "$INSTALLER_DIR/.env"
fi

# Create registry config file for update scripts
cat > "$INSTALLER_DIR/.supercog-registry" <<EOF
REGISTRY_URL=$REGISTRY_URL
REGISTRY_USERNAME=$REGISTRY_USERNAME
EOF
chmod 600 "$INSTALLER_DIR/.supercog-registry"

print_success "Registry configured successfully"
print_info "You can now pull images from $REGISTRY_URL"
