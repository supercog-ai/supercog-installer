#!/bin/bash
# Create required directory structure for Supercog

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source colors
source "$SCRIPT_DIR/../../utils/colors.sh"

print_info "Creating Supercog directory structure..."

# Define directories to create
declare -a directories=(
    "logs"
    "backups"
    "keys"
    "local_data"
    "local_data/sc_localfiles"
    "local_data/tools"
)

# Create each directory
for dir in "${directories[@]}"; do
    full_path="$INSTALLER_DIR/$dir"
    
    if [ -d "$full_path" ]; then
        print_info "Directory already exists: $dir"
    else
        mkdir -p "$full_path"
        print_success "Created directory: $dir"
    fi
    
    # Set appropriate permissions
    case "$dir" in
        keys)
            chmod 700 "$full_path"
            print_info "Set restricted permissions on: $dir"
            ;;
        logs|backups)
            chmod 755 "$full_path"
            ;;
    esac
done

# Verify directory structure
print_info "Verifying directory structure..."
all_exist=true

for dir in "${directories[@]}"; do
    full_path="$INSTALLER_DIR/$dir"
    if [ ! -d "$full_path" ]; then
        print_error "Failed to create: $dir"
        all_exist=false
    fi
done

if [ "$all_exist" = true ]; then
    print_success "All directories created successfully!"
    
    # Show directory tree
    echo ""
    echo "Directory structure:"
    echo "$INSTALLER_DIR/"
    echo "├── logs/              # Application logs"
    echo "├── backups/           # Backup files"
    echo "├── keys/              # Security keys"
    echo "└── local_data/        # Application data"
    echo "    ├── sc_localfiles/ # Local file storage"
    echo "    └── tools/         # Custom tools"
    echo ""
    
    exit 0
else
    print_error "Some directories could not be created"
    exit 1
fi

echo ""
echo "Next step: Configure your .env file with ./scripts/install/03-setup-env-file.sh"
