# Use a base image with Python
FROM python:3.9

# Set environment variable
ENV RHDH_ENDPOINT="https://rhdh-redhat-developer-hub-rhdh-performance.apps.rhperfcluster.ptjz.p1.openshiftapps.com/"

# Set working directory in the container
WORKDIR /tmp

# Copy requirements.txt and install Python dependencies
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copy the entire project directory into the container
COPY . .

# Command to run your script
CMD ["python", "rhdh_ui_load_perf.py"]
