from dotenv import load_dotenv
import os
import boto3
import sys

# Load environment variables from .env file
load_dotenv()

# Fetch AWS credentials from the .env file
AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")
AWS_REGION = os.getenv("AWS_REGION")

# Initialize the S3 client with the credentials
s3 = boto3.client(
    's3',
    aws_access_key_id=AWS_ACCESS_KEY_ID,
    aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    region_name=AWS_REGION
)

def upload_files_in_directory_to_s3(directory_path, bucket_name, subfolder=""):
    """Uploads all files in a directory to an S3 bucket under a subfolder."""
    try:
        for filename in os.listdir(directory_path):
            file_path = os.path.join(directory_path, filename)
            if os.path.isfile(file_path):  # Only upload files, not subdirectories
                # Add subfolder to the S3 key
                s3_key = f"{subfolder}/{os.path.basename(file_path)}" if subfolder else os.path.basename(file_path)
                s3.upload_file(file_path, bucket_name, s3_key)
                print(f"File {file_path} uploaded successfully to {bucket_name}/{s3_key}.")
    except Exception as e:
        print(f"Error uploading file: {e}")

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Usage: python upload_to_s3.py <directory_path> <bucket_name> <subfolder>")
        sys.exit(1)
    
    directory_path = sys.argv[1]
    bucket_name = sys.argv[2]
    subfolder = sys.argv[3]  # Optional: specify the subfolder

    # Upload all files in the directory to S3
    upload_files_in_directory_to_s3(directory_path, bucket_name, subfolder)
