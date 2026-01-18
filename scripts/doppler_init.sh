#!/bin/bash
#
# Initialize Doppler secrets for RouterOS CM
# Usage: ./scripts/doppler_init.sh
#
# Requires: doppler CLI installed and configured
#

set -e

PROJECT="routeros_cm"
CONFIG="lab"

echo "=== RouterOS CM Doppler Secret Initialization ==="
echo "Project: $PROJECT"
echo "Config:  $CONFIG"
echo ""

# Check for doppler CLI
if ! command -v doppler &> /dev/null; then
    echo "Error: doppler CLI not found. Install from https://docs.doppler.com/docs/cli"
    exit 1
fi

# Check if project exists, create if not
if ! doppler projects get "$PROJECT" &> /dev/null; then
    echo "Creating Doppler project '$PROJECT'..."
    doppler projects create "$PROJECT" --description "RouterOS Cluster Manager"
fi

# Check if config exists, create if not
if ! doppler configs get --project "$PROJECT" --config "$CONFIG" &> /dev/null; then
    echo "Creating Doppler config '$CONFIG'..."
    # Create environment first if it doesn't exist (required as base)
    # Syntax: doppler environments create [name] [slug] --project <project>
    doppler environments create "Lab" "lab" --project "$PROJECT" 2>/dev/null || true
    doppler configs create "$CONFIG" --project "$PROJECT" --environment "lab" 2>/dev/null || true
fi

# Generate SECRET_KEY_BASE (64 bytes, base64 encoded = 88 chars)
echo "Generating SECRET_KEY_BASE..."
SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')

# Generate CREDENTIAL_KEY (32 bytes, base64 encoded = 44 chars)
echo "Generating CREDENTIAL_KEY..."
CREDENTIAL_KEY=$(openssl rand -base64 32 | tr -d '\n')

# Prompt for database connection details
echo ""
echo "=== PostgreSQL Connection Details ==="
echo ""
read -p "DATABASE_HOST (e.g., db.example.com): " DATABASE_HOST
read -p "DATABASE_PORT [5432]: " DATABASE_PORT
DATABASE_PORT=${DATABASE_PORT:-5432}
read -p "DATABASE_NAME (e.g., routeros_cm_prod): " DATABASE_NAME
read -p "DATABASE_USER (e.g., routeros_cm): " DATABASE_USER
read -s -p "DATABASE_PASSWORD: " DATABASE_PASSWORD
echo ""

if [ -z "$DATABASE_HOST" ] || [ -z "$DATABASE_NAME" ] || [ -z "$DATABASE_USER" ]; then
    echo "Error: DATABASE_HOST, DATABASE_NAME, and DATABASE_USER are required"
    exit 1
fi

# Confirm before pushing
echo ""
echo "=== Secrets to be pushed ==="
echo "DATABASE_HOST:    $DATABASE_HOST"
echo "DATABASE_PORT:    $DATABASE_PORT"
echo "DATABASE_NAME:    $DATABASE_NAME"
echo "DATABASE_USER:    $DATABASE_USER"
echo "DATABASE_PASSWORD: ********"
echo "SECRET_KEY_BASE:  ${SECRET_KEY_BASE:0:20}..."
echo "CREDENTIAL_KEY:   ${CREDENTIAL_KEY:0:20}..."
echo ""
read -p "Push these secrets to Doppler $PROJECT/$CONFIG? (y/N) " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Push secrets to Doppler
echo ""
echo "Pushing secrets to Doppler..."

doppler secrets set \
    --project "$PROJECT" \
    --config "$CONFIG" \
    DATABASE_HOST="$DATABASE_HOST" \
    DATABASE_PORT="$DATABASE_PORT" \
    DATABASE_NAME="$DATABASE_NAME" \
    DATABASE_USER="$DATABASE_USER" \
    DATABASE_PASSWORD="$DATABASE_PASSWORD" \
    SECRET_KEY_BASE="$SECRET_KEY_BASE" \
    CREDENTIAL_KEY="$CREDENTIAL_KEY" \
    PHX_SERVER="true" \
    PORT="4000" \
    POOL_SIZE="10"

echo ""
echo "=== Done! ==="
echo ""
echo "Secrets have been pushed to Doppler ($PROJECT/$CONFIG)"
echo ""
echo "To use these secrets, set DOPPLER_TOKEN in your environment:"
echo "  export DOPPLER_TOKEN=\$(doppler configs tokens create --project $PROJECT --config $CONFIG --name deploy-token --plain)"
echo ""
echo "Or run with doppler:"
echo "  doppler run --project $PROJECT --config $CONFIG -- bin/routeros_cm start"
