# Mattermost Docker for ARM - Enterprise Edition on Raspberry Pi and ARM Servers

[![Docker Pulls](https://badgen.net/docker/pulls/imbios/mattermost-app?icon=docker&label=pulls)](https://hub.docker.com/r/imbios/mattermost-app)
[![Docker Stars](https://badgen.net/docker/stars/imbios/mattermost-app?icon=docker&label=stars)](https://hub.docker.com/r/imbios/mattermost-app)
![Github stars](https://badgen.net/github/stars/ImBIOS/mattermost-docker-arm?icon=github&label=stars)
![Github forks](https://badgen.net/github/forks/ImBIOS/mattermost-docker-arm?icon=github&label=forks)
![Github issues](https://img.shields.io/github/issues/ImBIOS/mattermost-docker-arm)

Deploy a production-ready Mattermost messaging platform on ARM architecture devices including Raspberry Pi 4/5, ARM servers, and other ARM64/ARMv7 hardware. This repository provides Docker-based deployment with automated CI/CD builds and releases.

## Features

- **ARM Architecture Support**: Optimized builds for ARM64 (aarch64) and ARMv7 (armhf) architectures
- **Docker Compose Orchestration**: Full stack deployment with PostgreSQL database
- **Automated Builds**: GitHub Actions CI/CD pipeline for consistent, reproducible builds
- **Enterprise Ready**: Production configuration with WAL-E backup support
- **Volume Management**: Persistent storage for data, plugins, logs, and configuration

## Supported Hardware

- Raspberry Pi 4/5 (ARM64)
- Raspberry Pi 3B+ (ARMv7)
- ARM64 servers (AWS Graviton, Ampere Altra, etc.)
- Any Linux ARM device running Docker

## Quick Start

1. **Configure the deployment:**

   ```bash
   cp docker-compose.yml.local docker-compose.yml
   ```

   Edit `run.env` to customize database credentials, Mattermost instance name, and optional SMTP settings.

2. **Launch the stack:**

   ```bash
   docker-compose up -d
   ```

3. **Access your instance:**

   Open <http://localhost:8000> and complete the initial setup.

## Building from Source

For custom builds or development:

```bash
# Configure build parameters
export MATTERMOST_VERSION=v11.3.0
export GO_VERSION=1.24.6

# Build binaries
./build.sh

# Build Docker images
docker build -t your-registry/mattermost-app:v11.3.0 ./app
```

## Repository Maintenance

This project tracks upstream Mattermost releases. To update:

1. Modify `mattermost-release.txt` with the new version
2. Update `.github/workflows/release.yml` if Go version changes
3. Submit a pull request with release notes

Contributions welcome—open issues or PRs for bug fixes and improvements.

## Credits

Original repository for source code: <https://github.com/remiheens/mattermost-docker-arm>
