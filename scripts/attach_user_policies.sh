#!/bin/bash

# Get the IAM user name from the command line
IAM_USER=$1

# Check if the IAM user name is provided
if [ -z "$IAM_USER" ]; then
  echo "Usage: $0 <iam_user>"
  echo "Example: $0 MikeMadeira"
  echo "Please provide the IAM user name you created in AWS console."
  exit 1
fi

# Attach the AdministratorAccess policy
aws iam attach-user-policy \
    --user-name $IAM_USER \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
echo "AdministratorAccess policy attached to user $IAM_USER."

# Attach the AmazonDynamoDBFullAccess policy
aws iam attach-user-policy \
    --user-name $IAM_USER \
    --policy-arn "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
echo "AmazonDynamoDBFullAccess policy attached to user $IAM_USER."

# Attach the AmazonEC2ContainerRegistryFullAccess policy
aws iam attach-user-policy \
    --user-name $IAM_USER \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
echo "AmazonEC2ContainerRegistryFullAccess policy attached to user $IAM_USER."

# Attach the AmazonS3FullAccess policy
aws iam attach-user-policy \
    --user-name $IAM_USER \
    --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess"
echo "AmazonS3FullAccess policy attached to user $IAM_USER."

# Attach the AWSLambda_FullAccess policy
aws iam attach-user-policy \
    --user-name $IAM_USER \
    --policy-arn "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
echo "AWSLambda_FullAccess policy attached to user $IAM_USER."
