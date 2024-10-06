from flask import Flask, request, jsonify
from flask_cors import CORS
from sentence_transformers import SentenceTransformer
from dotenv import load_dotenv
from openai import OpenAI

import faiss
import boto3
import pickle
import os
import traceback
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,  # You can adjust this level to DEBUG for more verbosity
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()  # Log to console
    ]
)

logger = logging.getLogger(__name__)  # Get a logger instance for this module

# Load environment variables from .env file
load_dotenv()

# Fetch AWS credentials from the .env file
AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")
AWS_REGION = os.getenv("AWS_REGION")
BUCKET_NAME = os.getenv("BUCKET_NAME")
TABLE_NAME = os.getenv("TABLE_NAME")

# Initialize the S3 client with the credentials
s3 = boto3.client(
    's3',
    aws_access_key_id=AWS_ACCESS_KEY_ID,
    aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    region_name=AWS_REGION
)

# Initialize the DynamoDB resource with the credentials
dynamodb = boto3.resource(
    'dynamodb',
    region_name=AWS_REGION,
    aws_access_key_id=AWS_ACCESS_KEY_ID,
    aws_secret_access_key=AWS_SECRET_ACCESS_KEY
)
table = dynamodb.Table(TABLE_NAME)  # Use your DynamoDB table name

# Load Sentence Transformer Model
model = SentenceTransformer('all-MiniLM-L6-v2')

# Set your OpenAI API key
os.environ['OPENAI_API_KEY'] = os.getenv('OPENAI_API_KEY')
client = OpenAI()

# Load FAISS index from S3
def load_faiss_index_from_s3(s3_bucket, s3_key, local_index_file='faiss_index.index'):
    """Download FAISS index from S3 and load it locally."""
    s3.download_file(s3_bucket, s3_key, local_index_file)
    faiss_index = faiss.read_index(local_index_file)
    return faiss_index

# Retrieve Chunks and File Keys from DynamoDB
def retrieve_chunks_from_db(query_embedding, faiss_index, top_k=5):
    """Retrieve the top-k most similar chunks and their source file keys from DynamoDB using FAISS."""
    distances, indices = faiss_index.search(query_embedding, top_k)
    logger.info(f"Distances: {distances}")
    logger.info(f"Indices: {indices}")

    results = []
    source_files = []

    for idx in indices[0]:  # Loop through the top-k indices returned by FAISS
        try:
            # Convert FAISS index from numpy.int64 to Python int
            idx = int(idx)
            
            response = table.query(
                IndexName='faiss_index_gsi',  # Use the GSI for faiss_index
                KeyConditionExpression=boto3.dynamodb.conditions.Key('faiss_index').eq(idx)
            )
            logger.info(f"Table item: {response}")
            # Check if any items were returned
            if 'Items' in response and response['Items']:
                logger.info(f"Response Item: {response['Items'][0]}")
                chunk = response['Items'][0]['chunk']
                file_key = response['Items'][0]['file_key']  # Retrieve the associated file key
                
                # Append the chunk and file key to the results
                results.append(chunk)
                source_files.append(file_key)
                
                logger.info(f"Chunk: {chunk}")
                logger.info(f"File key: {file_key}")
                logger.info(f"The chunk with the FAISS index '{idx}' added to the results.")
            else:
                logger.info(f"No item found for FAISS index: {idx}")
        except Exception as e:
            logger.error(f"Error retrieving chunk for index {idx}: {str(e)}")
    
    return results, source_files

# Mock Answer Generation (replace with actual LLM logic)
def generate_mock_answer(query, chunks):
    """Mock answer generation by concatenating the retrieved chunks."""
    context = "\n".join(chunks)
    return f"Answer based on context: {context}"

# Generate Answer using LLM
def generate_answer(query, retrieved_chunks):
    """Generate an answer using an LLM based on the query and retrieved chunks."""
    context = "\n".join(retrieved_chunks)  # Combine all chunks into a single context
    
    # Create the prompt for the LLM
    prompt = f"Answer the following question based on the provided context:\n\nContext:\n{context}\n\nQuestion: {query}\nAnswer:"
    
    # Send the prompt to the LLM (using OpenAI's GPT)
    response = client.chat.completions.create(
        model='gpt-4o-mini',
        messages=[{"role": 'system', "content": 'You are a helpful assistant.'}, 
                  {"role": 'user', "content": prompt}],
    )
    
    logger.info(f"Response from the LLM:\n{response}")
    # Extract the answer from the response
    answer = response.choices[0].message.content
    
    return answer

# Flask App Setup
app = Flask(__name__)

# Enable CORS for all routes
CORS(app)

@app.route('/', methods=['GET'])
def root():
    return "This is the backend root.", 200

@app.route('/query', methods=['POST'])
def handle_query():
    data = request.get_json()
    query = data.get('query')
    logger.info("User's Query:", query)
    try:
        # Embed the query
        query_embedding = model.encode([query])

        # Load FAISS index from S3
        s3_index_bucket = BUCKET_NAME
        s3_index_key = 'faiss/faiss_index.index'
        faiss_index = load_faiss_index_from_s3(s3_index_bucket, s3_index_key)

        # Retrieve chunks and file keys from DynamoDB
        retrieved_chunks, source_files = retrieve_chunks_from_db(query_embedding, faiss_index)

        # Generate answer
        answer = generate_answer(query, retrieved_chunks)
        logger.info("Answer:", answer)

        # Return answer along with the file sources
        return jsonify({
            'answer': answer,
            'source_files': source_files  # Include the file names in the response
        }), 200

    except Exception as e:
        logger.info("Error occurred:", str(e))
        logger.info(traceback.format_exc())
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
