# Supercog On-Premise Installer

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/supercog-ai/supercog-installer/releases)
[![Docker](https://img.shields.io/badge/docker-%3E%3D20.10-blue.svg)](https://www.docker.com/)
[![PostgreSQL](https://img.shields.io/badge/postgresql-16-blue.svg)](https://www.postgresql.org/)

Complete installation package for deploying Supercog on-premise with enterprise-grade reliability, monitoring, and security.

## 🚀 Quick Start

```bash
# Clone the installer
git clone https://github.com/supercog-ai/supercog-installer.git
cd supercog-installer

chmod +x scripts/*
chmod +x utils/*

# Run the installer
./scripts/install.sh
```

The installer will guide you through:
1. System requirement checks
2. Docker installation (if needed)
3. API key configuration
4. Registry authentication
5. Service deployment

## 📋 Requirements

### Hardware
- **CPU**: 2+ cores (4+ recommended)
- **RAM**: 4GB minimum (8GB recommended)
- **Storage**: 20GB free space (50GB recommended, SSD preferred)
- **Network**: Stable internet connection

### Software
- **OS**: Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+, RHEL 8+)
- **Docker**: 20.10+ (auto-installed if missing)
- **Docker Compose**: 2.0+ (auto-installed if missing)

### API Keys
At least one AI provider API key:
- OpenAI API key (for GPT models), or
- Anthropic Claude API key

## 🏗️ Architecture

Supercog runs as a collection of Docker containers:

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

## 📦 What's Included

### Core Services
- **Supercog Dashboard** - Web interface for managing agents and conversations
- **Supercog Engine** - Core AI processing engine
- **PostgreSQL** - Database with pgvector extension for embeddings
- **Redis** - High-performance caching and session storage
- **MinIO** - S3-compatible object storage for files

### Management Tools
- **Installation Script** - Automated setup with prerequisite checking
- **Smart Updater** - Efficient updates with digest checking
- **Health Monitor** - Service health and resource monitoring
- **Log Manager** - Centralized log collection and analysis
- **Backup System** - Automated backup and restore capabilities

## 🔧 Installation

### 1. Prepare Your System

```bash
# Clone the installer
git clone https://github.com/supercog-ai/supercog-installer.git
cd supercog-installer

# Check system requirements
./utils/system-check.sh
```

### 2. Run Installation

```bash
# Start installation
./scripts/install.sh
```

The installer will:
- ✅ Check system requirements
- ✅ Install Docker if needed
- ✅ Generate security keys
- ✅ Configure API keys
- ✅ Set up registry access
- ✅ Initialize databases
- ✅ Start all services

### 3. Access Supercog

After installation:
- **Dashboard**: http://localhost:3000
- **API**: http://localhost:8080
- **MinIO Console**: http://localhost:9003

## 🔄 Updates

### Check for Updates
```bash
./scripts/update-supercog.sh check
```

### Apply Updates
```bash
./scripts/update-supercog.sh update
```

### Automatic Updates
Add to crontab for nightly updates:
```bash
0 2 * * * /path/to/supercog-installer/scripts/update-supercog.sh auto
```

## 🛠️ Management

### Service Health
```bash
# Check all services
./scripts/health-check.sh

# View service status
docker compose ps
```

### Logs
```bash
# Tail all logs
./scripts/log-manager.sh tail

# Tail specific service
./scripts/log-manager.sh tail engine

# Collect logs for support
./scripts/log-manager.sh collect

# Analyze errors
./scripts/log-manager.sh analyze
```

### Backup & Restore
```bash
# Create backup
./scripts/backup.sh

# Restore from backup
./scripts/restore.sh /path/to/backup.tar.gz
```

### Start/Stop Services
```bash
# Stop all services
docker compose down

# Start all services
docker compose up -d

# Restart specific service
docker compose restart engine
```

## 🔐 Security

### API Keys
- Store API keys in `.env` file
- Never commit `.env` to version control

### Network Security
- Services communicate over Docker internal network
- Only required ports exposed to host
- Use reverse proxy for production deployment

### Data Encryption
- All credentials encrypted with CREDENTIALS_MASTER_KEY
- ECDSA keys for authentication
- Secure session management

## 📁 Directory Structure

```
supercog-installer/
├── docker compose.yml      # Service definitions
├── .env.example           # Environment template
├── scripts/               # Management scripts
│   ├── install.sh         # Main installer
│   ├── update-supercog.sh
│   ├── health-check.sh
│   ├── backup.sh
│   └── ...
├── sql/                   # Database schemas
│   ├── 01-monster_dashboard.sql
│   ├── 02-monster_engine.sql
│   └── ...
├── docs/                  # Documentation
└── logs/                  # Application logs (created at runtime)
```

## 🚨 Troubleshooting

### Common Issues

**Services not starting**
```bash
# Check logs
docker compose logs [service-name]

# Check disk space
df -h

# Check ports
ss -tuln | grep -E '(3000|8080|5432|6379|9002)'
```

**Database connection errors**
```bash
# Restart database
docker compose restart postgres

# Check database logs
docker compose logs postgres
```

**Permission denied errors**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
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

## 📊 Resource Usage

Typical resource consumption:
- **RAM**: 2-4GB under normal load
- **CPU**: 10-30% on 4-core system
- **Disk**: ~5GB for application, plus data
- **Network**: Varies with usage

## 🤝 Support

### Documentation
- [Installation Guide](docs/INSTALLATION.md)
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- [Maintenance Guide](docs/MAINTENANCE.md)

### Getting Help
- **Email**: support@supercog.ai
- **Issues**: [GitHub Issues](https://github.com/supercog-ai/supercog-installer/issues)

### Before Contacting Support
1. Check service health: `./scripts/health-check.sh`
2. Collect logs: `./scripts/log-manager.sh collect`
3. Note your version: `cat VERSION`

---

Made with ❤️ by the Supercog team
