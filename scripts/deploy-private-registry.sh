#!/bin/bash

# Deploy to Private Docker Registry
set -e

# Configuration
REGISTRY_HOST=${REGISTRY_HOST:-"your-registry.company.com"}
IMAGE_NAME=${IMAGE_NAME:-"lesetool-directus"}
VERSION=${VERSION:-"latest"}
FULL_IMAGE_NAME="$REGISTRY_HOST/$IMAGE_NAME:$VERSION"

echo "🚀 Deploying to private registry: $FULL_IMAGE_NAME"

# Step 1: Build the image
echo "📦 Building Docker image..."
docker build -t $IMAGE_NAME:$VERSION .

# Step 2: Tag for private registry
echo "🏷️  Tagging image for private registry..."
docker tag $IMAGE_NAME:$VERSION $FULL_IMAGE_NAME

# Step 3: Login to private registry
echo "🔐 Logging in to private registry..."
echo "Please enter your registry credentials:"
docker login $REGISTRY_HOST

# Step 4: Push to registry
echo "⬆️  Pushing to private registry..."
docker push $FULL_IMAGE_NAME

echo "✅ Successfully deployed to $FULL_IMAGE_NAME"
echo ""
echo "To deploy on your servers, run:"
echo "docker pull $FULL_IMAGE_NAME"
echo "docker-compose up -d"