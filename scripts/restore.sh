#!/bin/bash

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source helpers
source "$SCRIPT_DIR/../utils/colors.sh"

# Configuration
BACKUP_DIR="$INSTALLER_DIR/backups"
TEMP_DIR="/tmp/supercog_restore_$$"

# Function to show usage
show_usage() {
    echo "Usage: $0 <backup-file> [options]"
    echo ""
    echo "Arguments:"
    echo "  backup-file    Path to backup tar.gz file"
    echo ""
    echo "Options:"
    echo "  --data-only    Restore only databases and files (keep current config)"
    echo "  --config-only  Restore only configuration files"
    echo "  --force        Skip confirmation prompts"
    echo "  --no-stop      Don't stop services before restore"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/supercog_backup_20240115_120000.tar.gz"
    echo "  $0 ./backups/latest.tar.gz --data-only"
}

# Parse arguments
BACKUP_FILE=""
DATA_ONLY=false
CONFIG_ONLY=false
FORCE=false
NO_STOP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --data-only)
            DATA_ONLY=true
            shift
            ;;
        --config-only)
            CONFIG_ONLY=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --no-stop)
            NO_STOP=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            if [ -z "$BACKUP_FILE" ]; then
                BACKUP_FILE="$1"
            else
                print_error "Unknown option: $1"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [ -z "$BACKUP_FILE" ]; then
    print_error "No backup file specified"
    show_usage
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    print_error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

if [ "$DATA_ONLY" = true ] && [ "$CONFIG_ONLY" = true ]; then
    print_error "Cannot use --data-only and --config-only together"
    exit 1
fi

# Function to extract backup
extract_backup() {
    print_info "Extracting backup..."
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Extract backup
    tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR" || {
        print_error "Failed to extract backup"
        cleanup_temp
        exit 1
    }
    
    # Find the backup directory (handle nested structure)
    BACKUP_ROOT=$(find "$TEMP_DIR" -name "backup_info.txt" -type f | head -1 | xargs dirname)
    
    if [ -z "$BACKUP_ROOT" ] || [ ! -d "$BACKUP_ROOT" ]; then
        print_error "Invalid backup format - backup_info.txt not found"
        cleanup_temp
        exit 1
    fi
    
    print_success "Backup extracted successfully"
}

# Function to show backup info
show_backup_info() {
    print_info "Backup Information:"
    if [ -f "$BACKUP_ROOT/backup_info.txt" ]; then
        cat "$BACKUP_ROOT/backup_info.txt" | sed 's/^/  /'
    else
        print_warning "  No backup info found"
    fi
    echo ""
}

# Function to verify backup compatibility
verify_backup() {
    print_info "Verifying backup compatibility..."
    
    # Check for required files
    local required_files=(
        "monster_dashboard.sql.gz"
        "monster_engine.sql.gz"
        "monster_credentials.sql.gz"
        ".env"
    )
    
    local missing_files=()
    for file in "${required_files[@]}"; do
        if [ ! -f "$BACKUP_ROOT/$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_warning "Missing files in backup:"
        printf '  - %s\n' "${missing_files[@]}"
        
        if [ "$FORCE" != true ]; then
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                cleanup_temp
                exit 1
            fi
        fi
    else
        print_success "Backup verification passed"
    fi
}

# Function to stop services
stop_services() {
    if [ "$NO_STOP" = true ]; then
        print_warning "Skipping service stop (--no-stop specified)"
        return 0
    fi
    
    print_info "Stopping Supercog services..."
    
    cd "$INSTALLER_DIR"
    
    # Stop application services but keep databases running
    docker compose stop dashboard triggersvc engine || {
        print_warning "Some services may not have stopped cleanly"
    }
    
    print_success "Services stopped"
}

# Function to restore databases
restore_databases() {
    if [ "$CONFIG_ONLY" = true ]; then
        print_info "Skipping database restore (--config-only specified)"
        return 0
    fi
    
    print_info "Restoring databases..."
    
    cd "$INSTALLER_DIR"
    
    # Ensure PostgreSQL is running
    docker compose up -d postgres
    
    # Wait for PostgreSQL to be ready
    print_info "Waiting for PostgreSQL..."
    local max_attempts=30
    local attempt=0
    
    while ! docker compose exec -T postgres pg_isready -U pguser &>/dev/null; do
        attempt=$((attempt + 1))
        if [ $attempt -eq $max_attempts ]; then
            print_error "PostgreSQL failed to start"
            exit 1
        fi
        sleep 2
    done
    
    # Restore each database
    local databases=("monster_dashboard" "monster_engine" "monster_credentials" "monster_rag")
    
    for db in "${databases[@]}"; do
        local backup_file="$BACKUP_ROOT/${db}.sql.gz"
        
        if [ -f "$backup_file" ]; then
            print_info "  Restoring $db..."
            
            # Drop existing database
            docker compose exec -T postgres psql -U pguser -d postgres -c "DROP DATABASE IF EXISTS $db;" || true
            
            # Create new database
            docker compose exec -T postgres psql -U pguser -d postgres -c "CREATE DATABASE $db;"
            
            # Restore from backup
            gunzip -c "$backup_file" | docker compose exec -T postgres psql -U pguser -d "$db" || {
                print_error "Failed to restore $db"
                exit 1
            }
            
            print_success "  $db restored"
        else
            print_warning "  Backup for $db not found, skipping"
        fi
    done
    
    print_success "Database restore completed"
}

# Function to restore MinIO data
restore_minio() {
    if [ "$CONFIG_ONLY" = true ]; then
        print_info "Skipping MinIO restore (--config-only specified)"
        return 0
    fi
    
    if [ -f "$BACKUP_ROOT/minio_data.tar.gz" ]; then
        print_info "Restoring MinIO data..."
        
        cd "$INSTALLER_DIR"
        
        # Ensure MinIO is running
        docker compose up -d minio
        sleep 5
        
        # Get volume name
        local volume_name=$(docker compose ps -q minio | xargs docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }}{{ end }}{{ end }}' | grep minio_data | head -1)
        
        if [ -n "$volume_name" ]; then
            # Stop MinIO temporarily
            docker compose stop minio
            
            # Restore data
            docker run --rm -v "$volume_name:/target" -v "$BACKUP_ROOT:/backup" \
                alpine sh -c "rm -rf /target/* && tar -xzf /backup/minio_data.tar.gz -C /target"
            
            # Start MinIO again
            docker compose up -d minio
            
            print_success "MinIO data restored"
        else
            print_warning "Could not find MinIO volume, skipping MinIO restore"
        fi
    else
        print_info "No MinIO backup found, skipping"
    fi
}

