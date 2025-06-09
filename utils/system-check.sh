#!/bin/bash
# System requirements checker

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/colors.sh"

# Requirements
MIN_RAM_MB=4096
MIN_DISK_GB=20
MIN_CPU_CORES=2

check_ram() {
    local total_ram=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_ram" -lt "$MIN_RAM_MB" ]; then
        print_error "Insufficient RAM: ${total_ram}MB (minimum: ${MIN_RAM_MB}MB)"
        return 1
    else
        print_success "RAM: ${total_ram}MB ✓"
        return 0
    fi
}

check_disk() {
    local available_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_gb" -lt "$MIN_DISK_GB" ]; then
        print_error "Insufficient disk space: ${available_gb}GB (minimum: ${MIN_DISK_GB}GB)"
        return 1
    else
        print_success "Disk space: ${available_gb}GB available ✓"
        return 0
    fi
}

check_cpu() {
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt "$MIN_CPU_CORES" ]; then
        print_warning "Low CPU cores: ${cpu_cores} (recommended: ${MIN_CPU_CORES}+)"
    else
        print_success "CPU cores: ${cpu_cores} ✓"
    fi
}

check_ports() {
    local ports=(3000 8000 8080 5432 6379 9000 9001)
    local ports_in_use=()
    
    for port in "${ports[@]}"; do
        if ss -tuln 2>/dev/null | grep -q ":$port " || netstat -tuln 2>/dev/null | grep -q ":$port "; then
            ports_in_use+=($port)
        fi
    done
    
    if [ ${#ports_in_use[@]} -gt 0 ]; then
        print_warning "Ports in use: ${ports_in_use[*]}"
        print_warning "You may need to stop conflicting services"
    else
        print_success "Required ports available ✓"
    fi
}

# Run all checks
print_info "Checking system requirements..."
echo ""

failed=false
check_ram || failed=true
check_disk || failed=true
check_cpu
check_ports

echo ""
if [ "$failed" = true ]; then
    print_error "System does not meet minimum requirements"
    exit 1
else
    print_success "System meets all requirements"
fi
