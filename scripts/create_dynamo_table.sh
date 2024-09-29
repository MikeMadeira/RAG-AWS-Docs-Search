#!/bin/bash

# Get arguments from the command line
TABLE_NAME=$1
REGION=$2

# Check if both arguments are provided
if [ -z "$TABLE_NAME" ] || [ -z "$REGION" ]; then
  echo "Usage: $0 <table_name> <region>"
  echo "Example: $0 aws_test_docs_chunks eu-north-1"
  echo "Please provide both the DynamoDB table name and the AWS region."
  exit 1
fi

# Delete DynamoDB table if it exists
aws dynamodb delete-table --table-name $TABLE_NAME --region $REGION

# Wait for the table to be deleted before proceeding
aws dynamodb wait table-not-exists --table-name $TABLE_NAME --region $REGION

echo "DynamoDB table $TABLE_NAME deleted."

# Create DynamoDB table with unique 'id' as the primary key and with a GSI for faiss_index
aws dynamodb create-table \
    --table-name $TABLE_NAME \
    --attribute-definitions \
        AttributeName=id,AttributeType=S \
        AttributeName=faiss_index,AttributeType=N \
    --key-schema \
        AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --global-secondary-indexes \
        "IndexName=faiss_index_gsi,KeySchema=[{AttributeName=faiss_index,KeyType=HASH}],Projection={ProjectionType=ALL}" \
    --region $REGION

echo "DynamoDB table $TABLE_NAME created with 'id' as the primary key and with a GSI for faiss_index."
