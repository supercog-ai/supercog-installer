#!/bin/bash

# Script: update-supercog.sh
# Purpose: Pull latest Docker images from supercog.ddns.net and restart services
# Location: ~/supercog-installer/scripts/update-supercog.sh

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
REGISTRY="supercog.ddns.net"
IMAGES=("engine:latest" "dashboard:latest")
COMPOSE_DIR="$HOME/supercog-installer"
COMPOSE_FILE="docker-compose.yml"
LOG_FILE="$HOME/supercog-installer/scripts/update.log"

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Start update process
print_message "$GREEN" "Starting SuperCog update process..."
log_message "Starting update process"

# Create log file if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# Check if docker-compose file exists
if [ ! -f "$COMPOSE_DIR/$COMPOSE_FILE" ]; then
    print_message "$RED" "Error: docker-compose.yml not found in $COMPOSE_DIR"
    log_message "Error: docker-compose.yml not found"
    exit 1
fi

# Pull images
print_message "$YELLOW" "Pulling latest images from $REGISTRY..."
for image in "${IMAGES[@]}"; do
    full_image="$REGISTRY/$image"
    print_message "$YELLOW" "  Pulling $full_image..."
    
    if docker pull "$full_image"; then
        print_message "$GREEN" "  ✓ Successfully pulled $image"
        log_message "Successfully pulled $full_image"
    else
        print_message "$RED" "  ✗ Failed to pull $image"
        log_message "Failed to pull $full_image"
        exit 1
    fi
done

# Navigate to compose directory
cd "$COMPOSE_DIR"

# Stop current containers
print_message "$YELLOW" "Stopping current containers..."
if docker-compose down; then
    print_message "$GREEN" "  ✓ Containers stopped successfully"
    log_message "Containers stopped successfully"
else
    print_message "$RED" "  ✗ Failed to stop containers"
    log_message "Failed to stop containers"
    exit 1
fi

# Start containers with new images
print_message "$YELLOW" "Starting containers with updated images..."
if docker-compose up -d; then
    print_message "$GREEN" "  ✓ Containers started successfully"
    log_message "Containers started successfully"
else
    print_message "$RED" "  ✗ Failed to start containers"
    log_message "Failed to start containers"
    exit 1
fi

# Wait for containers to be healthy (optional)
print_message "$YELLOW" "Waiting for services to be ready..."
sleep 5

# Check container status
print_message "$YELLOW" "Checking container status..."
docker-compose ps

# Clean up old images (optional)
print_message "$YELLOW" "Cleaning up old images..."
docker image prune -f

# Success message
print_message "$GREEN" "==============================================="
print_message "$GREEN" "SuperCog update completed successfully!"
print_message "$GREEN" "==============================================="
log_message "Update completed successfully"

# Show last few log entries
print_message "$YELLOW" "\nRecent update history:"
tail -5 "$LOG_FILE"
