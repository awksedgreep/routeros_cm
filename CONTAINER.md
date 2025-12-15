# Container Guide

This guide covers building, running, and publishing the RouterOS Cluster Manager container image.

## Prerequisites

- **Podman** (or Docker) installed and running
- **Elixir 1.15+** for running mix tasks
- **GitHub account** with Personal Access Token (for publishing to ghcr.io)

## Quick Start

```bash
# Build and run locally
mix container.build
mix container.run

# Access the application
open http://localhost:6555
```

## Mix Tasks Reference

| Task | Description |
|------|-------------|
| `mix container.build` | Build the container image locally |
| `mix container.run` | Run the container locally |
| `mix container.stop` | Stop and remove the container |
| `mix container.logs` | View container logs |
| `mix container.login` | Login to GitHub Container Registry |
| `mix container.publish` | Publish image to ghcr.io |

## Building the Image

### Basic Build

```bash
mix container.build
```

### Build with Version Tag

```bash
mix container.build --tag v1.0.0
```

### Build without Cache

Useful when dependencies have changed:

```bash
mix container.build --no-cache
```

### Build Options

| Option | Alias | Description |
|--------|-------|-------------|
| `--tag` | `-t` | Image tag (default: `latest`) |
| `--no-cache` | | Build without using cache |

## Running Locally

### Basic Run

Starts the container on port 6555:

```bash
mix container.run
```

### Custom Port

```bash
mix container.run --port 8080
```

### Run Specific Version

```bash
mix container.run --tag v1.0.0
```

### Run Options

| Option | Alias | Description |
|--------|-------|-------------|
| `--tag` | `-t` | Image tag to run (default: `latest`) |
| `--port` | `-p` | Host port (default: `6555`) |
| `--name` | `-n` | Container name (default: `routeros_cm`) |
| `--env-file` | | Path to env file (default: `.env.docker`) |

## Managing the Container

### View Logs

```bash
# Last 100 lines
mix container.logs

# Follow logs in real-time
mix container.logs --follow

# Show last 50 lines
mix container.logs --tail 50
```

### Stop Container

```bash
# Stop and remove
mix container.stop

# Stop but keep container
mix container.stop --keep
```

### Restart Container

```bash
mix container.stop
mix container.run
```

## Publishing to GitHub Container Registry

### 1. Create GitHub Personal Access Token

1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Generate new token (classic) with `write:packages` scope
3. Copy the token

### 2. Set Environment Variables

```bash
export GITHUB_USERNAME=your-github-username
export GITHUB_TOKEN=ghp_your_token_here
```

### 3. Login to Registry

```bash
mix container.login
```

### 4. Publish Image

```bash
# Publish existing image
mix container.publish

# Build and publish in one step
mix container.publish --build

# Publish with specific tag
mix container.publish --tag v1.0.0

# Publish to different namespace (org)
mix container.publish --namespace my-org --tag latest
```

### Publish Options

| Option | Alias | Description |
|--------|-------|-------------|
| `--tag` | `-t` | Image tag (default: `latest`) |
| `--build` | `-b` | Build before publishing |
| `--namespace` | `-n` | GitHub namespace/username |

## Configuration

### Application Config

In `config/config.exs`:

```elixir
config :routeros_cm, :container,
  registry: "ghcr.io",
  namespace: "your-github-username",
  image_name: "routeros_cm"
```

### Environment Variables

Create `.env.docker` for local development:

```bash
# Required
SECRET_KEY_BASE=your-secret-key-base-here
CREDENTIAL_KEY=your-32-byte-base64-key

# Optional
URL_SCHEME=http
URL_PORT=6555          # External port for generated URLs (email links, etc.)
PHX_HOST=localhost
PORT=4000              # Internal port the app listens on
DATABASE_PATH=/app/data/routeros_cm.db

# Mail provider (see Mail Configuration below)
MAIL_PROVIDER=local
```

**Note:** When running in a container with port mapping (e.g., `-p 6555:4000`), set `URL_PORT` to the external port (6555) so that generated URLs in emails work correctly.

#### Generating Secrets

```bash
# Generate SECRET_KEY_BASE
mix phx.gen.secret

# Generate CREDENTIAL_KEY (32 bytes, base64 encoded)
openssl rand -base64 32
```

## Mail Configuration

The container supports multiple mail providers configured via the `MAIL_PROVIDER` environment variable.

### Local Mailbox (Development)

Enables the `/dev/mailbox` web interface to view sent emails:

```bash
MAIL_PROVIDER=local
```

Access the mailbox at: http://localhost:6555/dev/mailbox

This is the recommended setting for local development and testing.

### Logger (Console Output)

Logs all emails to stdout/container logs:

```bash
MAIL_PROVIDER=logger
```

View emails with:
```bash
mix container.logs --follow
```

