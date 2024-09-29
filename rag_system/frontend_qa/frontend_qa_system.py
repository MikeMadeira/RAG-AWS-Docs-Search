import streamlit as st
import requests
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

# Streamlit App for Q&A
st.title("Document Search and Q&A System")

# User input for the search query
query = st.text_input("Enter your search query:")

# Backend API URL
# backend_api_url = "http://flask-backend:5000/query"  # Backend Flask API locally
backend_api_url = "http://rag-aws-alb-backend-1015498497.eu-north-1.elb.amazonaws.com:5000/query" # Backend Flask on AWS

if query:
    logger.info(f"User query: {query}")
    try:
        # Make a request to the backend Flask API
        response = requests.post(backend_api_url, json={"query": query})
        logger.info(f"Request sent to backend: {backend_api_url}")

        if response.status_code == 200:
            answer = response.json().get('answer')
            source_files = response.json().get('source_files')
            logger.info(f"Response received: {response.json()}")

            st.subheader(f"Answer to: {query}")
            st.write(answer)
            if len(source_files) > 0:
                st.subheader(f"Read more on the files below:")
                st.write(source_files)
        else:
            logger.error(f"Error: Could not retrieve the answer. Status code: {response.status_code}")
            st.write("Error: Could not retrieve the answer.")
    except Exception as e:
        logger.exception("Exception occurred during request processing")
        st.write("An error occurred while processing your request.")
