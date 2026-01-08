#!/bin/bash

# =============================================================================
# Microservices ASG Initialization Script
# =============================================================================

# Enable error logging
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

set -x  # Enable debug mode
echo "Starting microservices initialization at $(date)"

# Update system
echo "Updating system packages..."
yum update -y

# Install Docker
echo "Installing Docker and dependencies..."
yum install -y docker jq
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose
echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Docker login if registry provided
%{ if docker_registry != "" && docker_username != "" }
echo "${docker_password}" | docker login ${docker_registry} -u ${docker_username} --password-stdin
%{ endif }

# Create services directory
mkdir -p /opt/services

# Parse services JSON and create docker-compose
cat > /opt/services/docker-compose.yml <<'EOF'
version: '3.8'
services:
EOF

# Add each service
echo '${services}' | jq -r '.[] | @json' | while read service; do
  NAME=$(echo $service | jq -r '.name')
  IMAGE=$(echo $service | jq -r '.image')
  PORT=$(echo $service | jq -r '.port')
  
  cat >> /opt/services/docker-compose.yml <<SERVICEEOF
  $NAME:
    image: ${docker_registry}/$IMAGE
    container_name: $NAME
    restart: always
    ports:
      - "$PORT:$PORT"
    environment:
      - NODE_ENV=${environment}
      - DB_HOST=${database_host}
      - REDIS_HOST=${redis_host}
      - KONG_ENDPOINT=${kong_endpoint}
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:$PORT/api/v1/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3

SERVICEEOF
done

# Pull images and start services
cd /opt/services
docker-compose pull
docker-compose up -d

cat > /etc/motd <<WELCOME
================================================
Academic Platform - Microservices
Environment: ${environment}
================================================
WELCOME

echo "Microservices initialization complete!"

