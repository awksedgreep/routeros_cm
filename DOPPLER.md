# Doppler Integration for RouterOS CM

This document explains how to use Doppler for secure configuration management in the RouterOS CM application.

## Overview

Doppler is a secrets management platform that provides secure storage and delivery of environment variables and configuration data. This integration allows you to:

- Store all sensitive configuration in Doppler instead of environment variables
- Maintain different configurations for different environments (dev, staging, prod)
- Audit configuration changes and access
- Sync configurations across team members and deployments

## Setup

### 1. Install Doppler CLI

```bash
# macOS
brew install doppler

# Linux
curl -Ls https://cli.doppler.com/install.sh | sh

# Windows
scoop install doppler
```

### 2. Authenticate with Doppler

```bash
doppler login
```

### 3. Create Project and Environment

```bash
# Create a new project
doppler projects create routeros-cm

# Set up environments
doppler environments create dev --project routeros-cm
doppler environments create staging --project routeros-cm  
doppler environments create production --project routeros-cm
```

### 4. Configure Secrets

Use the provided setup script to configure all required secrets:

```bash
./scripts/doppler_setup.sh
```

Or manually configure secrets:

```bash
# Switch to your project and environment
doppler setup --project routeros-cm --config production

# Set required secrets
doppler secrets set SECRET_KEY_BASE "$(mix phx.gen.secret)"
doppler secrets set DATABASE_PATH "/app/routeros_cm.db"
doppler secrets set CREDENTIAL_KEY "$(openssl rand -base64 32)"
doppler secrets set PHX_HOST "your-domain.com"
# ... and so on
```

## Custom Implementation

This project uses a custom Doppler configuration provider (`RouterosCm.DopplerConfigProvider`) instead of third-party libraries. This provides:

- **Modern Elixir**: Uses current Logger functions (no deprecated warnings)
- **Type Safety**: Better type checking and error handling
- **Tailored Configuration**: Specifically designed for RouterOS CM's needs
- **Maintainability**: Full control over the implementation

The custom provider automatically handles type conversion for integers, booleans, and atoms, with proper error logging for invalid values.

## Required Configuration Variables

### Core Application
- `SECRET_KEY_BASE` - Phoenix secret key base for signing cookies and sessions
- `DATABASE_PATH` - Path to SQLite database file
- `CREDENTIAL_KEY` - 32-byte base64 key for encrypting stored credentials

### Server Configuration
- `PHX_HOST` - Hostname for the Phoenix application
- `PORT` - Internal port for the Phoenix server (default: 4000)
- `URL_PORT` - External port for generated URLs (default: 4000)
- `URL_SCHEME` - URL scheme: http or https (default: https)
- `PHX_SERVER` - Enable Phoenix server (default: true)

### Optional Configuration

#### Database
- `POOL_SIZE` - Database connection pool size (default: 5)

#### Container Registry
- `CONTAINER_REGISTRY` - Container registry URL (default: ghcr.io)
- `CONTAINER_NAMESPACE` - Container namespace (your GitHub username)
- `CONTAINER_IMAGE_NAME` - Container image name (default: routeros_cm)

#### SMTP Email
- `SMTP_HOST` - SMTP server hostname
- `SMTP_PORT` - SMTP server port (default: 587)
- `SMTP_USERNAME` - SMTP username
- `SMTP_PASSWORD` - SMTP password
- `SMTP_SSL` - Use SSL for SMTP (true/false, default: false)

#### Feature Flags
- `ENABLE_REGISTRATION` - Allow new user registration (default: false)
- `ENABLE_PASSWORD_RESET` - Allow password reset functionality (default: true)
- `ENABLE_EMAIL_VERIFICATION` - Require email verification (default: true)

#### Rate Limiting
- `RATE_LIMIT_LOGIN_ATTEMPTS` - Max login attempts per IP (default: 5)
- `RATE_LIMIT_API_REQUESTS` - Max API requests per minute (default: 100)

#### Monitoring & Logging
- `LOG_LEVEL` - Logging level: debug, info, warn, error (default: info)
- `SENTRY_DSN` - Sentry DSN for error tracking

#### Clustering
- `DNS_CLUSTER_QUERY` - DNS query for cluster discovery

## Usage

### Development

Run your application with Doppler:

```bash
# Start the Phoenix server with Doppler secrets
doppler run -- mix phx.server

# Run tests with Doppler secrets
doppler run -- mix test

# Build release with Doppler secrets
doppler run -- mix release
```

