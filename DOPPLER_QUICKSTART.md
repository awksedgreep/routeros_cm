# Doppler Quick Start Guide

This guide will help you set up Doppler for RouterOS CM in minutes.

## Prerequisites

1. **Install Doppler CLI**
   ```bash
   # macOS
   brew install doppler
   
   # Linux
   curl -Ls https://cli.doppler.com/install.sh | sh
   
   # Windows
   scoop install doppler
   ```

2. **Login to Doppler**
   ```bash
   doppler login
   ```

## Step 1: Create Project and Environment

```bash
# Create the project
doppler projects create routeros-cm

# Create environments
doppler environments create dev --project routeros-cm
doppler environments create staging --project routeros-cm  
doppler environments create production --project routeros-cm

# Setup local config (choose your environment)
doppler setup --project routeros-cm --config production
```

## Step 2: Set Required Secrets

Run these commands to set all the required configuration:

```bash
# Core Application Secrets (REQUIRED)
doppler secrets set SECRET_KEY_BASE "$(openssl rand -base64 48)"
doppler secrets set DATABASE_PATH "/app/routeros_cm.db"
doppler secrets set CREDENTIAL_KEY "$(openssl rand -base64 32)"
doppler secrets set PHX_HOST "your-domain.com"
doppler secrets set PORT "4000"
doppler secrets set URL_PORT "4000"
doppler secrets set URL_SCHEME "https"
doppler secrets set PHX_SERVER "true"
```

## Step 3: Set Optional Secrets

### Database Configuration
```bash
doppler secrets set POOL_SIZE "5"
```

### Container Registry
```bash
doppler secrets set CONTAINER_REGISTRY "ghcr.io"
doppler secrets set CONTAINER_NAMESPACE "your-github-username"
doppler secrets set CONTAINER_IMAGE_NAME "routeros_cm"
```

### SMTP Email Configuration
```bash
doppler secrets set SMTP_HOST "smtp.gmail.com"
doppler secrets set SMTP_PORT "587"
doppler secrets set SMTP_USERNAME "your-email@gmail.com"
doppler secrets set SMTP_PASSWORD "your-app-password"
doppler secrets set SMTP_SSL "false"
```

### Feature Flags
```bash
doppler secrets set ENABLE_REGISTRATION "false"
doppler secrets set ENABLE_PASSWORD_RESET "true"
doppler secrets set ENABLE_EMAIL_VERIFICATION "true"
```

### Rate Limiting
```bash
doppler secrets set RATE_LIMIT_LOGIN_ATTEMPTS "5"
doppler secrets set RATE_LIMIT_API_REQUESTS "100"
```

### Monitoring & Logging
```bash
doppler secrets set LOG_LEVEL "info"
# Optional: Set SENTRY_DSN if you use Sentry
# doppler secrets set SENTRY_DSN "https://your-sentry-dsn@sentry.io/project-id"
```

## Step 4: Test Your Setup

### View All Secrets
```bash
doppler secrets
```

### Test Local Development
```bash
# Run Phoenix server with Doppler
doppler run -- mix phx.server

# Run tests with Doppler
doppler run -- mix test

# Build release with Doppler
doppler run -- mix release
```

## Step 5: Production Deployment

### Create Service Token
```bash
# Create a service token for production
doppler configs tokens create production --project routeros-cm --name "production-server"
```

Copy the generated token (starts with `dp.st.production.`).

### Set in Your Deployment

#### Docker/Container
```dockerfile
ENV DOPPLER_TOKEN=dp.st.production.xxxxxxxxxxxxx
```

#### Kubernetes
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: doppler-token
type: Opaque
data:
  token: <base64-encoded-service-token>
---
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: routeros-cm
        env:
        - name: DOPPLER_TOKEN
          valueFrom:
            secretKeyRef:
              name: doppler-token
              key: token
```

#### Environment Variable
```bash
export DOPPLER_TOKEN="dp.st.production.xxxxxxxxxxxxx"
./bin/routeros_cm start
```

## Example Values for Different Environments

### Development Environment
```bash
doppler setup --project routeros-cm --config dev
doppler secrets set PHX_HOST "localhost"
doppler secrets set URL_SCHEME "http"
doppler secrets set URL_PORT "4000"
doppler secrets set ENABLE_REGISTRATION "true"
doppler secrets set LOG_LEVEL "debug"
```

### Staging Environment  
```bash
doppler setup --project routeros-cm --config staging
doppler secrets set PHX_HOST "staging.yourdomain.com"
doppler secrets set URL_SCHEME "https"
doppler secrets set URL_PORT "443"
doppler secrets set DATABASE_PATH "/app/staging_routeros_cm.db"
```

### Production Environment
```bash
doppler setup --project routeros-cm --config production
doppler secrets set PHX_HOST "yourdomain.com"
doppler secrets set URL_SCHEME "https"
doppler secrets set URL_PORT "443"
doppler secrets set DATABASE_PATH "/app/routeros_cm.db"
doppler secrets set LOG_LEVEL "warn"
```

## Quick Commands Reference

```bash
# View current configuration
doppler secrets

# Update a secret
doppler secrets set KEY_NAME "new_value"

# Delete a secret
doppler secrets delete KEY_NAME

# Switch environments
doppler setup --project routeros-cm --config staging

# Run app with Doppler
doppler run -- mix phx.server

# Get service token for deployment
doppler configs tokens create production --project routeros-cm

# Test Doppler connection
doppler me
```

## Troubleshooting

### Common Issues

1. **"DOPPLER_TOKEN not found"**
   - Make sure you've set the service token in your deployment environment
   - Verify the token with `doppler me`

2. **"Failed to fetch secrets"**
   - Check network connectivity to api.doppler.com
   - Verify the service token has the correct permissions
   - Check Doppler status at status.doppler.com

3. **"Invalid configuration values"**
   - Check logs for specific parsing errors
   - Verify boolean values are "true"/"false", not "yes"/"no"
   - Ensure integer values are valid numbers

### Debug Commands

```bash
# Test connection
doppler run --command "env | grep SECRET_KEY_BASE"

# Check logs during startup
doppler run -- mix phx.server 2>&1 | grep DopplerConfigProvider

# Verify all secrets are loaded
doppler secrets download --format json
```

## Security Best Practices

1. **Never commit service tokens** to version control
2. **Use separate tokens** for each environment
3. **Rotate tokens regularly** (every 90 days)
4. **Monitor access logs** in Doppler dashboard
5. **Use least privilege** - only grant necessary permissions
6. **Enable audit logging** in your Doppler organization

## Next Steps

1. ✅ Set up Doppler project and secrets (above)
2. ✅ Test locally with `doppler run -- mix phx.server`
3. ⬜ Deploy to staging with service token
4. ⬜ Verify configuration in staging environment
5. ⬜ Deploy to production with production service token
6. ⬜ Remove old environment variables from deployment configs
7. ⬜ Set up monitoring and alerts for secret access

Your RouterOS CM application is now configured with secure, centralized secret management! 🚀