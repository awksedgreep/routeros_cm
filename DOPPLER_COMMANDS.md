# Doppler Quick Setup Commands

Copy and paste these commands to quickly set up Doppler for RouterOS CM.

## 1. Initial Setup

```bash
# Install Doppler CLI (macOS)
brew install doppler

# Login to Doppler
doppler login

# Create project and environment
doppler projects create routeros-cm
doppler environments create production --project routeros-cm
doppler setup --project routeros-cm --config production --no-interactive
```

## 2. Set All Required Secrets (One Command Block)

```bash
# Core Application Secrets - Copy and paste this entire block
doppler secrets set \
  SECRET_KEY_BASE "$(openssl rand -base64 48)" \
  DATABASE_PATH "/app/routeros_cm.db" \
  CREDENTIAL_KEY "$(openssl rand -base64 32)" \
  PHX_HOST "yourdomain.com" \
  PORT "4000" \
  URL_PORT "443" \
  URL_SCHEME "https" \
  PHX_SERVER "true"
```

## 3. Optional Configuration (Copy blocks as needed)

### Database & Performance
```bash
doppler secrets set POOL_SIZE "5"
```

### Container Registry
```bash
doppler secrets set \
  CONTAINER_REGISTRY "ghcr.io" \
  CONTAINER_NAMESPACE "your-github-username" \
  CONTAINER_IMAGE_NAME "routeros_cm"
```

### SMTP Email
```bash
doppler secrets set \
  SMTP_HOST "smtp.gmail.com" \
  SMTP_PORT "587" \
  SMTP_USERNAME "your-email@gmail.com" \
  SMTP_PASSWORD "your-app-password" \
  SMTP_SSL "false"
```

### Feature Flags
```bash
doppler secrets set \
  ENABLE_REGISTRATION "false" \
  ENABLE_PASSWORD_RESET "true" \
  ENABLE_EMAIL_VERIFICATION "true"
```

### Rate Limiting
```bash
doppler secrets set \
  RATE_LIMIT_LOGIN_ATTEMPTS "5" \
  RATE_LIMIT_API_REQUESTS "100"
```

### Monitoring
```bash
doppler secrets set LOG_LEVEL "info"
# Optional: doppler secrets set SENTRY_DSN "https://your-sentry-dsn@sentry.io/project"
```

## 4. Test Your Setup

```bash
# View all secrets
doppler secrets

# Test locally
doppler run -- mix phx.server

# Build release
doppler run -- mix release
```

## 5. Production Deployment

```bash
# Create service token
doppler configs tokens create production --project routeros-cm --name "prod-server"

# Use the token in your deployment (replace xxxxx with actual token)
export DOPPLER_TOKEN="dp.st.production.xxxxxxxxxxxxx"
```

## Environment-Specific Quick Setup

### Development Environment
```bash
doppler environments create dev --project routeros-cm
doppler setup --project routeros-cm --config dev --no-interactive
doppler secrets set \
  PHX_HOST "localhost" \
  URL_SCHEME "http" \
  URL_PORT "4000" \
  ENABLE_REGISTRATION "true" \
  LOG_LEVEL "debug"
```

### Staging Environment
```bash
doppler environments create staging --project routeros-cm
doppler setup --project routeros-cm --config staging --no-interactive
doppler secrets set \
  PHX_HOST "staging.yourdomain.com" \
  DATABASE_PATH "/app/staging_routeros_cm.db"
```

## Quick Commands Reference

```bash
# Switch environments
doppler setup --project routeros-cm --config staging

# Update secrets
doppler secrets set KEY_NAME "new_value"

# Bulk update from file
doppler secrets upload secrets.json

# Download secrets
doppler secrets download --format env > .env

# Delete secret
doppler secrets delete KEY_NAME

# View audit logs
doppler activity
```

## One-Line Complete Setup

For the impatient - this sets up everything with sensible defaults:

```bash
doppler login && \
doppler projects create routeros-cm && \
doppler environments create production --project routeros-cm && \
doppler setup --project routeros-cm --config production --no-interactive && \
doppler secrets set \
  SECRET_KEY_BASE "$(openssl rand -base64 48)" \
  DATABASE_PATH "/app/routeros_cm.db" \
  CREDENTIAL_KEY "$(openssl rand -base64 32)" \
  PHX_HOST "localhost" \
  PORT "4000" \
  URL_PORT "4000" \
  URL_SCHEME "http" \
  PHX_SERVER "true" \
  POOL_SIZE "5" \
  ENABLE_REGISTRATION "false" \
  ENABLE_PASSWORD_RESET "true" \
  ENABLE_EMAIL_VERIFICATION "true" \
  RATE_LIMIT_LOGIN_ATTEMPTS "5" \
  RATE_LIMIT_API_REQUESTS "100" \
  LOG_LEVEL "info" && \
echo "✅ Doppler setup complete! Run: doppler run -- mix phx.server"
```

## Verification

After setup, verify everything works:

```bash
# Check configuration
doppler secrets

# Test app startup
doppler run -- mix deps.get
doppler run -- mix compile
doppler run -- mix test
doppler run -- mix phx.server
```

Your RouterOS CM is now configured with Doppler! 🚀