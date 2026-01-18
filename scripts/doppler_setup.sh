#!/bin/bash

# Doppler Setup Script for RouterOS CM
# This script helps configure your Doppler secrets for the RouterOS CM application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}RouterOS CM - Doppler Configuration Setup${NC}"
echo "=============================================="
echo

# Check if doppler CLI is installed
if ! command -v doppler &> /dev/null; then
    echo -e "${RED}Error: Doppler CLI is not installed.${NC}"
    echo "Please install it from: https://docs.doppler.com/docs/install-cli"
    exit 1
fi

# Check if user is logged in to doppler
if ! doppler me &> /dev/null; then
    echo -e "${YELLOW}You need to login to Doppler first.${NC}"
    echo "Run: doppler login"
    exit 1
fi

echo -e "${GREEN}✓ Doppler CLI is installed and authenticated${NC}"
echo

# Project and environment setup
PROJECT_NAME="${DOPPLER_PROJECT:-routeros-cm}"
ENVIRONMENT="${DOPPLER_ENVIRONMENT:-production}"

echo "Setting up Doppler configuration for:"
echo "  Project: $PROJECT_NAME"
echo "  Environment: $ENVIRONMENT"
echo

# Check if project exists, if not create it
if ! doppler projects get "$PROJECT_NAME" &> /dev/null; then
    echo -e "${YELLOW}Project '$PROJECT_NAME' doesn't exist. Creating it...${NC}"
    doppler projects create "$PROJECT_NAME"
    echo -e "${GREEN}✓ Created project '$PROJECT_NAME'${NC}"
fi

# Check if environment exists, if not create it
if ! doppler environments get "$ENVIRONMENT" --project "$PROJECT_NAME" &> /dev/null; then
    echo -e "${YELLOW}Environment '$ENVIRONMENT' doesn't exist. Creating it...${NC}"
    doppler environments create "$ENVIRONMENT" --project "$PROJECT_NAME"
    echo -e "${GREEN}✓ Created environment '$ENVIRONMENT'${NC}"
fi

# Setup the configuration
doppler setup --project "$PROJECT_NAME" --config "$ENVIRONMENT" --no-interactive
echo

# Function to set secret if it doesn't exist
set_secret_if_missing() {
    local key=$1
    local description=$2
    local default_value=$3
    local is_required=${4:-true}

    if ! doppler secrets get "$key" --plain &> /dev/null; then
        echo -e "${YELLOW}Setting up: $key${NC}"
        echo "  Description: $description"

        if [ "$is_required" = "true" ]; then
            if [ -n "$default_value" ]; then
                read -p "  Enter value (default: $default_value): " user_value
                value=${user_value:-$default_value}
            else
                read -p "  Enter value: " value
                while [ -z "$value" ]; do
                    echo -e "${RED}  This value is required.${NC}"
                    read -p "  Enter value: " value
                done
            fi
        else
            read -p "  Enter value (optional, press enter to skip): " value
            if [ -z "$value" ]; then
                echo "  Skipped."
                echo
                return
            fi
        fi

        # Generate secure defaults for certain keys
        case "$key" in
            "SECRET_KEY_BASE")
                if [ -z "$value" ]; then
                    echo "  Generating SECRET_KEY_BASE..."
                    value=$(openssl rand -base64 48)
                fi
                ;;
            "CREDENTIAL_KEY")
                if [ -z "$value" ] && [ -z "$default_value" ]; then
                    echo "  Generating CREDENTIAL_KEY..."
                    value=$(openssl rand -base64 32)
                fi
                ;;
        esac

        doppler secrets set "$key" "$value"
        echo -e "${GREEN}  ✓ Set $key${NC}"
    else
        echo -e "${GREEN}✓ $key is already configured${NC}"
    fi
    echo
}

echo "Configuring required secrets..."
echo "==============================="

# Core application secrets
set_secret_if_missing "SECRET_KEY_BASE" "Phoenix secret key base for signing cookies and sessions" ""
set_secret_if_missing "DATABASE_PATH" "Path to SQLite database file" "/app/routeros_cm.db"
set_secret_if_missing "CREDENTIAL_KEY" "Key for encrypting stored credentials (32-byte base64)" ""

