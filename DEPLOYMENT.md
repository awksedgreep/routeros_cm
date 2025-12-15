# Deployment Guide

This guide covers deploying RouterOS Cluster Manager to production.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Application Configuration](#application-configuration)
- [Database Setup](#database-setup)
- [Systemd Service](#systemd-service)
- [Reverse Proxy](#reverse-proxy)
- [SSL/TLS](#ssltls)
- [Backup and Recovery](#backup-and-recovery)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

- **OS:** Ubuntu 22.04 LTS / Debian 12 (recommended) or similar
- **RAM:** Minimum 1GB, recommended 2GB+
- **Disk:** 10GB+ available space
- **CPU:** 1 core minimum, 2+ recommended

### Software Requirements

```bash
# Install Elixir and Erlang
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install -y elixir erlang-dev erlang-parsetools

# Install Node.js (for asset compilation)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install build tools
sudo apt-get install -y build-essential git
```

## Environment Setup

### 1. Create Application User

```bash
sudo useradd -r -m -U -s /bin/bash routeros_cm
sudo su - routeros_cm
```

### 2. Clone and Setup Application

```bash
cd ~
git clone <repository-url> routeros_cm
cd routeros_cm

# Install dependencies
mix local.hex --force
mix local.rebar --force
mix deps.get --only prod

# Compile assets
npm install --prefix assets
npm run deploy --prefix assets
mix assets.deploy
```

### 3. Generate Secrets

```bash
# Generate secret key base
mix phx.gen.secret

# Generate encryption key
mix cloak.generate_key
```

## Application Configuration

### Environment Variables

Create `/home/routeros_cm/routeros_cm/.env`:

```bash
#!/bin/bash
# Application
export SECRET_KEY_BASE="<generated-secret-key-base>"
export PHX_HOST="your-domain.com"
export PORT=4000

# Database
export DATABASE_PATH="/home/routeros_cm/routeros_cm/priv/repo/routeros_cm_prod.db"

# Encryption
export CLOAK_KEY="<generated-cloak-key>"

# Environment
export MIX_ENV=prod
```

Make it executable:

```bash
chmod +x .env
```

### Production Configuration

The `config/runtime.exs` handles production configuration via environment variables. Ensure it includes:

```elixir
if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
    raise """
    environment variable DATABASE_PATH is missing.
    For example: /home/routeros_cm/routeros_cm/priv/repo/routeros_cm_prod.db
    """

  config :routeros_cm, RouterosCm.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :routeros_cm, RouterosCmWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  cloak_key =
    System.get_env("CLOAK_KEY") ||
    raise """
    environment variable CLOAK_KEY is missing.
    You can generate one by calling: mix cloak.generate_key
    """

  config :routeros_cm, RouterosCm.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1",
        key: Base.decode64!(cloak_key)
      }
    ]
end
```

## Database Setup

### Initialize Database

```bash
source .env
mix ecto.create
mix ecto.migrate
```

### Database Backups

Create backup script `/home/routeros_cm/backup_db.sh`:

```bash
#!/bin/bash
BACKUP_DIR="/home/routeros_cm/backups"
DB_PATH="/home/routeros_cm/routeros_cm/priv/repo/routeros_cm_prod.db"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR
sqlite3 $DB_PATH ".backup '$BACKUP_DIR/routeros_cm_$DATE.db'"

# Keep only last 30 days of backups
find $BACKUP_DIR -name "routeros_cm_*.db" -mtime +30 -delete
```

Make executable and add to crontab:

```bash
chmod +x /home/routeros_cm/backup_db.sh

# Add to crontab (daily at 2 AM)
crontab -e
# Add: 0 2 * * * /home/routeros_cm/backup_db.sh
```

## Systemd Service

### Create Service File

Create `/etc/systemd/system/routeros_cm.service`:

```ini
[Unit]
Description=RouterOS Cluster Manager
After=network.target

[Service]
Type=simple
User=routeros_cm
Group=routeros_cm
WorkingDirectory=/home/routeros_cm/routeros_cm
EnvironmentFile=/home/routeros_cm/routeros_cm/.env
ExecStart=/usr/bin/mix phx.server
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=routeros_cm

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/home/routeros_cm/routeros_cm/priv

[Install]
WantedBy=multi-user.target
```

### Enable and Start Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable routeros_cm
sudo systemctl start routeros_cm
sudo systemctl status routeros_cm
```

### Service Management

```bash
# View logs
sudo journalctl -u routeros_cm -f

# Restart service
sudo systemctl restart routeros_cm

# Stop service
sudo systemctl stop routeros_cm
```

## Reverse Proxy

### Nginx Configuration

Install Nginx:

```bash
sudo apt-get install -y nginx
```

Create `/etc/nginx/sites-available/routeros_cm`:

```nginx
upstream routeros_cm {
    server 127.0.0.1:4000;
}

server {
    listen 80;
    server_name your-domain.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    # SSL certificates (configured with certbot)
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Logging
    access_log /var/log/nginx/routeros_cm_access.log;
    error_log /var/log/nginx/routeros_cm_error.log;

    # Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://routeros_cm;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_read_timeout 86400;
    }

    # Static assets
    location ~* ^.+\.(css|js|jpg|jpeg|gif|png|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://routeros_cm;
        proxy_cache_valid 200 30d;
        add_header Cache-Control "public, immutable";
    }
}
```

Enable site:

```bash
sudo ln -s /etc/nginx/sites-available/routeros_cm /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## SSL/TLS

### Let's Encrypt with Certbot

Install Certbot:

```bash
sudo apt-get install -y certbot python3-certbot-nginx
```

Obtain certificate:

```bash
sudo certbot --nginx -d your-domain.com
```

Auto-renewal is configured automatically. Test renewal:

```bash
sudo certbot renew --dry-run
```

## Backup and Recovery

### Full Backup Script

Create `/home/routeros_cm/full_backup.sh`:

```bash
#!/bin/bash
BACKUP_DIR="/home/routeros_cm/backups/full"
APP_DIR="/home/routeros_cm/routeros_cm"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="routeros_cm_full_$DATE"

mkdir -p $BACKUP_DIR/$BACKUP_NAME

# Backup database
sqlite3 $APP_DIR/priv/repo/routeros_cm_prod.db ".backup '$BACKUP_DIR/$BACKUP_NAME/database.db'"

# Backup environment
cp $APP_DIR/.env $BACKUP_DIR/$BACKUP_NAME/

# Create archive
cd $BACKUP_DIR
tar -czf $BACKUP_NAME.tar.gz $BACKUP_NAME
rm -rf $BACKUP_NAME

# Keep only last 7 days
find $BACKUP_DIR -name "routeros_cm_full_*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_NAME.tar.gz"
```

### Recovery Process

```bash
# Stop service
sudo systemctl stop routeros_cm

# Extract backup
cd /home/routeros_cm/backups/full
tar -xzf routeros_cm_full_YYYYMMDD_HHMMSS.tar.gz

# Restore database
cp routeros_cm_full_YYYYMMDD_HHMMSS/database.db \
   /home/routeros_cm/routeros_cm/priv/repo/routeros_cm_prod.db

# Restore environment (if needed)
cp routeros_cm_full_YYYYMMDD_HHMMSS/.env \
   /home/routeros_cm/routeros_cm/.env

# Start service
sudo systemctl start routeros_cm
```

## Monitoring

### Health Check Endpoint

Add to your monitoring system:

```bash
# HTTP health check
curl -f http://localhost:4000/ || exit 1
```

### Log Monitoring

View application logs:

```bash
# Real-time logs
sudo journalctl -u routeros_cm -f

# Last 100 lines
sudo journalctl -u routeros_cm -n 100

# Filter by priority
sudo journalctl -u routeros_cm -p err
```

### Disk Space

Monitor database growth:

```bash
# Check database size
du -h /home/routeros_cm/routeros_cm/priv/repo/routeros_cm_prod.db
```

## Troubleshooting

### Service Won't Start

1. Check environment variables:
   ```bash
   source /home/routeros_cm/routeros_cm/.env
   echo $SECRET_KEY_BASE
   ```

2. Check permissions:
   ```bash
   ls -la /home/routeros_cm/routeros_cm/priv/repo/
   ```

3. Check logs:
   ```bash
   sudo journalctl -u routeros_cm -n 50
   ```

### Database Locked

```bash
# Stop service
sudo systemctl stop routeros_cm

# Check for stale processes
ps aux | grep beam

# Kill if necessary
sudo pkill -9 beam

# Start service
sudo systemctl start routeros_cm
```

### High Memory Usage

```bash
# Check memory usage
ps aux | grep beam

# Restart service
sudo systemctl restart routeros_cm
```

### Connection Issues to RouterOS

1. Test from server:
   ```bash
   telnet <routeros-ip> 8728
   ```

2. Check firewall rules on RouterOS
3. Verify API service is enabled
4. Check credentials in application

## Updates and Maintenance

### Updating Application

```bash
# As routeros_cm user
cd /home/routeros_cm/routeros_cm
git pull origin main

# Update dependencies
MIX_ENV=prod mix deps.get

# Recompile assets
npm install --prefix assets
npm run deploy --prefix assets
MIX_ENV=prod mix assets.deploy

# Run migrations
MIX_ENV=prod mix ecto.migrate

# Restart service
sudo systemctl restart routeros_cm
```

### Zero-Downtime Deployment

For critical systems, consider:
1. Setting up a second instance
2. Using a load balancer
3. Switching traffic after validation

## Security Recommendations

1. **Firewall:** Only expose port 443 (HTTPS)
   ```bash
   sudo ufw allow 443/tcp
   sudo ufw enable
   ```

2. **Regular Updates:**
   ```bash
   sudo apt-get update && sudo apt-get upgrade
   ```

3. **Strong Passwords:** Use complex passwords for user accounts
4. **Regular Backups:** Automate daily backups
5. **Monitor Logs:** Set up log alerts for suspicious activity
6. **API Keys:** Rotate RouterOS API credentials periodically

## Performance Tuning

### Database Optimization

```bash
# Vacuum database regularly
sqlite3 /path/to/database.db "VACUUM;"
```

### Phoenix Configuration

In `config/runtime.exs` for production:

```elixir
config :routeros_cm, RouterosCmWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true
```

## Support

For deployment issues:
1. Check application logs
2. Review Nginx logs
3. Verify environment variables
4. Test database connectivity
5. Confirm network access to RouterOS devices
