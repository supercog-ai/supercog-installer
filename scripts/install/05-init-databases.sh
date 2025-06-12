#!/bin/bash
# Initialize PostgreSQL databases for Supercog

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source colors
source "$SCRIPT_DIR/../../utils/colors.sh"

# Change to installer directory
cd "$INSTALLER_DIR"

print_info "Initializing Supercog databases..."
echo ""

# Start PostgreSQL if not running
if ! docker compose ps postgres | grep -q "Up.*healthy\|Up.*starting\|Up.*running"; then
    print_info "Starting PostgreSQL..."
    if docker compose up -d postgres; then
        print_success "PostgreSQL container started"
    else
        print_error "Failed to start PostgreSQL"
        exit 1
    fi
else
    print_info "PostgreSQL is already running"
fi

# Wait for PostgreSQL to be ready
print_info "Ensuring PostgreSQL is ready..."
max_attempts=30
attempt=0

while ! docker compose exec -T postgres pg_isready -U pguser &>/dev/null; do
    attempt=$((attempt + 1))
    if [ $attempt -eq $max_attempts ]; then
        print_error "PostgreSQL is not responding"
        docker compose logs --tail=50 postgres
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""
print_success "PostgreSQL is ready"

# Check if databases already exist
print_info "Checking existing databases..."
existing_dbs=$(docker compose exec -T postgres psql -U pguser -d postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;" | grep -E '(monster_dashboard|monster_engine|monster_credentials|monster_rag)' || true)

if [ -n "$existing_dbs" ]; then
    print_warning "Found existing databases:"
    echo "$existing_dbs" | sed 's/^/  /'
    echo ""
    read -p "Do you want to reinitialize databases? This will DELETE all data! (y/N) " -n 1 -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Database initialization cancelled"
        exit 0
    fi
    
    # Drop existing databases
    print_warning "Dropping existing databases..."
    for db in monster_dashboard monster_engine monster_credentials monster_rag; do
        docker compose exec -T postgres psql -U pguser -d postgres -c "DROP DATABASE IF EXISTS $db;" || true
    done
fi

# Initialize databases
databases=(
    "01-monster_dashboard.sql"
    "02-monster_engine.sql"
    "03-monster_credentials.sql"
    "04-monster_rag.sql"
)

for sql_file in "${databases[@]}"; do
    db_name=$(echo $sql_file | sed 's/[0-9]*-//;s/.sql$//')
    
    if [ ! -f "$SCRIPT_DIR/../../sql//$sql_file" ]; then
        print_error "SQL file not found: $sql_file"
        exit 1
    fi
    
    print_info "Creating database: $db_name..."
    
    if docker compose exec -T postgres psql -U pguser -d postgres < "$SCRIPT_DIR/../../sql/$sql_file"; then
        print_success "  ✓ $db_name created"
    else
        print_error "  ✗ Failed to create $db_name"
        exit 1
    fi
done

# Verify databases were created
echo ""
print_info "Verifying databases..."
for db in monster_dashboard monster_engine monster_credentials monster_rag; do
    if docker compose exec -T postgres psql -U pguser -d postgres -t -c "SELECT 1 FROM pg_database WHERE datname='$db';" | grep -q 1; then
        print_success "  ✓ $db exists"
    else
        print_error "  ✗ $db not found"
        exit 1
    fi
done

# Check for pgvector extension in monster_rag
print_info "Checking pgvector extension..."
if docker compose exec -T postgres psql -U pguser -d monster_rag -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null; then
    print_success "pgvector extension is available"
else
    print_warning "pgvector extension not available (embeddings may not work)"
fi

# Show database sizes
echo ""
print_info "Database information:"
docker compose exec -T postgres psql -U pguser -d postgres -c "
SELECT 
    datname as database,
    pg_size_pretty(pg_database_size(datname)) as size
FROM pg_database 
WHERE datname LIKE 'monster_%'
ORDER BY datname;"

echo ""
print_success "All databases initialized successfully!"

echo ""
echo "Next step: Start the application: docker compose up -d"

exit 0
