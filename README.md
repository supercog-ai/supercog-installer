# Supercog On-Premise Installer

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/supercog-ai/supercog-installer/releases)
[![Docker](https://img.shields.io/badge/docker-%3E%3D20.10-blue.svg)](https://www.docker.com/)
[![PostgreSQL](https://img.shields.io/badge/postgresql-16-blue.svg)](https://www.postgresql.org/)

Complete installation package for deploying Supercog on-premise with enterprise-grade reliability, monitoring, and security.

## 🚀 Installation Steps

### Quick Start

```bash
# Clone the installer
git clone https://github.com/supercog-ai/supercog-installer.git
cd supercog-installer

# Make all scripts executable
chmod +x scripts/*.sh scripts/install/*.sh utils/*.sh

# Run the installation steps
./scripts/install/01-install-docker.sh
./scripts/install/02-create-directories.sh
./scripts/install/03-setup-env-file.sh
./scripts/install/04-configure-registry.sh
./scripts/install/05-init-databases.sh

# Start services
docker compose up -d
```

### Detailed Installation Process

Run each installation script in order:

#### 1. Install Docker
```bash
./scripts/install/01-install-docker.sh
```
- Detects your OS and installs Docker + Docker Compose
- Configures Docker to start on boot
- Sets up proper permissions so you can run Docker without sudo
- Configures log rotation and other optimizations

#### 2. Create Directory Structure
```bash
./scripts/install/02-create-directories.sh
```
- Creates required directories for logs, backups, keys, and local data
- Sets appropriate permissions on sensitive directories

#### 3. Setup Environment and API Keys
```bash
./scripts/install/03-setup-env-file.sh
```
- Creates `.env` file from template
- Configures AI API keys (OpenAI and/or Claude)
- Generates security keys (ECDSA keys and master encryption key)
- You need at least one AI API key for Supercog to function

#### 4. Configure Registry Access
```bash
./scripts/install/04-configure-registry.sh
```
- Sets up authentication to pull Supercog Docker images
- Tests registry connection
- Saves credentials securely in `.env`

#### 5. Start Services
```bash
docker compose up -d
```
- Starts all Supercog services
- Access the dashboard at http://localhost:3000

## 🛠️ Management Scripts

### Service Management

**Health Check**
```bash
./scripts/health-check.sh
```
- Checks status of all services
- Shows disk usage and Docker volumes
- Reports recent errors from logs
- Overall system health status

**Update Manager**
```bash
./scripts/update-supercog.sh [command]
```
Commands:
- `check` - Check for available updates (default)
- `update` - Download updates and restart services
- `restart` - Restart all services
- `status` - Show current image versions
- `clean` - Remove old unused images
- `auto` - Automatic mode for cron jobs

**Log Manager**
```bash
./scripts/logs-manager.sh [command] [service]
```
Commands:
- `collect [service]` - Save logs to file
- `tail [service]` - Follow logs in real-time
- `clean` - Remove logs older than 7 days
- `analyze` - Show recent errors and warnings

### Backup & Restore

**Create Backup**
```bash
./scripts/backup.sh
```
- Backs up all databases
- Backs up MinIO/S3 data
- Saves configuration files
- Creates compressed archive with timestamp
- Automatically cleans old backups (keeps last 7)

**Restore from Backup**
```bash
./scripts/restore.sh <backup-file> [options]
```
Options:
- `--data-only` - Restore only databases and files
- `--config-only` - Restore only configuration
- `--force` - Skip confirmation prompts
- `--no-stop` - Don't stop services before restore

### Reset Database
```bash
./scripts/init-databases.sh
```
- Starts PostgreSQL container
- Creates all required databases (dashboard, engine, credentials, RAG)
- Sets up pgvector extension for embeddings
- Verifies database creation

## 🔧 Utility Scripts

**Generate Security Keys**
```bash
./utils/generate-keys.sh [command]
```
Commands:
- `generate` - Generate missing keys (default)
- `show` - Show which keys are set
- `regenerate` - Force regenerate all keys (WARNING: data loss risk)

**System Check**
```bash
./utils/system-check.sh
```
- Verifies system meets requirements
- Checks available disk space, RAM, and CPU
- Tests Docker installation
- Validates network connectivity

## 📦 What's Included

### Core Services
- **Supercog Dashboard** (Port 3000) - Web interface for managing agents
- **Supercog Engine** (Port 8080) - Core AI processing engine
- **PostgreSQL** (Port 5432) - Database with pgvector for embeddings
- **Redis** (Port 6379) - Caching and session storage
- **MinIO** (Port 9002/9003) - S3-compatible object storage

### Architecture
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    Dashboard    │────▶│     Engine      │────▶│   PostgreSQL    │
│   (Port 3000)   │     │   (Port 8080)   │     │   (Port 5432)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │                          │
                               ▼                          ▼
                        ┌─────────────────┐     ┌─────────────────┐
                        │     Redis       │     │     MinIO       │
                        │   (Port 6379)   │     │   (Port 9002)   │
                        └─────────────────┘     └─────────────────┘
```

## 🔄 Automatic Updates

Enable nightly updates by adding to crontab:
```bash
# Check and apply updates at 2 AM daily
0 2 * * * /path/to/supercog-installer/scripts/update-supercog.sh auto
```

## 📁 Directory Structure

```
supercog-installer/
├── docker-compose.yml     # Service definitions
├── .env.example          # Environment template
├── scripts/              # Management scripts
│   ├── install/          # Step-by-step installers
│   ├── update-supercog.sh
│   ├── health-check.sh
│   ├── backup.sh
│   ├── restore.sh
│   └── logs-manager.sh
├── utils/                # Utility scripts
│   ├── generate-keys.sh
│   └── colors.sh
├── sql/                  # Database schemas
└── logs/                 # Application logs (created at runtime)
```

## 🚨 Common Operations

### Start/Stop Services
```bash
# Stop all services
docker compose down

# Start all services
docker compose up -d

# Restart specific service
docker compose restart engine

# View service status
docker compose ps
```

### View Logs
```bash
# Tail all service logs
./scripts/logs-manager.sh tail

# Tail specific service
./scripts/logs-manager.sh tail engine

# Collect logs for support
./scripts/logs-manager.sh collect
```

### Reset Installation
```bash
# Stop and remove everything
docker compose down -v

# Remove data directories
rm -rf local_data/ logs/ backups/

# Start fresh
./scripts/install.sh
```

## 🤝 Support

### Getting Help
- **Email**: support@supercog.ai
- **Issues**: [GitHub Issues](https://github.com/supercog-ai/supercog-installer/issues)

### Before Contacting Support
1. Check service health: `./scripts/health-check.sh`
2. Collect logs: `./scripts/logs-manager.sh collect`
3. Note your version: `cat VERSION`

---

Made with ❤️ by the Supercog team
