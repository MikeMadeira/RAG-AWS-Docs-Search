#!/bin/bash

# Get arguments from the command line
BUCKET_NAME=$1
REGION=$2

# Check if both arguments are provided
if [ -z "$BUCKET_NAME" ] || [ -z "$REGION" ]; then
  echo "Usage: $0 <bucket_name> <region>"
  echo "Example: $0 aws-test-docs-loka eu-north-1"
  echo "Please provide both the S3 bucket name and the AWS region."
  exit 1
fi

# Create S3 bucket
aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION --create-bucket-configuration LocationConstraint=$REGION

echo "S3 bucket $BUCKET_NAME created in region $REGION."
