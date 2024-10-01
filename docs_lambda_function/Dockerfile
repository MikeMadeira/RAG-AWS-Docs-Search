# Use an official Python runtime as a base image
FROM python:3.9-slim

# Set the working directory in the container
WORKDIR /app

# Copy the current directory contents into the container
COPY . /app

# Install the required dependencies
RUN pip install --no-cache-dir boto3 faiss-cpu sentence-transformers numpy

# Set environment variables (if needed)
ENV AWS_REGION=eu-north-1

# Specify the command to run your script
CMD ["python", "processing_service.py"]