#!/bin/bash
# Health check script for Supercog services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"

# Source colors
source "$SCRIPT_DIR/../utils/colors.sh"

# Change to installer directory
cd "$INSTALLER_DIR"

# Check if services are running
print_info "Checking service status..."
echo ""

# Define services and their health endpoints
declare -A services=(
    ["postgres"]="PostgreSQL Database"
    ["redis"]="Redis Cache"
    ["minio"]="MinIO Storage"
    ["engine"]="Supercog Engine"
    ["triggersvc"]="Trigger Service"
    ["dashboard"]="Supercog Dashboard"
)

declare -A health_checks=(
    ["postgres"]="docker-compose exec -T postgres pg_isready -U pguser"
    ["redis"]="docker-compose exec -T redis redis-cli ping"
    ["minio"]="curl -s -f http://localhost:${MINIO_API_PORT_NUMBER:-9002}/minio/health/live"
    ["engine"]="curl -s -f http://localhost:8080/health"
    ["triggersvc"]="curl -s -f http://localhost:8002/health"
    ["dashboard"]="curl -s -f http://localhost:3000"
)

# Track overall health
all_healthy=true

# Check each service
for service in "${!services[@]}"; do
    printf "%-20s" "${services[$service]}:"
    
    # Check if container is running
    if ! docker-compose ps | grep -q "${service}.*Up"; then
        print_error " Container not running"
        all_healthy=false
        continue
    fi
    
    # Run health check
    if [ -n "${health_checks[$service]}" ]; then
        if eval "${health_checks[$service]}" &>/dev/null; then
            print_success " Healthy"
        else
            print_error " Unhealthy"
            all_healthy=false
        fi
    else
        print_warning " No health check defined"
    fi
done

echo ""

# Check disk usage
print_info "Disk usage:"
df -h "$INSTALLER_DIR" | tail -n 1 | awk '{print "  Total: " $2 ", Used: " $3 " (" $5 "), Available: " $4}'

echo ""

# Check Docker volumes
print_info "Docker volumes:"
for volume in postgres_data redis_data minio_data; do
    size=$(docker volume inspect "$(basename $INSTALLER_DIR)_${volume}" 2>/dev/null | jq -r '.[0].UsageData.Size // "unknown"' 2>/dev/null || echo "unknown")
    if [ "$size" != "unknown" ] && [ "$size" != "null" ]; then
        size_mb=$((size / 1024 / 1024))
        printf "  %-20s %dMB\n" "$volume:" "$size_mb"
    else
        printf "  %-20s %s\n" "$volume:" "unknown"
    fi
done

echo ""

# Check logs for errors
print_info "Recent errors (last 10 minutes):"
error_count=0
for service in "${!services[@]}"; do
    errors=$(docker-compose logs --since 10m "$service" 2>&1 | grep -iE "(error|exception|fatal)" | wc -l)
    if [ "$errors" -gt 0 ]; then
        printf "  %-20s %d errors\n" "${services[$service]}:" "$errors"
        error_count=$((error_count + errors))
    fi
done

if [ "$error_count" -eq 0 ]; then
    echo "  No errors found"
fi

echo ""

# Overall status
if [ "$all_healthy" = true ] && [ "$error_count" -eq 0 ]; then
    print_success "Overall status: All systems operational"
    exit 0
else
    print_error "Overall status: Issues detected"
    exit 1
fi
