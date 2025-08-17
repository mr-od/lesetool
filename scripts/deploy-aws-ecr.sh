#!/bin/bash

# Deploy to AWS ECR (Elastic Container Registry)
set -e

# Configuration
AWS_REGION=${AWS_REGION:-"us-west-2"}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-"123456789012"}
REPOSITORY_NAME=${REPOSITORY_NAME:-"lesetool-directus"}
VERSION=${VERSION:-"latest"}

ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
FULL_IMAGE_NAME="$ECR_URI/$REPOSITORY_NAME:$VERSION"

echo "🚀 Deploying to AWS ECR: $FULL_IMAGE_NAME"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install it first."
    exit 1
fi

# Step 1: Create ECR repository if it doesn't exist
echo "📦 Creating ECR repository (if not exists)..."
aws ecr describe-repositories --repository-names $REPOSITORY_NAME --region $AWS_REGION 2>/dev/null || \
aws ecr create-repository --repository-name $REPOSITORY_NAME --region $AWS_REGION

# Step 2: Get ECR login token
echo "🔐 Getting ECR login token..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI

# Step 3: Build the image
echo "🔨 Building Docker image..."
docker build -t $REPOSITORY_NAME:$VERSION .

# Step 4: Tag for ECR
echo "🏷️  Tagging image for ECR..."
docker tag $REPOSITORY_NAME:$VERSION $FULL_IMAGE_NAME

# Step 5: Push to ECR
echo "⬆️  Pushing to ECR..."
docker push $FULL_IMAGE_NAME

echo "✅ Successfully deployed to ECR: $FULL_IMAGE_NAME"
echo ""
echo "To deploy on your EC2 servers:"
echo "1. Configure AWS credentials on the server"
echo "2. Run: aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI"
echo "3. Update docker-compose.yml image to: $FULL_IMAGE_NAME"
echo "4. Run: docker-compose up -d"