### Production Deployment

#### Option 1: Service Token (Recommended)

1. Create a service token for your production environment:
   ```bash
   doppler configs tokens create production --project routeros-cm
   ```

2. Set the `DOPPLER_TOKEN` environment variable in your deployment:
   ```bash
   export DOPPLER_TOKEN="dp.st.production.xxxxxxxxxxxx"
   ```

3. Deploy your application. The Doppler config provider will automatically fetch secrets at runtime.

#### Option 2: Docker Integration

```dockerfile
# In your Dockerfile
RUN curl -Ls https://cli.doppler.com/install.sh | sh

# Set the service token as an environment variable
ENV DOPPLER_TOKEN=dp.st.production.xxxxxxxxxxxx

# Your app will automatically use Doppler for configuration
CMD ["./bin/routeros_cm", "start"]
```

#### Option 3: Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: routeros-cm
spec:
  template:
    spec:
      containers:
      - name: routeros-cm
        image: your-registry/routeros-cm:latest
        env:
        - name: DOPPLER_TOKEN
          valueFrom:
            secretKeyRef:
              name: doppler-token
              key: token
```

## Configuration Behavior

The application automatically detects whether to use Doppler based on the presence of the `DOPPLER_TOKEN` environment variable:

- **With DOPPLER_TOKEN**: Uses Doppler config provider for all configuration
- **Without DOPPLER_TOKEN**: Falls back to traditional environment variables

This ensures backward compatibility with existing deployments while providing a smooth migration path to Doppler.

## Custom Provider Features

Our custom `RouterosCm.DopplerConfigProvider` includes:

- **Automatic Type Conversion**: Converts string values to appropriate Elixir types
- **Smart Configuration Merging**: Only applies non-empty configurations
- **Comprehensive Error Handling**: Graceful fallback on API failures
- **Modern Logging**: Uses current Logger functions without deprecation warnings
- **Efficient HTTP Client**: Uses Erlang's built-in `:httpc` for minimal dependencies

## Best Practices

### Environment Management
- Use separate Doppler projects or environments for dev/staging/prod
- Never commit service tokens to version control
- Rotate service tokens regularly

### Secret Organization
- Group related secrets using consistent naming prefixes
- Document the purpose of each secret
- Use descriptive names for secrets

### Access Control
- Limit access to production secrets to essential personnel
- Use workplace integrations for team access management
- Audit secret access regularly

## Migration from Environment Variables

To migrate from environment variables to Doppler:

1. **Audit Current Variables**: List all environment variables currently used
2. **Set Up Doppler**: Configure all variables in Doppler using the setup script
3. **Test**: Verify the application works with Doppler in a staging environment  
4. **Deploy**: Set `DOPPLER_TOKEN` in production and deploy
5. **Cleanup**: Remove environment variables from your deployment configuration

## Troubleshooting

### Common Issues

**Application fails to start with Doppler**
- Verify `DOPPLER_TOKEN` is set correctly
- Check that all required secrets are configured in Doppler
- Ensure the service token has access to the correct environment

**Secrets not updating**
- Restart the application after updating secrets in Doppler
- Verify the service token permissions
- Check Doppler audit logs for configuration changes

**Fallback to environment variables**
- Ensure `DOPPLER_TOKEN` is present in the environment
- Check that the token is valid with `doppler me`

### Debug Commands

```bash
# Test Doppler connection
doppler secrets

# Verify service token
doppler me

# Check which secrets are being used
doppler run --command "env | grep -E '^(SECRET_KEY_BASE|DATABASE_PATH)'"

# View audit logs
doppler activity
```

## Security Considerations

- **Service Tokens**: Treat service tokens like passwords - store them securely
- **Network Access**: Ensure your deployment environment can reach Doppler's API
- **Backup Strategy**: Consider exporting critical secrets as encrypted backups
- **Monitoring**: Set up alerts for unusual access patterns in Doppler

## Support

For issues specific to this integration:
- Check the RouterOS CM project documentation
- Review Elixir release configuration in `mix.exs`

For Doppler-related issues:
- [Doppler Documentation](https://docs.doppler.com/)
- [Doppler Support](https://doppler.com/support)

For custom provider issues:
- Check the implementation in `lib/routeros_cm/doppler_config_provider.ex`
- Review logs for configuration parsing errors
- Verify JSON response format from Doppler API