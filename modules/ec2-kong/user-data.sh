#!/bin/bash

# =============================================================================
# Kong API Gateway Initialization Script
# =============================================================================

# Enable error logging
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

set -x  # Enable debug mode
echo "Starting Kong Gateway initialization at $(date)"

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI..."
    yum install -y aws-cli
fi

# Associate Elastic IP if provided (for ASG instances)
# This is MANDATORY - EIP must always be associated
%{ if associate_eip == "true" && eip_allocation_id != "" }
echo "Starting EIP association process..."
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

echo "Instance ID: $INSTANCE_ID"
echo "EIP Allocation ID: ${eip_allocation_id}"
echo "Region: $REGION"

# Wait for instance to be fully ready and AWS CLI available
echo "Waiting for instance to be ready..."
sleep 15

# Disassociate EIP from any existing instance (with retries)
echo "Disassociating EIP from any existing instance..."
for i in {1..3}; do
    aws ec2 disassociate-address --allocation-id ${eip_allocation_id} --region $REGION 2>&1 | tee -a /var/log/eip-association.log || true
    sleep 5
done

# Associate EIP with this instance (with retries)
echo "Associating EIP with instance..."
MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$SUCCESS" = false ]; do
    if aws ec2 associate-address \
        --instance-id $INSTANCE_ID \
        --allocation-id ${eip_allocation_id} \
        --region $REGION \
        --allow-reassociation 2>&1 | tee -a /var/log/eip-association.log; then
        echo "EIP successfully associated on attempt $((RETRY_COUNT + 1))" | tee -a /var/log/eip-association.log
        SUCCESS=true
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "EIP association attempt $RETRY_COUNT failed, retrying in 10 seconds..." | tee -a /var/log/eip-association.log
        sleep 10
    fi
done

if [ "$SUCCESS" = false ]; then
    echo "ERROR: Failed to associate EIP after $MAX_RETRIES attempts" | tee -a /var/log/eip-association.log
else
    echo "EIP association completed successfully" | tee -a /var/log/eip-association.log
    # Wait a moment for IP association to propagate
    sleep 5
fi
%{ endif }

# Update system
echo "Updating system packages..."
yum update -y

# Install Docker
echo "Installing Docker..."
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose
echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Wait for database to be ready
sleep 60

# Create Kong configuration
cat > /opt/kong-compose.yml <<'EOF'
version: '3.8'

services:
  kong:
    image: kong:${kong_version}-alpine
    container_name: kong
    restart: always
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: %{ if kong_database_host != "" }${kong_database_host}%{ else }localhost%{ endif }
      KONG_PG_PORT: ${kong_database_port}
      KONG_PG_USER: postgres
      KONG_PG_PASSWORD: $${KONG_PG_PASSWORD:-postgres_password_change_me}
      KONG_PG_DATABASE: ${kong_database_name}
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001, 0.0.0.0:8444 ssl
    ports:
      - "80:8000"
      - "443:8443"
      - "8001:8001"
      - "8444:8444"
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 10s
      retries: 10
EOF

# Run Kong migrations
docker run --rm \
  -e KONG_DATABASE=postgres \
  -e KONG_PG_HOST=%{ if kong_database_host != "" }${kong_database_host}%{ else }localhost%{ endif } \
  -e KONG_PG_PORT=${kong_database_port} \
  -e KONG_PG_USER=postgres \
  -e KONG_PG_PASSWORD=postgres_password_change_me \
  -e KONG_PG_DATABASE=${kong_database_name} \
  kong:${kong_version}-alpine kong migrations bootstrap || true

# Start Kong
cd /opt
docker-compose -f kong-compose.yml up -d

# Wait for Kong to be ready
sleep 30

# Configure Kong health endpoint
curl -i -X POST http://localhost:8001/services \
  --data name=health-check \
  --data url=http://localhost:8001/status || true

curl -i -X POST http://localhost:8001/services/health-check/routes \
  --data paths[]=/status || true

cat > /etc/motd <<WELCOME
================================================
Academic Platform - Kong API Gateway
Environment: ${environment}
Instance: ${instance_index}
------------------------------------------------
Proxy: http://$$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
Admin API: http://$$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8001
================================================
WELCOME

echo "Kong API Gateway initialization complete!"

