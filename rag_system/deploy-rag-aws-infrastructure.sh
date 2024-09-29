#!/bin/bash

# Set variables
AWS_REGION="eu-north-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

FRONTEND_REPO_NAME="frontend-ecr-repo"
BACKEND_REPO_NAME="backend-ecr-repo"
FRONTEND_IMAGE_TAG="latest"
BACKEND_IMAGE_TAG="latest"
CLUSTER_NAME="my-ecs-cluster"
FRONTEND_TASK="frontend-task"
BACKEND_TASK="backend-task"
FRONTEND_SERVICE="frontend-service"
BACKEND_SERVICE="backend-service"
VPC_NAME="my-vpc"
ALB_SG_NAME="alb-security-group"
TARGET_GROUP_NAME_FRONTEND="frontend-target-group"
TARGET_GROUP_NAME_BACKEND="backend-target-group"
SUBNET_A="subnet-1"
SUBNET_B="subnet-2"

# Step 1: Create ECR repositories
echo "=== Step 1: Create ECR Repositories ==="
aws ecr create-repository --repository-name $FRONTEND_REPO_NAME --region $AWS_REGION
aws ecr create-repository --repository-name $BACKEND_REPO_NAME --region $AWS_REGION

# Step 2: Build and push Docker images to ECR
echo "=== Step 2: Build and push Docker images ==="
# Authenticate Docker to ECR
$(aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com)

# Build and push Frontend image
docker build -t $FRONTEND_REPO_NAME ./frontend
docker tag ${FRONTEND_REPO_NAME}:${FRONTEND_IMAGE_TAG} ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FRONTEND_REPO_NAME}:${FRONTEND_IMAGE_TAG}
docker push ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FRONTEND_REPO_NAME}:${FRONTEND_IMAGE_TAG}

# Build and push Backend image
docker build -t $BACKEND_REPO_NAME ./backend
docker tag ${BACKEND_REPO_NAME}:${BACKEND_IMAGE_TAG} ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BACKEND_REPO_NAME}:${BACKEND_IMAGE_TAG}
docker push ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BACKEND_REPO_NAME}:${BACKEND_IMAGE_TAG}

# Step 3: Create a VPC
echo "=== Step 3: Create VPC ==="
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text --region $AWS_REGION)

# Step 4: Create Subnets
echo "=== Step 4: Create Subnets ==="
SUBNET_A_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone ${AWS_REGION}a --query 'Subnet.SubnetId' --output text)
SUBNET_B_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone ${AWS_REGION}b --query 'Subnet.SubnetId' --output text)

# Step 5: Create Security Groups for ALB
echo "=== Step 5: Create Security Group for ALB ==="
ALB_SG_ID=$(aws ec2 create-security-group --group-name $ALB_SG_NAME --description "ALB Security Group" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $ALB_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0

# Step 6: Create Target Groups
echo "=== Step 6: Create Target Groups ==="
FRONTEND_TG_ARN=$(aws elbv2 create-target-group --name $TARGET_GROUP_NAME_FRONTEND --protocol HTTP --port 80 --vpc-id $VPC_ID --target-type ip --query 'TargetGroups[0].TargetGroupArn' --output text)
BACKEND_TG_ARN=$(aws elbv2 create-target-group --name $TARGET_GROUP_NAME_BACKEND --protocol HTTP --port 5000 --vpc-id $VPC_ID --target-type ip --query 'TargetGroups[0].TargetGroupArn' --output text)

# Step 7: Create ALBs
echo "=== Step 7: Create ALBs ==="
FRONTEND_ALB_ARN=$(aws elbv2 create-load-balancer --name frontend-alb --subnets $SUBNET_A_ID $SUBNET_B_ID --security-groups $ALB_SG_ID --scheme internet-facing --query 'LoadBalancers[0].LoadBalancerArn' --output text)
BACKEND_ALB_ARN=$(aws elbv2 create-load-balancer --name backend-alb --subnets $SUBNET_A_ID $SUBNET_B_ID --security-groups $ALB_SG_ID --scheme internal --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Step 8: Create ECS Cluster
echo "=== Step 8: Create ECS Cluster ==="
aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $AWS_REGION

# Step 9: Register Task Definitions
echo "=== Step 9: Register Task Definitions for Frontend and Backend ==="
# Register frontend task
cat <<EOT > frontend-task-def.json
{
    "family": "$FRONTEND_TASK",
    "containerDefinitions": [
        {
            "name": "$FRONTEND_TASK",
            "image": "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FRONTEND_REPO_NAME}:${FRONTEND_IMAGE_TAG}",
            "memory": 512,
            "cpu": 256,
            "essential": true,
            "portMappings": [
                {
                    "containerPort": 80,
                    "hostPort": 80
                }
            ]
        }
    ],
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512"
}
EOT
aws ecs register-task-definition --cli-input-json file://frontend-task-def.json

# Register backend task
cat <<EOT > backend-task-def.json
{
    "family": "$BACKEND_TASK",
    "containerDefinitions": [
        {
            "name": "$BACKEND_TASK",
            "image": "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BACKEND_REPO_NAME}:${BACKEND_IMAGE_TAG}",
            "memory": 512,
            "cpu": 256,
            "essential": true,
            "portMappings": [
                {
                    "containerPort": 5000,
                    "hostPort": 5000
                }
            ]
        }
    ],
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512"
}
EOT
aws ecs register-task-definition --cli-input-json file://backend-task-def.json

# Step 10: Create ECS Services
echo "=== Step 10: Create ECS Services for Frontend and Backend ==="
aws ecs create-service --cluster $CLUSTER_NAME --service-name $FRONTEND_SERVICE --task-definition $FRONTEND_TASK --desired-count 1 --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_A_ID,$SUBNET_B_ID],securityGroups=[$ALB_SG_ID],assignPublicIp=ENABLED}" --load-balancers "targetGroupArn=$FRONTEND_TG_ARN,containerName=$FRONTEND_TASK,containerPort=80"

aws ecs create-service --cluster $CLUSTER_NAME --service-name $BACKEND_SERVICE --task-definition $BACKEND_TASK --desired-count 1 --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_A_ID,$SUBNET_B_ID],securityGroups=[$ALB_SG_ID],assignPublicIp=DISABLED}" --load-balancers "targetGroupArn=$BACKEND_TG_ARN,containerName=$BACKEND_TASK,containerPort=5000"

echo "=== ECS Services Created ==="