# Server configuration
echo -e "${BLUE}Server Configuration${NC}"
if [ "$ENVIRONMENT" = "dev" ] || [ "$ENVIRONMENT" = "development" ]; then
    set_secret_if_missing "PHX_HOST" "Hostname for the Phoenix application" "localhost"
    set_secret_if_missing "URL_SCHEME" "URL scheme (http or https)" "http"
    set_secret_if_missing "URL_PORT" "External port for generated URLs" "4000"
else
    read -p "Enter your domain name (e.g., yourdomain.com): " domain
    set_secret_if_missing "PHX_HOST" "Hostname for the Phoenix application" "${domain:-yourdomain.com}"
    set_secret_if_missing "URL_SCHEME" "URL scheme (http or https)" "https"
    set_secret_if_missing "URL_PORT" "External port for generated URLs" "443"
fi
set_secret_if_missing "PORT" "Internal port for the Phoenix server" "4000"
set_secret_if_missing "PHX_SERVER" "Enable Phoenix server" "true"

echo "Configuring optional secrets..."
echo "==============================="

# Database configuration
set_secret_if_missing "POOL_SIZE" "Database connection pool size" "5" false

# Container configuration
set_secret_if_missing "CONTAINER_REGISTRY" "Container registry URL" "ghcr.io" false
set_secret_if_missing "CONTAINER_NAMESPACE" "Container namespace (GitHub username)" "" false
set_secret_if_missing "CONTAINER_IMAGE_NAME" "Container image name" "routeros_cm" false

# SMTP configuration
echo -e "${BLUE}SMTP Configuration (for email notifications)${NC}"
set_secret_if_missing "SMTP_HOST" "SMTP server hostname" "localhost" false
set_secret_if_missing "SMTP_PORT" "SMTP server port" "587" false
set_secret_if_missing "SMTP_USERNAME" "SMTP username" "" false
set_secret_if_missing "SMTP_PASSWORD" "SMTP password" "" false
set_secret_if_missing "SMTP_SSL" "Use SSL for SMTP (true/false)" "false" false

# Feature flags
echo -e "${BLUE}Feature Flags${NC}"
set_secret_if_missing "ENABLE_REGISTRATION" "Allow new user registration" "false" false
set_secret_if_missing "ENABLE_PASSWORD_RESET" "Allow password reset functionality" "true" false
set_secret_if_missing "ENABLE_EMAIL_VERIFICATION" "Require email verification" "true" false

# Rate limiting
echo -e "${BLUE}Rate Limiting${NC}"
set_secret_if_missing "RATE_LIMIT_LOGIN_ATTEMPTS" "Max login attempts per IP" "5" false
set_secret_if_missing "RATE_LIMIT_API_REQUESTS" "Max API requests per minute" "100" false

# Monitoring
echo -e "${BLUE}Monitoring & Logging${NC}"
set_secret_if_missing "LOG_LEVEL" "Logging level (debug, info, warn, error)" "info" false
set_secret_if_missing "SENTRY_DSN" "Sentry DSN for error tracking" "" false

# DNS cluster (for distributed deployments)
set_secret_if_missing "DNS_CLUSTER_QUERY" "DNS query for cluster discovery" "" false

echo -e "${GREEN}Doppler configuration complete!${NC}"
echo
echo "📋 Configuration Summary:"
echo "  Project: $PROJECT_NAME"
echo "  Environment: $ENVIRONMENT"
echo "  Secrets configured: $(doppler secrets --json | jq '. | length') secrets"
echo
echo "🚀 Next steps:"
echo "1. Test locally: ${YELLOW}doppler run -- mix phx.server${NC}"
echo "2. Build release: ${YELLOW}doppler run -- mix release${NC}"
echo "3. For production, create service token:"
echo "   ${YELLOW}doppler configs tokens create $ENVIRONMENT --project $PROJECT_NAME${NC}"
echo
echo "📚 Useful commands:"
echo "  View secrets:     ${YELLOW}doppler secrets${NC}"
echo "  Update secret:    ${YELLOW}doppler secrets set KEY_NAME new_value${NC}"
echo "  Switch env:       ${YELLOW}doppler setup --project $PROJECT_NAME --config staging${NC}"
echo "  Test connection:  ${YELLOW}doppler me${NC}"
echo
echo -e "${GREEN}Your RouterOS CM is now Doppler-powered! 🎉${NC}"
