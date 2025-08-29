import socket
from google.cloud import storage
from vertexai.preview.generative_models import GenerativeModel
from google.cloud import adk # Import the ADK library

@adk.tool(
    name="summarize_gcs_file",
    description="Reads a text file from a given Google Cloud Storage URI (e.g., gs://bucket/file.txt) and returns a summary of its content. Also returns the full content for context."
)
def summarize_gcs_file(gcs_uri: str) -> str:
    """
    This tool reads a file from GCS. In the vulnerable scenario, the file's
    content contains a hidden instruction that the agent will see.
    """
    client = storage.Client()
    try:
        # Parse the GCS URI to get bucket and file name
        if not gcs_uri.startswith("gs://"):
            return "Error: Invalid GCS URI. It must start with gs://"
        parts = gcs_uri.replace("gs://", "").split("/", 1)
        bucket_name = parts[0]
        object_name = parts[1]

        bucket = client.bucket(bucket_name)
        blob = bucket.blob(object_name)
        
        print(f"Reading from gs://{bucket_name}/{object_name}")
        original_content = blob.download_as_text()
    except Exception as e:
        return f"Error: Could not read from GCS URI {gcs_uri}: {e}"

    # Use Vertex AI Gemini to summarize the content
    model = GenerativeModel("gemini-pro")
    prompt = f"Please summarize the following document in one or two sentences:\n\n{original_content}"
    response = model.generate_content(prompt)
    
    # CRITICAL FOR THE LAB: The agent's memory will now contain the original text.
    # This is how the hidden prompt gets into the agent's context.
    return f"Summary: {response.text.strip()}\n\nFull Content Processed: '{original_content[:200]}...'"


@adk.tool(
    name="perform_dns_lookup",
    description="For security validation ONLY. Performs a DNS lookup for a given domain name."
)
def perform_dns_lookup(domain: str) -> str:
    """
    This is the tool that the agent will be tricked into abusing for data exfiltration.
    """
    print(f"Performing DNS lookup for: {domain}")
    try:
        ip_address = socket.gethostbyname(domain)
        return f"Successfully resolved {domain} to {ip_address}"
    except socket.gaierror:
        # This error is expected when our security controls are working.
        return f"Error: Could not resolve domain '{domain}'. It may not exist or network access is blocked."
