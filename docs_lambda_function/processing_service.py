import os
import re
import numpy as np
import boto3
import faiss
import pickle
import logging

# Set Hugging Face cache-related directories to /tmp
os.environ['TRANSFORMERS_CACHE'] = '/tmp'
os.environ['HF_HOME'] = '/tmp'
os.environ['HF_DATASETS_CACHE'] = '/tmp'
os.environ['HF_MODULES_CACHE'] = '/tmp'
os.environ['HF_METRICS_CACHE'] = '/tmp'

from sentence_transformers import SentenceTransformer

AWS_REGION = 'eu-north-1'

# Initialize the S3 client (AWS Lambda automatically handles the credentials)
s3 = boto3.client('s3')

# Initialize the DynamoDB resource
dynamodb = boto3.resource(
    'dynamodb',
    region_name=AWS_REGION
)
table = dynamodb.Table('aws_test_docs_chunks')  # Use your DynamoDB table name

# Load Sentence Transformer Model
model = SentenceTransformer('all-MiniLM-L6-v2')

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 1. Download file from S3
def download_file_from_s3(bucket_name, file_key, local_path='/tmp/downloaded_document.txt'):
    """Download a file from S3 and save it locally in the /tmp directory."""
    s3.download_file(bucket_name, file_key, local_path)
    with open(local_path, 'r') as file:
        return file.read()

# 2. Text Pre-processing (clean, chunk, and generate embeddings)
def clean_text(text):
    """Cleans the input text by removing unnecessary characters."""
    text = re.sub(r'\s+', ' ', text)  # Remove extra spaces and newlines
    return text.strip()

def chunk_text(text, chunk_size=200, overlap=50):
    """Split the text into chunks."""
    cleaned_text = clean_text(text)
    words = cleaned_text.split()
    chunks = []
    i = 0
    while i < len(words):
        chunk = words[i:i + chunk_size]
        chunks.append(' '.join(chunk))  # Return only the chunk
        i += chunk_size - overlap
    return chunks

# Embeddings generation batched to allow the preprocess to end in production
def generate_embeddings(chunks, batch_size=2):
    """Generate embeddings for each chunk in smaller batches."""
    embeddings = []
    for i in range(0, len(chunks), batch_size):
        batch_chunks = chunks[i:i + batch_size]
        batch_embeddings = model.encode(batch_chunks, convert_to_tensor=False)
        embeddings.extend(batch_embeddings)
    return embeddings

# 3. Saving Chunks and FAISS Indices to DynamoDB
def save_chunks_and_faiss_indices_to_db(file_key, chunks, embeddings, faiss_index):
    """Save each chunk, its corresponding embedding, and FAISS index to DynamoDB."""
    for i, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
        unique_id = f'{file_key}_{i}'  # Create unique id by concatenating file_key and chunk index
        table.put_item(
            Item={
                'id': unique_id,  # Unique primary key
                'file_key': file_key,  # The original file the chunk came from
                'faiss_index': int(faiss_index),  # FAISS index
                'chunk': chunk,  # Text chunk
                'embedding': pickle.dumps(embedding)  # Serialized embedding
            }
        )
        faiss_index += 1  # Increment FAISS index
    logger.info(f"Chunks, embeddings, and FAISS indices for {file_key} saved to DynamoDB.")
    return faiss_index  # Return the updated FAISS index

# 4. FAISS Index Creation
def create_faiss_index(embeddings):
    """Create or update the FAISS index with new embeddings."""
    embeddings_np = np.array(embeddings)
    dimension = embeddings_np.shape[1]
    index = faiss.IndexFlatL2(dimension)
    index.add(embeddings_np)
    
    logger.info("FAISS index created.")
    return index

# 5. Save FAISS Index to S3
def save_faiss_index_to_s3(faiss_index, s3_bucket, s3_key):
    """Save the FAISS index to S3."""
    local_index_path = '/tmp/faiss_index.index'  # Save in /tmp directory
    faiss.write_index(faiss_index, local_index_path)  # Save to /tmp directory first
    s3.upload_file(local_index_path, s3_bucket, s3_key)
    logger.info(f"FAISS index saved to S3 at {s3_bucket}/{s3_key}.")


def process_all_files_in_s3_folder(bucket_name, folder_name, s3_index_bucket, s3_index_key):
    """Download, process, and save all files from a specific S3 folder, and update the FAISS index."""
    response = s3.list_objects_v2(Bucket=bucket_name, Prefix=folder_name)
    all_embeddings = []
    faiss_index = 0  # Initialize the FAISS index counter
    
    for obj in response.get('Contents', []):
        file_key = obj['Key']  # The file path in S3
        
        # Step 1: Download file from S3
        text = download_file_from_s3(bucket_name, file_key)
        
        # Step 2: Clean and chunk the text
        chunks = chunk_text(text)
        logger.info(f"File: {file_key} - Number of chunks: {len(chunks)}")  # Log the number of chunks
        
        if len(chunks) == 0:
            logger.error(f"No chunks generated for {file_key}. Skipping this file.")
            continue
        
        # Step 3: Generate embeddings
        logger.info(f"Starting embedding generation for file: {file_key}")
        embeddings = generate_embeddings(chunks)
        logger.info(f"Embeddings generated for file: {file_key} - Number of embeddings: {len(embeddings)}")

        if len(embeddings) == 0:
            logger.error(f"No embeddings generated for {file_key}. Skipping this file.")
            continue
        
        # Collect embeddings for FAISS index creation
        all_embeddings.append(embeddings)
        
        # Step 4: Save chunks, embeddings, and FAISS indices to DynamoDB
        save_chunks_and_faiss_indices_to_db(file_key, chunks, embeddings, faiss_index)
    
    if not all_embeddings:
        logger.error("No valid embeddings found for any file. Skipping FAISS index creation.")
        return

    # Combine all embeddings from all files
    try:
        all_embeddings_np = np.vstack(all_embeddings)  # Stack embeddings into a single numpy array
        logger.info(f"Combined embeddings shape: {all_embeddings_np.shape}")
    except ValueError as e:
        logger.error(f"Error combining embeddings: {e}")
        return

    # Step 5: Create FAISS index and save it to S3
    faiss_index = create_faiss_index(all_embeddings_np)
    save_faiss_index_to_s3(faiss_index, s3_index_bucket, s3_index_key)


# Example usage
if __name__ == '__main__':
    bucket_name = 'aws-test-docs-loka'  # Your S3 bucket name
    folder_name = 'sagemaker_documentation/'  # Folder within the S3 bucket
    s3_index_bucket = 'aws-test-docs-loka'  # The S3 bucket where FAISS index will be saved
    s3_index_key = 'faiss_index.index'  # S3 key for FAISS index

    process_all_files_in_s3_folder(bucket_name, folder_name, s3_index_bucket, s3_index_key)