# Function to restore configuration
restore_configuration() {
    if [ "$DATA_ONLY" = true ]; then
        print_info "Skipping configuration restore (--data-only specified)"
        return 0
    fi
    
    print_info "Restoring configuration..."
    
    # Backup current .env
    if [ -f "$INSTALLER_DIR/.env" ]; then
        cp "$INSTALLER_DIR/.env" "$INSTALLER_DIR/.env.before_restore"
        print_info "Current .env backed up to .env.before_restore"
    fi
    
    # Restore .env
    if [ -f "$BACKUP_ROOT/.env" ]; then
        cp "$BACKUP_ROOT/.env" "$INSTALLER_DIR/.env"
        print_success "Configuration restored"
        
        # Regenerate keys if they're missing
        if ! grep -q "^DASH_PRIVATE_KEY=..*" "$INSTALLER_DIR/.env"; then
            print_warning "Security keys missing in backup, regenerating..."
            "$SCRIPT_DIR/../utils/generate-keys.sh"
        fi
    else
        print_warning "No .env in backup, keeping current configuration"
    fi
}

# Function to start services
start_services() {
    if [ "$NO_STOP" = true ]; then
        print_info "Restarting only stopped services..."
        docker compose up -d dashboard triggersvc engine
    else
        print_info "Starting all services..."
        cd "$INSTALLER_DIR"
        docker compose up -d
    fi
    
    # Wait for services to be ready
    print_info "Waiting for services to be ready..."
    sleep 15
    
    # Quick health check
    "$SCRIPT_DIR/health-check.sh" || {
        print_warning "Some services may not be healthy yet"
    }
    
    print_success "Services started"
}

# Function to cleanup temp files
cleanup_temp() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Function to create restore report
create_restore_report() {
    local report_file="$BACKUP_DIR/restore_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" <<EOF
Supercog Restore Report
=======================
Date: $(date)
Backup File: $BACKUP_FILE
Restore Type: $([ "$DATA_ONLY" = true ] && echo "Data Only" || [ "$CONFIG_ONLY" = true ] && echo "Config Only" || echo "Full")

Backup Info:
$(cat "$BACKUP_ROOT/backup_info.txt" 2>/dev/null || echo "N/A")

Restored Components:
EOF
    
    if [ "$CONFIG_ONLY" != true ]; then
        echo "- Databases: Yes" >> "$report_file"
        echo "- MinIO Data: $([ -f "$BACKUP_ROOT/minio_data.tar.gz" ] && echo "Yes" || echo "No")" >> "$report_file"
    else
        echo "- Databases: Skipped" >> "$report_file"
        echo "- MinIO Data: Skipped" >> "$report_file"
    fi
    
    if [ "$DATA_ONLY" != true ]; then
        echo "- Configuration: Yes" >> "$report_file"
    else
        echo "- Configuration: Skipped" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "Service Status After Restore:" >> "$report_file"
    docker compose ps >> "$report_file" 2>&1
    
    print_info "Restore report saved to: $report_file"
}

# Main restore process
main() {
    print_info "Supercog Restore Utility"
    echo "========================"
    echo ""
    
    # Extract and verify backup
    extract_backup
    show_backup_info
    verify_backup
    
    # Confirmation
    if [ "$FORCE" != true ]; then
        print_warning "This will restore Supercog from backup"
        print_warning "Current data may be overwritten!"
        echo ""
        read -p "Are you sure you want to continue? (y/N) " -n 1 -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Restore cancelled"
            cleanup_temp
            exit 0
        fi
    fi
    
    # Perform restore
    stop_services
    restore_databases
    restore_minio
    restore_configuration
    start_services
    
    # Cleanup
    cleanup_temp
    
    # Create report
    create_restore_report
    
    # Success message
    print_success "Restore completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Verify services are running: docker compose ps"
    echo "2. Check application access: http://localhost:3000"
    echo "3. Review restore report in: $BACKUP_DIR/"
    echo ""
    
    if [ -f "$INSTALLER_DIR/.env.before_restore" ]; then
        print_info "Your previous configuration was saved to .env.before_restore"
    fi
}

# Set trap to cleanup on exit
trap cleanup_temp EXIT

# Run main function
main
