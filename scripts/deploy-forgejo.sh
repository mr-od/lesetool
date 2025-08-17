#!/bin/bash

# Deploy to Forgejo Container Registry
set -e

# Configuration
FORGEJO_REGISTRY=${FORGEJO_REGISTRY:-"git.ecoiot.co.nz"}
FORGEJO_USER=${FORGEJO_USER:-"your-username"}
FORGEJO_ORG=${FORGEJO_ORG:-"$FORGEJO_USER"}
IMAGE_NAME=${IMAGE_NAME:-"lesetool-directus"}
VERSION=${VERSION:-"latest"}

# Full image name following Forgejo convention: {registry}/{owner}/{image}:{tag}
FULL_IMAGE_NAME="$FORGEJO_REGISTRY/$FORGEJO_ORG/$IMAGE_NAME:$VERSION"

echo "🚀 Deploying to Forgejo Registry: $FULL_IMAGE_NAME"

# Check if Forgejo registry and user are configured
if [ "$FORGEJO_REGISTRY" = "forgejo.yourcompany.com" ] || [ "$FORGEJO_USER" = "your-username" ]; then
    echo "❌ Please configure FORGEJO_REGISTRY and FORGEJO_USER environment variables"
    echo "Example:"
    echo "export FORGEJO_REGISTRY=forgejo.yourcompany.com"
    echo "export FORGEJO_USER=your-username"
    echo "export FORGEJO_ORG=your-org  # Optional, defaults to username"
    exit 1
fi

# Step 1: Build the image
echo "🔨 Building Docker image..."
docker build -t $IMAGE_NAME:$VERSION .

# Step 2: Tag for Forgejo registry
echo "🏷️  Tagging image for Forgejo registry..."
docker tag $IMAGE_NAME:$VERSION $FULL_IMAGE_NAME

# Step 3: Login to Forgejo registry
echo "🔐 Logging in to Forgejo registry..."
echo "Please enter your Forgejo credentials (use Personal Access Token if using 2FA):"
docker login $FORGEJO_REGISTRY --username $FORGEJO_USER

# Step 4: Push to Forgejo registry
echo "⬆️  Pushing to Forgejo registry..."
docker push $FULL_IMAGE_NAME

echo "✅ Successfully deployed to Forgejo: $FULL_IMAGE_NAME"
echo ""
echo "Image available at: https://$FORGEJO_REGISTRY/$FORGEJO_ORG/-/packages/container/$IMAGE_NAME"
echo ""
echo "To deploy on your servers:"
echo "1. Login: docker login $FORGEJO_REGISTRY"
echo "2. Pull: docker pull $FULL_IMAGE_NAME"
echo "3. Update docker-compose.forgejo.yml with image: $FULL_IMAGE_NAME"
echo "4. Deploy: docker-compose -f docker-compose.forgejo.yml up -d"