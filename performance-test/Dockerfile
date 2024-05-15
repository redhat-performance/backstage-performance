# Use a base image with Ubuntu
FROM ubuntu:20.04

# Set environment variable
ENV RHDH_ENDPOINT="https://rhdh-redhat-developer-hub-rhdh-performance.apps.rhperfcluster.ptjz.p1.openshiftapps.com/"

# Set working directory in the container
WORKDIR /tmp

# Install system dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements.txt and install Python dependencies
COPY requirements.txt .
RUN pip3 install -r requirements.txt
RUN playwright install
RUN playwright install-deps

# Copy the entire project directory into the container
COPY . .

