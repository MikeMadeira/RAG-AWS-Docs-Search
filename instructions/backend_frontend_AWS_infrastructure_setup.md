## Through terminal

### Create new repositories for backend and frontend through terminal

    aws ecr create-repository --repository-name flask-backend-rag-aws --region eu-north-1

    aws ecr create-repository --repository-name streamlit-frontend-rag-aws --region eu-north-1

### Authenticate Docker to your ECR registry

    sudo docker login -u AWS -p $(aws ecr get-login-password --region eu-north-1) <account-id>.dkr.ecr.eu-north-1.amazonaws.com

### Tag the backend Docker image for ECR
    sudo docker tag rag-system_flask-backend <account-id>.dkr.ecr.eu-north-1.amazonaws.com/flask-backend-rag-aws:latest
### Push the backend image to ECR
    sudo docker push <account-id>.dkr.ecr.eu-north-1.amazonaws.com/flask-backend-rag-aws:latest 
### Tag the Frontend Image to ECR
    sudo docker tag rag-system_streamlit-frontend <account-id>.dkr.ecr.eu-north-1.amazonaws.com/streamlit-frontend-rag-aws:latest 
### Push the frontend image to ECR
    sudo docker push <account-id>.dkr.ecr.eu-north-1.amazonaws.com/streamlit-frontend-rag-aws:latest

## Through AWS Console

1. **Create a Cluster**

2. **Create a new task definition for backend and frontend**

    Each one pointing to the respective repository and image

3. **Create the backend ECS service**

    - Associate the respective task
    - Create a new VPC
    - Create new subnets and associate to the created VPC
    - Create new security group
    - Create a target group to include backend ECS service
    - Create an Application Load Balancer for internal traffic
        - Assign it to the backend service, allowing to have a DNS
        - Assign to the target group previously created
    
4. **Create the frontend ECS service**

    - Associate the respective task
    - Associate to the same VPC, subnets, security group as the backend
    - Create a new target group to include frontend ECS service
    - Create an Application Load Balancer now for public traffic
        - Assign it to the frontend service
        - Assign to the target group previously created

5. **Update the request URL of frontend code with the backend DNS**

    - Create the image again, tag it and push it
    - Create a task revision
    - Deploy and Update the frontend service