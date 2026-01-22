# Mattermost ARM64 Docker - Enterprise Edition for Raspberry Pi and ARM Servers

Deploy a production-ready Mattermost messaging platform on ARM architecture. This repository provides Docker-based deployment with automated CI/CD builds and releases for ARM64 and ARMv7 devices.

[![Docker Pulls](https://badgen.net/docker/pulls/imbios/mattermost-app?icon=docker&label=pulls)](https://hub.docker.com/r/imbios/mattermost-app)
[![Docker Stars](https://badgen.net/docker/stars/imbios/mattermost-app?icon=docker&label=stars)](https://hub.docker.com/r/imbios/mattermost-app)
![Github stars](https://badgen.net/github/stars/ImBIOS/mattermost-enterprise-arm?icon=github&label=stars)
![Github forks](https://badgen.net/github/forks/ImBIOS/mattermost-enterprise-arm?icon=github&label=forks)

## What This Repository Provides

This repository enables building and running Mattermost on ARM devices including:

- **Raspberry Pi 4/5** (ARM64/aarch64)
- **Raspberry Pi 3B+** (ARMv7/armhf)
- **ARM64 servers** (AWS Graviton, Ampere Altra, etc.)
- **Any Linux ARM device** running Docker

## Understanding Mattermost Editions

Before building, understand what you're deploying:

| Edition | Source Code | Features | License Required | Production Use |
|---------|-------------|----------|------------------|----------------|
| **Team Edition** | Public (MIT/AGPL) | Core messaging only | None | Free |
| **Source-Available** | Public repo (`server/enterprise/`) | Some enterprise features | Source Available License (free for dev/test) | Limited |
| **Enterprise Edition** | Private repo + public | All enterprise features | Paid Enterprise License | Full features |

### Source-Available Mode

This repository builds **source-available edition** by default, which includes:

- Some enterprise features from the public `mattermost/server` repository
- Enterprise code gated behind `sourceavailable` build tag
- Free to use for development and testing
- Suitable for small teams with basic enterprise needs

### True Enterprise Edition

For full enterprise features, you need:

- Access to Mattermost's private enterprise repository
- A paid Enterprise license from Mattermost, Inc.
- Production usage rights under commercial agreement

## Quick Start

### 1. Configure Deployment

```bash
cp docker-compose.yml.local docker-compose.yml
```

Edit `run.env` to customize database credentials, Mattermost instance name, and SMTP settings.

### 2. Launch the Stack

```bash
docker-compose up -d
```

### 3. Access Your Instance

Open <http://localhost:8000> and complete the initial setup.

## Building from Source

### Prerequisites

- Docker and Docker Buildx
- Git
- ~20GB free disk space for build

### Build Commands

```bash
# Configure build parameters
export MATTERMOST_VERSION=v11.3.0
export GO_VERSION=1.24.6
export MM_EDITION=sourceavailable  # or 'enterprise' for full features

# Build binaries
./build.sh

# Build Docker images
docker buildx build --platform linux/arm64 --load -t your-registry/mattermost-app:v11.3.0 ./app
```

### Building for Different Architectures

```bash
# ARM64 (Raspberry Pi 4/5, AWS Graviton)
export GOOS=linux GOARCH=arm64

# ARMv7 (Raspberry Pi 3B+)
export GOOS=linux GOARCH=arm

# AMD64 (x86_64, for testing)
export GOOS=linux GOARCH=amd64
```

## Deployment Options

### Docker Compose (Recommended)

```bash
# Build and start all services
docker-compose build
docker-compose up -d

# View logs
docker-compose logs -f app

# Stop services
docker-compose down
```

### Standalone Docker

```bash
# Build ARM64 image
docker buildx build --platform linux/arm64 --load -t mattermost-app:latest ./app

# Run with external database
docker run -d \
  --name mattermost \
  -p 8000:8000 \
  -v ./config:/mattermost/config \
  -v ./data:/mattermost/data \
  -v ./logs:/mattermost/logs \
  -v ./plugins:/mattermost/plugins \
  -e MM_DBHOST=your-db-host \
  mattermost-app:latest
```

## Features

- **ARM Architecture Support**: Native builds for ARM64 and ARMv7
- **Docker Compose Orchestration**: Full stack deployment with PostgreSQL
- **Automated CI/CD**: GitHub Actions for consistent builds
- **Volume Management**: Persistent storage for data, plugins, logs, config
- **WAL-E Backup Support**: Database backup integration

## Supported Hardware

| Device | Architecture | Status |
|--------|--------------|--------|
| Raspberry Pi 4/5 | ARM64 (aarch64) | Tested |
| Raspberry Pi 3B+ | ARMv7 (armhf) | Tested |
| Raspberry Pi 5 | ARM64 | Tested |
| AWS Graviton | ARM64 | Tested |
| Ampere Altra | ARM64 | Compatible |
| Odroid N2+ | ARM64 | Compatible |
| Rock Pi 4 | ARM64 | Compatible |

## Requirements

- Docker 20.10+ with Buildx
- Docker Compose 2.0+
- 2GB RAM minimum (4GB recommended)
- 10GB disk space minimum

## Configuration

### Environment Variables

Edit `run.env` to configure:

```env
# Database
POSTGRES_USER=mmuser
POSTGRES_PASSWORD=your_secure_password
POSTGRES_DB=mattermost

# Mattermost
DOMAIN=localhost
SITE_URL=http://localhost:8000
```

### Volume Mounts

| Mount Point | Purpose |
|-------------|---------|
| `/mattermost/config` | Configuration files |
| `/mattermost/data` | User files, attachments |
| `/mattermost/logs` | Application logs |
| `/mattermost/plugins` | Plugin files |

## Troubleshooting

### Build Fails with Memory Error

Increase Docker memory allocation to 4GB+ in Docker Desktop settings.

### QEMU Not Available

Install QEMU for cross-platform builds:

```bash
docker run --privileged --rm tonistiigi/binfmt --install arm64,arm
```

### Enterprise Features Not Visible

Without an enterprise license, the system runs in "free mode". To unlock features:

1. Purchase an Enterprise license from Mattermost
2. Upload license file in System Console > About
3. Features unlock immediately

### Database Connection Failed

Verify PostgreSQL is running and credentials in `run.env` are correct:

```bash
docker-compose ps
docker-compose logs db
```

## Upgrading

1. Update version in `mattermost-release.txt`
2. Pull latest code: `git pull origin main`
3. Rebuild: `docker-compose build app`
4. Restart: `docker-compose up -d`

## CI/CD Pipeline

This repository uses GitHub Actions for automated builds:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `release.yml` | Push to `main` or `support-*` | Build binaries for all platforms |
| `docker.yml` | Tag push (`v*`) | Build and publish Docker images |

### Automated Builds

1. Push to `main` branch triggers binary builds for ARM64 and ARMv7
2. Creating a version tag (e.g., `v11.3.0`) triggers Docker image builds
3. Docker images published to Docker Hub automatically

## Contributing

Contributions welcome:

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

- This build system: MIT License
- Mattermost Team Edition: MIT License
- Mattermost Enterprise: Commercial license required

See [Mattermost Licensing](https://docs.mattermost.com/about/licensing.html) for details.

## Credits

- Original project: [mattermost-enterprise-arm](https://github.com/remiheens/mattermost-enterprise-arm)
- Mattermost, Inc. for the collaboration platform
- Community contributors

## Support

- GitHub Issues: Report bugs and feature requests
- Docker Hub: [imbios/mattermost-app](https://hub.docker.com/r/imbios/mattermost-app)
