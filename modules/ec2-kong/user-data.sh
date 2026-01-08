#!/bin/bash

# =============================================================================
# Kong API Gateway Initialization Script
# =============================================================================

# Enable error logging
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

set -x  # Enable debug mode
echo "Starting Kong Gateway initialization at $(date)"

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
      KONG_PG_HOST: ${kong_database_host}
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
  -e KONG_PG_HOST=${kong_database_host} \
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

