#!/bin/bash

# Generate secure secrets for production deployment
set -e

echo "🔐 Generating secure secrets for production..."

# Function to generate random string
generate_secret() {
    openssl rand -hex 16
}

# Generate secrets
KEY=$(generate_secret)
SECRET=$(generate_secret)

echo ""
echo "Generated secrets (add these to your .env file):"
echo "=============================================="
echo "KEY=$KEY"
echo "SECRET=$SECRET"
echo ""
echo "Also remember to set:"
echo "- ADMIN_EMAIL=your-email@company.com"
echo "- ADMIN_PASSWORD=your-secure-password"
echo "- DB_PASSWORD=your-secure-db-password"
echo "- REGISTRY_HOST=your-registry.company.com"
echo ""
echo "⚠️  IMPORTANT: Keep these secrets secure and never commit them to git!"