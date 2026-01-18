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
# Using standard PostgreSQL variable names so psql works on the command line
echo ""
echo "=== PostgreSQL Connection Details ==="
echo ""
read -p "PGHOST (e.g., db.example.com): " PGHOST
read -p "PGPORT [5432]: " PGPORT
PGPORT=${PGPORT:-5432}
read -p "PGDATABASE (e.g., routeros_cm_prod): " PGDATABASE
read -p "PGUSER (e.g., routeros_cm): " PGUSER
read -s -p "PGPASSWORD: " PGPASSWORD
echo ""
echo "PASSWORD_LENGTH:  ${#PGPASSWORD} characters"

if [ -z "$PGHOST" ] || [ -z "$PGDATABASE" ] || [ -z "$PGUSER" ]; then
    echo "Error: PGHOST, PGDATABASE, and PGUSER are required"
    exit 1
fi

# Prompt for app settings
echo ""
echo "=== Application Settings ==="
echo ""
read -p "PORT (Phoenix server port): " APP_PORT

if [ -z "$APP_PORT" ]; then
    echo "Error: PORT is required"
    exit 1
fi

# Confirm before pushing
echo ""
echo "=== Secrets to be pushed ==="
echo "PGHOST:           $PGHOST"
echo "PGPORT:           $PGPORT"
echo "PGDATABASE:       $PGDATABASE"
echo "PGUSER:           $PGUSER"
echo "PGPASSWORD:       ********"
echo "PORT:             $APP_PORT"
echo "SECRET_KEY_BASE:  ${SECRET_KEY_BASE:0:20}..."
echo "CREDENTIAL_KEY:   ${CREDENTIAL_KEY:0:20}..."
echo ""
read -p "Push these secrets to Doppler $PROJECT/$CONFIG? (Y/n) " CONFIRM < /dev/tty

if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Push secrets to Doppler
echo ""
echo "Pushing secrets to Doppler..."

doppler secrets set \
    --project "$PROJECT" \
    --config "$CONFIG" \
    PGHOST="$PGHOST" \
    PGPORT="$PGPORT" \
    PGDATABASE="$PGDATABASE" \
    PGUSER="$PGUSER" \
    PGPASSWORD="$PGPASSWORD" \
    SECRET_KEY_BASE="$SECRET_KEY_BASE" \
    CREDENTIAL_KEY="$CREDENTIAL_KEY" \
    PHX_SERVER="true" \
    PORT="$APP_PORT" \
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
