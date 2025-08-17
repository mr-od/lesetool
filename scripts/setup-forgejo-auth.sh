#!/bin/bash

# Setup Forgejo Authentication for Container Registry
set -e

echo "🔐 Setting up Forgejo Container Registry Authentication"

# Configuration
FORGEJO_REGISTRY=${FORGEJO_REGISTRY:-"forgejo.yourcompany.com"}
FORGEJO_USER=${FORGEJO_USER:-""}
FORGEJO_TOKEN=${FORGEJO_TOKEN:-""}

# Check configuration
if [ -z "$FORGEJO_REGISTRY" ] || [ "$FORGEJO_REGISTRY" = "forgejo.yourcompany.com" ]; then
    echo "❌ Please set FORGEJO_REGISTRY environment variable"
    echo "Example: export FORGEJO_REGISTRY=forgejo.yourcompany.com"
    exit 1
fi

if [ -z "$FORGEJO_USER" ]; then
    echo "📝 Please enter your Forgejo username:"
    read -r FORGEJO_USER
fi

echo ""
echo "Authentication Options:"
echo "1. Interactive login (enter password/token when prompted)"
echo "2. Use Personal Access Token (recommended for automation)"
echo ""
echo "Choose option (1 or 2): "
read -r auth_option

case $auth_option in
    1)
        echo "🔑 Logging in to Forgejo registry interactively..."
        docker login $FORGEJO_REGISTRY --username $FORGEJO_USER
        ;;
    2)
        if [ -z "$FORGEJO_TOKEN" ]; then
            echo "🎫 Please enter your Personal Access Token:"
            echo "   (Create one at: https://$FORGEJO_REGISTRY/user/settings/applications)"
            read -rs FORGEJO_TOKEN
        fi
        
        echo "🔑 Logging in to Forgejo registry with token..."
        echo $FORGEJO_TOKEN | docker login $FORGEJO_REGISTRY --username $FORGEJO_USER --password-stdin
        ;;
    *)
        echo "❌ Invalid option"
        exit 1
        ;;
esac

echo "✅ Successfully authenticated with Forgejo registry"
echo ""
echo "Docker config saved to: ~/.docker/config.json"
echo "You can now push/pull images from: $FORGEJO_REGISTRY"
echo ""
echo "Next steps:"
echo "1. Deploy image: ./scripts/deploy-forgejo.sh"
echo "2. Or test pull: docker pull $FORGEJO_REGISTRY/your-org/lesetool-directus:latest"