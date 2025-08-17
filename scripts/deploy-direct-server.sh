#!/bin/bash

# Deploy directly to server (no registry needed)
set -e

# Configuration
SERVER_HOST=${SERVER_HOST:-"your-server.com"}
SERVER_USER=${SERVER_USER:-"ubuntu"}
IMAGE_NAME=${IMAGE_NAME:-"lesetool-directus"}
VERSION=${VERSION:-"latest"}

echo "🚀 Deploying directly to server: $SERVER_USER@$SERVER_HOST"

# Step 1: Build the image
echo "🔨 Building Docker image..."
docker build -t $IMAGE_NAME:$VERSION .

# Step 2: Save image to tar file
echo "💾 Saving Docker image to tar file..."
docker save $IMAGE_NAME:$VERSION | gzip > ${IMAGE_NAME}-${VERSION}.tar.gz

# Step 3: Copy files to server
echo "📤 Copying files to server..."
scp ${IMAGE_NAME}-${VERSION}.tar.gz $SERVER_USER@$SERVER_HOST:~/
scp docker-compose.yml $SERVER_USER@$SERVER_HOST:~/
scp .env.example $SERVER_USER@$SERVER_HOST:~/.env
scp -r scripts/ $SERVER_USER@$SERVER_HOST:~/

# Step 4: Deploy on server
echo "🚀 Deploying on server..."
ssh $SERVER_USER@$SERVER_HOST << EOF
    echo "Loading Docker image..."
    gunzip -c ${IMAGE_NAME}-${VERSION}.tar.gz | docker load
    
    echo "Stopping existing containers..."
    docker-compose down 2>/dev/null || true
    
    echo "Starting new deployment..."
    docker-compose up -d
    
    echo "Cleaning up..."
    rm ${IMAGE_NAME}-${VERSION}.tar.gz
    
    echo "✅ Deployment complete!"
    docker-compose ps
EOF

# Step 5: Cleanup local files
echo "🧹 Cleaning up local files..."
rm ${IMAGE_NAME}-${VERSION}.tar.gz

echo "✅ Successfully deployed to $SERVER_HOST"