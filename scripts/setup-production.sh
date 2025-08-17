#!/bin/bash

# Production Setup Script
set -e

echo "🚀 Setting up production deployment..."

# Check if .env exists
if [ ! -f .env ]; then
    echo "📋 Creating production environment file..."
    cp .env.prod.example .env
    echo "⚠️  IMPORTANT: Edit .env file with your production values!"
    echo "   - Set secure passwords"
    echo "   - Generate new KEY and SECRET"
    echo "   - Configure your registry host"
    exit 1
fi

# Source environment variables
source .env

# Validate required variables
required_vars=("KEY" "SECRET" "ADMIN_EMAIL" "ADMIN_PASSWORD" "REGISTRY_HOST")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Missing required variable: $var"
        echo "Please configure it in .env file"
        exit 1
    fi
done

# Check if using default values (security check)
if [ "$ADMIN_PASSWORD" = "your_secure_admin_password" ] || 
   [ "$KEY" = "your-32-character-encryption-key-here" ] ||
   [ "$SECRET" = "your-32-character-jwt-secret-here" ]; then
    echo "❌ You're still using default security values!"
    echo "Please update KEY, SECRET, and ADMIN_PASSWORD in .env"
    exit 1
fi

echo "✅ Environment validation passed"

# Create production directories
echo "📁 Creating production directories..."
mkdir -p backups logs

# Generate SSL certificates directory (if needed)
mkdir -p ssl

# Set proper permissions
chmod 600 .env

echo "✅ Production setup complete!"
echo ""
echo "Next steps:"
echo "1. Deploy your image: ./scripts/deploy-private-registry.sh"
echo "2. Start services: docker-compose -f docker-compose.prod.yml up -d"
echo "3. Check logs: docker-compose -f docker-compose.prod.yml logs -f"