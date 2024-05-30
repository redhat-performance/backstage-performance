# Use the official Playwright image as the base image
FROM mcr.microsoft.com/playwright/python:v1.43.0-jammy

# Set working directory in the container
WORKDIR /app

# Copy the entire project directory into the container
COPY . .

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# Run the script and inspect network interfaces
CMD ["bash", "-c", "./rhdh_ui_load_perf.py && cat /proc/net/dev"]
