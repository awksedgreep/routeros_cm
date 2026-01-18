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
    # Create a dev environment first if it doesn't exist (required as base)
    if ! doppler environments get --project "$PROJECT" --environment "lab" &> /dev/null 2>&1; then
        doppler environments create --project "$PROJECT" --slug "lab" --name "Lab"
    fi
    doppler configs create --project "$PROJECT" --environment "lab" --name "$CONFIG" 2>/dev/null || true
fi

# Generate SECRET_KEY_BASE (64 bytes, base64 encoded = 88 chars)
echo "Generating SECRET_KEY_BASE..."
SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')

# Generate CREDENTIAL_KEY (32 bytes, base64 encoded = 44 chars)
echo "Generating CREDENTIAL_KEY..."
CREDENTIAL_KEY=$(openssl rand -base64 32 | tr -d '\n')

# Prompt for DATABASE_URL
echo ""
echo "Enter your PostgreSQL connection URL"
echo "Format: ecto://username:password@hostname:port/database_name"
echo "Example: ecto://postgres:secretpass@db.example.com:5432/routeros_cm_prod"
echo ""
read -p "DATABASE_URL: " DATABASE_URL

if [ -z "$DATABASE_URL" ]; then
    echo "Error: DATABASE_URL is required"
    exit 1
fi

# Confirm before pushing
echo ""
echo "=== Secrets to be pushed ==="
echo "DATABASE_URL:     ${DATABASE_URL:0:20}..."
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
    DATABASE_URL="$DATABASE_URL" \
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
