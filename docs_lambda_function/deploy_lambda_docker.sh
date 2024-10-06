#!/bin/bash

# Get arguments from the command line
AWS_REGION=$1
ECR_REPO_NAME=$2
IMAGE_TAG=$3
LAMBDA_NAME=$4
ROLE_NAME=$5
BUCKET_NAME=$6

# Check if all required arguments are provided
if [ -z "$AWS_REGION" ] || [ -z "$ECR_REPO_NAME" ] || [ -z "$IMAGE_TAG" ] || [ -z "$LAMBDA_NAME" ] || [ -z "$ROLE_NAME" ] || [ -z "$BUCKET_NAME" ]; then
  echo "Usage: $0 <aws_region> <ecr_repo_name> <image_tag> <lambda_name> <role_name> <bucket_name>"
  echo "Example: $0 eu-north-1 processing-service-image latest processing-service-lambda lambda-docker-execution-role aws-test-docs-loka"
  echo "Please provide all required arguments."
  exit 1
fi

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Step 1: Create ECR Repository ==="
aws ecr create-repository --repository-name $ECR_REPO_NAME --region $AWS_REGION
echo "ECR repository $ECR_REPO_NAME created."

echo "=== Step 2: Authenticate Docker with ECR ==="
sudo docker login -u AWS -p $(aws ecr get-login-password --region $AWS_REGION) ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
echo "Docker authenticated with ECR."

echo "=== Step 3: Build Docker Image ==="
sudo docker build -t $ECR_REPO_NAME .
echo "Docker image built."

echo "=== Step 4: Tag Docker Image ==="
sudo docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG}
echo "Docker image tagged."

echo "=== Step 5: Push Docker Image to ECR ==="
sudo docker push ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG}
echo "Docker image pushed to ECR."

echo "=== Step 6: Create Lambda Execution Role ==="
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://<(echo '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "lambda.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
  }') \
  --region $AWS_REGION

echo "=== Wait for Role to be created ==="
sleep 15

echo "Attaching policies to the role..."
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
echo "Execution role created and policies attached."

echo "=== Step 7: Wait for Role to Propagate and Policies to be applied ==="
sleep 15
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)
echo "ROLE ARN: $ROLE_ARN"

echo "=== Step 8: Create Lambda Function with Docker Image ==="
aws lambda create-function \
  --function-name $LAMBDA_NAME \
  --package-type Image \
  --code ImageUri=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG} \
  --role $ROLE_ARN \
  --timeout 300 \
  --memory-size 1024 \
  --region $AWS_REGION
echo "Lambda function $LAMBDA_NAME created with Docker image."

echo "=== Step 9: Add Lambda Invoke Permission for S3 ==="
aws lambda add-permission \
  --function-name $LAMBDA_NAME \
  --statement-id s3invoke \
  --action lambda:InvokeFunction \
  --principal s3.amazonaws.com \
  --source-arn arn:aws:s3:::$BUCKET_NAME \
  --source-account $ACCOUNT_ID \
  --region $AWS_REGION
echo "Lambda permission for S3 added."

echo "=== Step 10: Wait 30s for Permission to be applied and fetch Lambda ARN ==="
sleep 30
LAMBDA_ARN=$(aws lambda get-function --function-name $LAMBDA_NAME --query 'Configuration.FunctionArn' --output text)
echo "Lambda function ARN: $LAMBDA_ARN"

echo "=== Step 11: Create S3 Event Trigger for Lambda ==="
aws s3api put-bucket-notification-configuration --bucket $BUCKET_NAME \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [
      {
        "LambdaFunctionArn": "'$LAMBDA_ARN'",
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {
          "Key": {
            "FilterRules": [
              {
                "Name": "prefix",
                "Value": "sagemaker_documentation/"
              },
              {
                "Name": "suffix",
                "Value": ".md"
              }
            ]
          }
        }
      }
    ]
  }'
echo "S3 bucket event notification for Lambda set up."

echo "=== Lambda function setup with Docker image is complete! ==="
