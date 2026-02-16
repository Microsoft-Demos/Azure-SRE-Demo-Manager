FROM python:3.11-slim

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY berlin_mcp_server.py .

# Expose port for health checks
EXPOSE 8080

# Run the FastAPI server for health checks
CMD ["python", "berlin_mcp_server.py"]
