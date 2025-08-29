# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory in the container
WORKDIR /app

# Copy the dependencies file to the working directory
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir --trusted-host pypi.python.org -r requirements.txt

# Copy the rest of the application code to the working directory
COPY . .

# Make port 8080 available to the world outside this container
EXPOSE 8080

# Define environment variables that will be passed by Cloud Run
ENV PORT=8080
ENV GCP_PROJECT_ID="" 

# Run the ADK server when the container launches. This replaces the gunicorn command.
CMD ["adk", "serve", "--host", "0.0.0.0", "--port", "8080"]
