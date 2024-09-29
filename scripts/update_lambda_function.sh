#!/bin/bash

# Get arguments from the command line
AWS_REGION=$1
ECR_REPO_NAME=$2
IMAGE_TAG=$3
LAMBDA_NAME=$4

# Check if all required arguments are provided
if [ -z "$AWS_REGION" ] || [ -z "$ECR_REPO_NAME" ] || [ -z "$IMAGE_TAG" ] || [ -z "$LAMBDA_NAME" ]; then
  echo "Usage: $0 <aws_region> <ecr_repo_name> <image_tag> <lambda_name>"
  echo "Example: $0 eu-north-1 processing-service-image latest processing-service-lambda"
  echo "Please provide all required arguments."
  exit 1
fi

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Step 1: Authenticate Docker with ECR ==="
sudo docker login -u AWS -p $(aws ecr get-login-password --region $AWS_REGION) ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
echo "Docker authenticated with ECR."

echo "=== Step 2: Build Docker Image ==="
sudo docker build -t $ECR_REPO_NAME .
echo "Docker image built."

echo "=== Step 3: Tag Docker Image ==="
sudo docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG}
echo "Docker image tagged."

echo "=== Step 4: Push Docker Image to ECR ==="
sudo docker push ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG}
echo "Docker image pushed to ECR."

echo "=== Step 5: Update Lambda Function with Docker Image ==="
aws lambda update-function-code \
  --function-name $LAMBDA_NAME \
  --image-uri ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG} \
  --region $AWS_REGION
echo "Lambda function $LAMBDA_NAME updated with Docker image."
