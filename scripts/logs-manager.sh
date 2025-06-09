#!/bin/bash
# Log management script for Supercog

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$INSTALLER_DIR/logs"

# Source colors
source "$SCRIPT_DIR/../utils/colors.sh"

# Create log directory
mkdir -p "$LOG_DIR"

# Function to collect logs
collect_logs() {
    local service=$1
    local output_file="$LOG_DIR/${service}_$(date +%Y%m%d_%H%M%S).log"
    
    print_info "Collecting logs for $service..."
    docker-compose logs --no-color --timestamps "$service" > "$output_file" 2>&1
    
    # Compress if large
    if [ -f "$output_file" ] && [ $(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file") -gt 10485760 ]; then
        gzip "$output_file"
        print_success "Logs saved to ${output_file}.gz"
    else
        print_success "Logs saved to $output_file"
    fi
}

# Function to tail logs
tail_logs() {
    local service=$1
    if [ -z "$service" ]; then
        docker-compose logs -f --tail=100
    else
        docker-compose logs -f --tail=100 "$service"
    fi
}

# Function to clean old logs
clean_logs() {
    print_info "Cleaning logs older than 7 days..."
    find "$LOG_DIR" -type f -name "*.log*" -mtime +7 -delete
    print_success "Old logs cleaned"
}

# Main menu
case "${1:-help}" in
    collect)
        if [ -z "$2" ]; then
            # Collect all services
            for service in postgres redis minio engine triggersvc dashboard; do
                collect_logs "$service"
            done
        else
            collect_logs "$2"
        fi
        ;;
    
    tail)
        tail_logs "$2"
        ;;
    
    clean)
        clean_logs
        ;;
    
    analyze)
        print_info "Recent errors and warnings:"
        echo ""
        for service in postgres redis minio engine triggersvc dashboard; do
            echo "=== $service ==="
            docker-compose logs --no-color --since 1h "$service" 2>&1 | \
                grep -iE "(error|warning|exception|fatal)" | \
                tail -10 || echo "No errors/warnings found"
            echo ""
        done
        ;;
    
    *)
        echo "Usage: $0 {collect|tail|clean|analyze} [service]"
        echo ""
        echo "Commands:"
        echo "  collect [service]  - Collect and save logs"
        echo "  tail [service]     - Tail logs in real-time"
        echo "  clean              - Remove logs older than 7 days"
        echo "  analyze            - Show recent errors and warnings"
        echo ""
        echo "Services: postgres, redis, minio, engine, triggersvc, dashboard"
        ;;
esac
