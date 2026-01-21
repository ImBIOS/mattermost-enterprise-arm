# Mattermost Telemetry Server

Lightweight telemetry collection server for Mattermost Docker deployments with Grafana visualization.

## Features

- Rust-based server with Actix-web for high performance
- SQLite database (no external dependencies)
- Grafana dashboards for visualization
- ARM64 support for Raspberry Pi and similar devices
- Auto-provisioned dashboards and data sources
- Single binary, zero config needed

## Quick Start

### Local Development

```bash
cd telemetry-server
docker-compose up -d
```

- Telemetry Server: <http://localhost:8080>
- Grafana: <http://localhost:3000> (admin/admin)

### Coolify Deployment

1. **Create a new service in Coolify** (Choose "Docker Compose" type)
2. **Copy the content of `docker-compose.coolify.yml`** to the Docker Compose configuration
3. **Configure environment variables** (optional):
   - `GRAFANA_USER` - Grafana admin user (default: admin)
   - `GRAFANA_PASSWORD` - Grafana admin password (default: admin)
4. **Deploy** - Coolify will build the ARM64 image and deploy

## Architecture

```txt
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Mattermost     │────▶│  Telemetry       │────▶│   SQLite DB     │
│  Containers     │     │  Server (Rust)   │     │   (file-based)  │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │   Grafana 12     │
                       │   Dashboards     │
                       └──────────────────┘
```

## Why SQLite?

| Aspect | PostgreSQL | SQLite |
|--------|-----------|--------|
| Startup time | ~2-5s | Instant |
| Resource usage | ~50MB+ RAM | ~5MB RAM |
| Setup complexity | Requires running service | Zero config |
| Backup | pg_dump | File copy |
| Perfect for | High concurrent writes | Your use case |

For a single telemetry server with light write load, SQLite is ideal. The file-based nature makes backups trivial - just copy the `.db` file.

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/collect` | POST | Receive telemetry events |
| `/metrics` | GET | Get aggregated metrics |
| `/health` | GET | Health check |
| `/deployments` | GET | Recent deployments |
| `/stats/architecture` | GET | Architecture breakdown |

## Telemetry Event Format

```json
POST /collect
{
  "instance_id": "unique-instance-id",
  "image_version": "v11.0.0",
  "architecture": "aarch64",
  "os": "Linux",
  "container_runtime": "docker",
  "startup_time_ms": 2500,
  "db_type": "postgres",
  "telemetry_version": "1.0"
}
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_ADDRESS` | `0.0.0.0:8080` | Server listen address |
| `DATABASE_URL` | `sqlite:///data/telemetry.db` | Database path |

## Build and Push

### Multi-platform build for ARM64

```bash
# Build for ARM64
docker buildx build --platform linux/arm64 -t imbios/mattermost-telemetry:latest .

# Push to Docker Hub
docker push imbios/mattermost-telemetry:latest
```

### Build directly on ARM64 server

```bash
cd telemetry-server
docker build -t imbios/mattermost-telemetry:latest .
docker push imbios/mattermost-telemetry:latest
```

## Mattermost Docker Integration

Update your Mattermost container to send telemetry:

```bash
docker run -e TELEMETRY_ENDPOINT=https://your-telemetry-server.com/collect \
  imbios/mattermost-app:latest
```

## Image Size

- **Base image**: Alpine 3.22 (~5 MB base)
- **Runtime size**: ~12 MB (including Rust binary)
- **Total**: ~15 MB (compressed ~6 MB)

## License

MIT
