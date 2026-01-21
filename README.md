# Mattermost Docker for ARM - Enterprise Edition on Raspberry Pi and ARM Servers

> **⚠️ ARCHIVED REPOSITORY**  
> Building Mattermost Enterprise is not possible outside of Mattermost, Inc. See [Why Enterprise Cannot Be Built](#why-enterprise-cannot-be-built) for details.

[![Docker Pulls](https://badgen.net/docker/pulls/imbios/mattermost-app?icon=docker&label=pulls)](https://hub.docker.com/r/imbios/mattermost-app)
[![Docker Stars](https://badgen.net/docker/stars/imbios/mattermost-app?icon=docker&label=stars)](https://hub.docker.com/r/imbios/mattermost-app)
![Github stars](https://badgen.net/github/stars/ImBIOS/mattermost-enterprise-arm?icon=github&label=stars)
![Github forks](https://badgen.net/github/forks/ImBIOS/mattermost-enterprise-arm?icon=github&label=forks)
![Github issues](https://img.shields.io/github/issues/ImBIOS/mattermost-enterprise-arm)

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

## Why Enterprise Cannot Be Built

Building Mattermost Enterprise edition is **not possible** outside of Mattermost, Inc. for the following reasons:

### Enterprise Code is Closed-Source

The Mattermost Enterprise edition source code lives in a **private repository** (`mattermost/enterprise`) that requires:

1. **Valid Enterprise License** - Must be purchased through Mattermost, Inc.
2. **Private GitHub Access** - The enterprise repo is not publicly accessible
3. **Commercial Agreement** - Access is granted only to customers and partners

### Technical Details

From the server Makefile:
```makefile
BUILD_ENTERPRISE_DIR ?= ../../enterprise
```

The build process expects enterprise source code at `/path/to/enterprise`. Without it:
- The build falls back to **Team Edition** (open-source)
- Results in `mattermost-team-linux-*.tar.gz` (not enterprise)

### What This Means

- Docker images tagged as "enterprise" would actually run **Team Edition**
- True Enterprise ARM binaries can only be obtained through:
  - Mattermost's official builds, or
  - Enterprise customers with proper licensing

### Alternatives

For Enterprise features on ARM:
1. **Use Mattermost's official images** - They provide multi-architecture support
2. **Contact Mattermost Sales** - Request ARM64 Enterprise builds
3. **Use Team Edition** - Open-source with essential features for most teams

---

## Repository Maintenance

This project tracks upstream Mattermost releases. To update:

1. Modify `mattermost-release.txt` with the new version
2. Update `.github/workflows/release.yml` if Go version changes
3. Submit a pull request with release notes

Contributions welcome—open issues or PRs for bug fixes and improvements.

## Credits

Original repository for source code: <https://github.com/remiheens/mattermost-enterprise-arm>
