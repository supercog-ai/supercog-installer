#!/bin/bash
# Script: update-supercog-smart.sh
# Purpose: Check for updates and only pull if images have changed
# Location: ~/supercog-installer/scripts/update-supercog-smart.sh

set -e  # Exit on error

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"

# Source colors
source "$SCRIPT_DIR/../utils/colors.sh"

# Configuration
COMPOSE_DIR="${SUPERCOG_HOME:-$INSTALLER_DIR}"
COMPOSE_FILE="docker-compose.yml"
LOG_FILE="$COMPOSE_DIR/logs/update.log"
STATE_FILE="$COMPOSE_DIR/.update-state"

# Load registry configuration if available
if [ -f "$INSTALLER_DIR/.supercog-registry" ]; then
    source "$INSTALLER_DIR/.supercog-registry"
fi

# Load environment variables
if [ -f "$INSTALLER_DIR/.env" ]; then
    source "$INSTALLER_DIR/.env"
fi

# Default to registry URL from env or use default
REGISTRY_URL="${REGISTRY_URL:-supercog-registry.fly.dev}"

# Images to check
IMAGES=("engine:latest" "dashboard:latest")

# Function to log messages
log_message() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to get image manifest digest from registry
get_registry_digest() {
    local image=$1
    local full_image="$REGISTRY_URL/$image"
    
    # Try to get manifest digest using docker manifest inspect
    # This requires experimental features to be enabled
    if docker manifest inspect "$full_image" &>/dev/null; then
        docker manifest inspect "$full_image" 2>/dev/null | jq -r '.config.digest' || \
        docker manifest inspect "$full_image" 2>/dev/null | jq -r '.digest'
    else
        # Fallback: try to get digest using curl
        local tag="${image#*:}"
        local repo="${image%:*}"
        
        # First try without auth
        local response=$(curl -s -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
                              "https://$REGISTRY_URL/v2/$repo/manifests/$tag")
        
        # Check if we need auth
        if echo "$response" | grep -q "unauthorized"; then
            # Need to login first
            if [ -n "$REGISTRY_USERNAME" ]; then
                echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" -u "$REGISTRY_USERNAME" --password-stdin &>/dev/null
            fi
            # After login, docker manifest inspect should work
            docker manifest inspect "$full_image" 2>/dev/null | jq -r '.config.digest' || echo ""
        else
            echo "$response" | jq -r '.config.digest' || echo ""
        fi
    fi
}

