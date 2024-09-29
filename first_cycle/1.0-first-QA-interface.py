import os
import streamlit as st
from sentence_transformers import SentenceTransformer
import faiss
import numpy as np

from util import *
from openai import OpenAI
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Initialize the model and FAISS index
model = SentenceTransformer('all-MiniLM-L6-v2')
faiss_index = load_faiss_index('faiss_index_file.index')  # Load or create the FAISS index with your embeddings
chunks = load_chunks('chunks_file.pkl')  # List of chunks you have already processed

# Set your OpenAI API key
os.environ['OPENAI_API_KEY'] = os.getenv('OPENAI_API_KEY')
client = OpenAI()

def search_query(query, model, index, chunks, top_k=5):
    """Searches for the most relevant chunks based on the input query."""
    # Embed the query
    query_embedding = model.encode([query], convert_to_tensor=False)
    
    # Search in the FAISS index for the most similar chunks
    distances, indices = index.search(np.array(query_embedding), top_k)
    
    # Retrieve the top-k chunks
    results = []
    for idx in indices[0]:
        results.append(chunks[idx])  # Get the chunk text
    
    return results

def generate_answer(query, retrieved_chunks):
    """Generate an answer using an LLM based on the query and retrieved chunks."""
    context = "\n".join(retrieved_chunks)  # Combine all chunks into a single context
    
    # Create the prompt for the LLM
    prompt = f"Answer the following question based on the provided context:\n\nContext:\n{context}\n\nQuestion: {query}\nAnswer:"
    
    # Send the prompt to the LLM (using OpenAI's GPT)
    response = client.chat.completions.create(
        model='gpt-4o-mini',
        messages=[{"role": 'system', "content": 'You are an helpful assistant.'}, 
                  {"role": 'user', "content": prompt}],
    )
    
    print(f"Response from the LLM:\n{response}")
    # Extract the answer from the response
    answer = response.choices[0].message.content
    
    return answer

# Streamlit App
st.title("Document Search and Q&A System")

# User input
query = st.text_input("Enter your search query:")

# If a query is entered
if query:
    # Perform search
    results = search_query(query, model, faiss_index, chunks)
    
    # Display the retrieved chunks
    st.subheader(f"Top {len(results)} relevant chunks for: {query}")
    for i, result in enumerate(results):
        st.write(f"**Chunk {i+1}:**")
        st.write(result)
        st.write("="*40)
    
    # Generate an answer using the retrieved chunks
    if results:
        answer = generate_answer(query, results)
        st.subheader(f"Answer to: {query}")
        st.write(answer)