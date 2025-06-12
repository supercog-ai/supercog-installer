#!/bin/bash
# Backup Supercog data

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/../utils/colors.sh"

# Backup directory
BACKUP_DIR="$INSTALLER_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/supercog_backup_$TIMESTAMP"

# Create backup directory
mkdir -p "$BACKUP_PATH"

print_info "Starting Supercog backup..."

# Backup databases
print_info "Backing up databases..."
cd "$INSTALLER_DIR"

for db in monster_dashboard monster_engine monster_credentials monster_rag; do
    print_info "  Backing up $db..."
    docker compose exec -T postgres pg_dump -U pguser $db | gzip > "$BACKUP_PATH/${db}.sql.gz"
done

# Backup MinIO data
print_info "Backing up MinIO data..."
docker run --rm -v $(basename $INSTALLER_DIR)_minio_data:/source -v "$BACKUP_PATH:/backup" \
    alpine tar czf /backup/minio_data.tar.gz -C /source .

# Backup configuration
print_info "Backing up configuration..."
cp "$INSTALLER_DIR/.env" "$BACKUP_PATH/"

# Create backup info
cat > "$BACKUP_PATH/backup_info.txt" <<EOF
Supercog Backup
Created: $(date)
Version: $(cat $INSTALLER_DIR/VERSION)
EOF

# Compress entire backup
print_info "Compressing backup..."
cd "$BACKUP_DIR"
tar czf "supercog_backup_$TIMESTAMP.tar.gz" "supercog_backup_$TIMESTAMP"
rm -rf "$BACKUP_PATH"

# Clean old backups (keep last 7)
print_info "Cleaning old backups..."
ls -t "$BACKUP_DIR"/supercog_backup_*.tar.gz | tail -n +8 | xargs -r rm

print_success "Backup completed: $BACKUP_DIR/supercog_backup_$TIMESTAMP.tar.gz"