# Function to get local image digest
get_local_digest() {
    local image=$1
    local full_image="$REGISTRY_URL/$image"
    
    # Check if image exists locally
    if docker image inspect "$full_image" &>/dev/null; then
        # Get the digest from RepoDigests
        local digest=$(docker image inspect "$full_image" --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' 2>/dev/null)
        if [ -n "$digest" ] && [ "$digest" != "<no value>" ]; then
            # Extract just the digest part (after @)
            echo "${digest#*@}"
        else
            # If no RepoDigests, use the image ID as fallback
            docker image inspect "$full_image" --format '{{.Id}}' 2>/dev/null | cut -d: -f2 | head -c 12
        fi
    else
        echo ""
    fi
}

# Function to check if update is needed
check_update_needed() {
    local image=$1
    local full_image="$REGISTRY_URL/$image"
    
    print_info "Checking $image..."
    
    # Get local digest
    local local_digest=$(get_local_digest "$image")
    
    if [ -z "$local_digest" ]; then
        print_warning "  Image not found locally - need to pull"
        return 0  # Update needed
    fi
    
    # For simple comparison, we'll pull and check if anything changed
    # This is because getting remote digest reliably can be complex
    print_info "  Current: ${local_digest:0:12}..."
    
    # Try to pull - Docker will tell us if image is up to date
    local pull_output=$(docker pull "$full_image" 2>&1)
    
    if echo "$pull_output" | grep -q "Image is up to date"; then
        print_success "  Up to date"
        return 1  # No update needed
    elif echo "$pull_output" | grep -q "Downloaded newer image\|Pulled"; then
        local new_digest=$(get_local_digest "$image")
        print_warning "  Updated to: ${new_digest:0:12}..."
        return 0  # Update performed
    else
        print_error "  Failed to check: $pull_output"
        return 2  # Error
    fi
}

# Function to perform update check
perform_update_check() {
    local updates_found=false
    local errors_found=false
    
    print_info "Checking for Supercog updates..."
    echo ""
    
    # Ensure we're logged into registry
    if [ -n "$REGISTRY_USERNAME" ] && [ -f "$INSTALLER_DIR/.supercog-registry" ]; then
        print_info "Authenticating with registry..."
        if ! docker login "$REGISTRY_URL" -u "$REGISTRY_USERNAME" --password-stdin < /dev/null &>/dev/null; then
            print_warning "Note: Not logged into registry, using cached credentials"
        fi
    fi
    
    # Check each image
    for image in "${IMAGES[@]}"; do
        if check_update_needed "$image"; then
            updates_found=true
        elif [ $? -eq 2 ]; then
            errors_found=true
        fi
    done
    
    echo ""
    
    if [ "$errors_found" = true ]; then
        print_error "Some images could not be checked"
        return 2
    elif [ "$updates_found" = true ]; then
        return 0  # Updates available/applied
    else
        return 1  # No updates
    fi
}

# Function to restart services
restart_services() {
    print_info "Restarting services..."
    
    cd "$COMPOSE_DIR"
    
    # Stop services gracefully
    print_info "Stopping services..."
    if docker-compose down; then
        print_success "Services stopped"
        log_message "Services stopped successfully"
    else
        print_error "Failed to stop services"
        log_message "Failed to stop services"
        return 1
    fi
    
    # Start services
    print_info "Starting services..."
    if docker-compose up -d; then
        print_success "Services started"
        log_message "Services started successfully"
    else
        print_error "Failed to start services"
        log_message "Failed to start services"
        return 1
    fi
    
    # Wait for services to be ready
    print_info "Waiting for services to be ready..."
    sleep 10
    
    # Quick health check
    local healthy=true
    for service in postgres redis minio engine dashboard; do
        if docker-compose ps | grep -E "${service}.*Up.*healthy" &>/dev/null; then
            print_success "  $service is healthy"
        elif docker-compose ps | grep -E "${service}.*Up" &>/dev/null; then
            print_warning "  $service is running (health check pending)"
        else
            print_error "  $service is not running"
            healthy=false
        fi
    done
    
    if [ "$healthy" = true ]; then
        return 0
    else
        return 1
    fi
}

# Function to show current status
show_status() {
    print_info "Current image versions:"
    echo ""
    
    for image in "${IMAGES[@]}"; do
        local full_image="$REGISTRY_URL/$image"
        local digest=$(get_local_digest "$image")
        local image_date=$(docker image inspect "$full_image" --format '{{.Created}}' 2>/dev/null | cut -d'T' -f1)
        
        if [ -n "$digest" ]; then
            printf "  %-20s %s (created: %s)\n" "$image:" "${digest:0:12}..." "${image_date:-unknown}"
        else
            printf "  %-20s %s\n" "$image:" "Not installed"
        fi
    done
}

# Function to clean old images
clean_old_images() {
    print_info "Cleaning old images..."
    
    # Remove dangling images
    docker image prune -f
    
    # Remove old versions of our images (keeping current ones)
    for image in "${IMAGES[@]}"; do
        local full_image="$REGISTRY_URL/$image"
        # Get all images with this repository name
        docker images "$REGISTRY_URL/${image%:*}" --format "{{.Repository}}:{{.Tag}} {{.ID}}" | \
        grep -v ":latest" | \
        awk '{print $2}' | \
        xargs -r docker rmi 2>/dev/null || true
    done
    
    print_success "Cleanup complete"
}

# Main function
main() {
    print_header() {
        echo ""
        echo "==================================="
        echo "  Supercog Update Manager"
        echo "==================================="
        echo ""
    }
    
    # Check prerequisites
    if [ "$EUID" -eq 0 ]; then
        print_error "Please do not run this script as root"
        exit 1
    fi
    
    if ! docker info &>/dev/null; then
        print_error "Docker is not running or you don't have permissions"
        exit 1
    fi
    
    if [ ! -f "$COMPOSE_DIR/$COMPOSE_FILE" ]; then
        print_error "docker-compose.yml not found in $COMPOSE_DIR"
        exit 1
    fi
    
    # Parse command
    case "${1:-check}" in
        check)
            print_header
            
            # Just check for updates (actually pulls to check)
            if perform_update_check; then
                print_warning "Updates were found and downloaded"
                print_info "Run '$0 restart' to apply the updates"
                exit 0
            else
                print_success "All images are up to date!"
                exit 0
            fi
            ;;
            
        update)
            print_header
            
            # Check and apply updates
            if perform_update_check; then
                echo ""
                print_warning "Updates have been downloaded"
                
                # Ask for confirmation to restart
                if [ "${FORCE:-}" != "true" ]; then
                    read -p "Do you want to restart services now? (y/n) " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        print_info "Updates downloaded but not applied"
                        print_info "Run '$0 restart' when ready to apply"
                        exit 0
                    fi
                fi
                
                # Restart services
                if restart_services; then
                    print_success "Update completed successfully!"
                    log_message "Update completed successfully"
                    
                    # Clean old images
                    clean_old_images
                    
                    exit 0
                else
                    print_error "Failed to restart services"
                    log_message "Failed to restart services"
                    exit 1
                fi
            else
                print_success "All images are up to date!"
                exit 0
            fi
            ;;
            
        restart)
            print_header
            
            # Just restart services
            if restart_services; then
                print_success "Services restarted successfully!"
                exit 0
            else
                print_error "Failed to restart services"
                exit 1
            fi
            ;;
            
        status)
            print_header
            show_status
            ;;
            
        clean)
            print_header
            clean_old_images
            ;;
            
        auto)
            # For cron jobs - update and restart automatically
            FORCE=true
            log_message "Starting automatic update check"
            
            if perform_update_check; then
                log_message "Updates found, restarting services"
                if restart_services; then
                    log_message "Automatic update completed successfully"
                    clean_old_images
                else
                    log_message "Automatic update failed during restart"
                    exit 1
                fi
            else
                log_message "No updates found"
            fi
            ;;
            
        *)
            echo "Usage: $0 [check|update|restart|status|clean|auto]"
            echo ""
            echo "Commands:"
            echo "  check    - Check for available updates (default)"
            echo "  update   - Check for updates and restart services if found"
            echo "  restart  - Restart all services"
            echo "  status   - Show current image versions"
            echo "  clean    - Remove old unused images"
            echo "  auto     - Automatic mode for cron (no prompts)"
            echo ""
            echo "Examples:"
            echo "  $0 check           # Check if updates are available"
            echo "  $0 update          # Update and restart if needed"
            echo "  $0 status          # Show current versions"
            echo ""
            echo "For automatic updates via cron:"
            echo "  0 2 * * * $SCRIPT_DIR/update-supercog-smart.sh auto"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