### SMTP Relay (Production)

Configure an external SMTP server:

```bash
MAIL_PROVIDER=smtp
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=your-username
SMTP_PASSWORD=your-password
SMTP_SSL=false
```

### Default (No Mail)

If `MAIL_PROVIDER` is not set, emails use the default Swoosh adapter but won't be delivered anywhere. Users won't receive confirmation emails.

## Development Tools

When running the container locally with `MAIL_PROVIDER=local`, these endpoints are available:

| Endpoint | Description |
|----------|-------------|
| `/dev/mailbox` | View sent emails (login tokens, confirmations) |
| `/dev/dashboard` | Phoenix LiveDashboard (metrics, processes) |

## Data Persistence

The SQLite database is stored in a named volume:

- **Volume name:** `routeros_cm_data`
- **Container path:** `/app/data/routeros_cm.db`

### Backup Database

```bash
# Copy database from volume
podman cp routeros_cm:/app/data/routeros_cm.db ./backup.db
```

### Restore Database

```bash
# Stop container first
mix container.stop

# Copy database to volume
podman volume create routeros_cm_data
podman run --rm -v routeros_cm_data:/data -v $(pwd):/backup alpine \
  cp /backup/backup.db /data/routeros_cm.db

# Start container
mix container.run
```

### Reset Database

```bash
mix container.stop
podman volume rm routeros_cm_data
mix container.run
```

## Direct Podman Commands

If you prefer using Podman directly:

### Build

```bash
podman build -t routeros_cm:latest .
```

### Run

```bash
podman run -d \
  --name routeros_cm \
  -p 6555:4000 \
  -v routeros_cm_data:/app/data \
  --env-file .env.docker \
  -e PHX_SERVER=true \
  -e PORT=4000 \
  -e PHX_HOST=localhost \
  -e DATABASE_PATH=/app/data/routeros_cm.db \
  routeros_cm:latest
```

### Publish

```bash
# Login
echo $GITHUB_TOKEN | podman login ghcr.io -u $GITHUB_USERNAME --password-stdin

# Tag and push
podman tag routeros_cm:latest ghcr.io/$GITHUB_USERNAME/routeros_cm:latest
podman push ghcr.io/$GITHUB_USERNAME/routeros_cm:latest
```

## Pulling from ghcr.io

Once published, others can pull and run your image:

```bash
# Pull image
podman pull ghcr.io/your-username/routeros_cm:latest

# Run
podman run -d \
  --name routeros_cm \
  -p 6555:4000 \
  -v routeros_cm_data:/app/data \
  -e SECRET_KEY_BASE=$(openssl rand -base64 48) \
  -e CREDENTIAL_KEY=$(openssl rand -base64 32) \
  -e PHX_SERVER=true \
  -e DATABASE_PATH=/app/data/routeros_cm.db \
  ghcr.io/your-username/routeros_cm:latest
```

## Docker Compose / Podman Compose

A `docker-compose.yml` is included for convenience:

```bash
# Start
podman-compose up -d

# Stop
podman-compose down

# Rebuild and start
podman-compose up -d --build
```

## Production Deployment

For production deployments:

1. **Generate new secrets** - Don't reuse development keys
2. **Use a reverse proxy** - nginx, Caddy, or Traefik for SSL termination
3. **Set `PHX_HOST`** - Your actual domain name
4. **Set `URL_SCHEME=https`** - When behind SSL proxy
5. **Backup regularly** - Schedule database backups

### Example Production Run

```bash
podman run -d \
  --name routeros_cm \
  --restart unless-stopped \
  -p 127.0.0.1:4000:4000 \
  -v routeros_cm_data:/app/data \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e CREDENTIAL_KEY="$(openssl rand -base64 32)" \
  -e PHX_SERVER=true \
  -e PHX_HOST=routeros.example.com \
  -e URL_SCHEME=https \
  -e DATABASE_PATH=/app/data/routeros_cm.db \
  ghcr.io/your-username/routeros_cm:latest
```

## Troubleshooting

### Container Won't Start

Check logs for errors:

```bash
podman logs routeros_cm
```

### Database Locked

```bash
mix container.stop
mix container.run
```

### Port Already in Use

```bash
# Use a different port
mix container.run --port 8080
```

### Permission Denied

The container runs as non-root user `nobody`. Ensure volume permissions are correct:

```bash
podman volume rm routeros_cm_data
mix container.run
```

### Build Failures

Try building without cache:

```bash
mix container.build --no-cache
```

### Can't Connect to RouterOS Devices

Ensure the container can reach your RouterOS devices on the network. For host network access:

```bash
podman run -d \
  --name routeros_cm \
  --network host \
  -v routeros_cm_data:/app/data \
  --env-file .env.docker \
  routeros_cm:latest
```

Note: With `--network host`, the app listens on port 4000 directly.
