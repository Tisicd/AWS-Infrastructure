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

# Install Docker and AWS CLI
echo "Installing Docker, AWS CLI and dependencies..."
yum install -y docker jq
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install AWS CLI v2 if not present
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    yum install -y unzip
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

# Associate Elastic IPs with this instance if enabled
# This is MANDATORY - Each microservice must have its own EIP
%{ if enable_elastic_ips == "true" }
echo "Configuring Elastic IP associations for microservices..."

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION="${aws_region}"

# Wait for instance to be fully ready and AWS CLI available
echo "Waiting for instance to be ready..."
sleep 20

# Function to associate EIP by service name with retries
associate_eip_for_service() {
    local SERVICE_NAME=$1
    local EIP_TAG="${eip_tag_name}$SERVICE_NAME"
    
    echo "========================================="
    echo "Associating EIP for service: $SERVICE_NAME"
    echo "Looking for EIP with tag Name=$EIP_TAG..."
    
    # Get EIP allocation ID by tag
    EIP_ALLOCATION_ID=$(aws ec2 describe-addresses \
        --region $REGION \
        --filters "Name=tag:Name,Values=$EIP_TAG" "Name=domain,Values=vpc" \
        --query 'Addresses[0].AllocationId' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$EIP_ALLOCATION_ID" != "None" ] && [ ! -z "$EIP_ALLOCATION_ID" ] && [ "$EIP_ALLOCATION_ID" != "" ]; then
        echo "Found EIP $EIP_ALLOCATION_ID for service $SERVICE_NAME"
        
        # Disassociate EIP from any existing instance (with retries)
        echo "Disassociating EIP from any existing instance..."
        for i in {1..3}; do
            aws ec2 disassociate-address --allocation-id $EIP_ALLOCATION_ID --region $REGION 2>&1 | tee -a /var/log/eip-association.log || true
            sleep 3
        done
        
        # Associate EIP with this instance (with retries)
        echo "Associating EIP $EIP_ALLOCATION_ID with instance $INSTANCE_ID..."
        MAX_RETRIES=5
        RETRY_COUNT=0
        SUCCESS=false
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$SUCCESS" = false ]; do
            if aws ec2 associate-address \
                --instance-id $INSTANCE_ID \
                --allocation-id $EIP_ALLOCATION_ID \
                --region $REGION \
                --allow-reassociation 2>&1 | tee -a /var/log/eip-association.log; then
                echo "EIP successfully associated on attempt $((RETRY_COUNT + 1)) for service $SERVICE_NAME" | tee -a /var/log/eip-association.log
                SUCCESS=true
            else
                RETRY_COUNT=$((RETRY_COUNT + 1))
                echo "EIP association attempt $RETRY_COUNT failed for service $SERVICE_NAME, retrying in 10 seconds..." | tee -a /var/log/eip-association.log
                sleep 10
            fi
        done
        
        if [ "$SUCCESS" = false ]; then
            echo "ERROR: Failed to associate EIP after $MAX_RETRIES attempts for service $SERVICE_NAME" | tee -a /var/log/eip-association.log
        else
            echo "EIP association completed successfully for service $SERVICE_NAME" | tee -a /var/log/eip-association.log
        fi
    else
        echo "WARNING: No EIP found for service $SERVICE_NAME (tag: $EIP_TAG)" | tee -a /var/log/eip-association.log
    fi
}

# Get this instance's position in the ASG to determine which EIP to associate
# We'll use the instance launch index (via ASG tags or instance metadata) to determine assignment
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Get all instance IDs from ASG ordered by launch time to determine index
ASG_NAME=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].Tags[?Key==`aws:autoscaling:groupName`].Value' --output text 2>/dev/null || echo "")

if [ -n "$ASG_NAME" ] && [ "$ASG_NAME" != "None" ]; then
    # Get this instance's index in the ASG (sorted by instance ID for consistency)
    ALL_INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region $REGION \
        --query 'AutoScalingGroups[0].Instances[?HealthStatus==`Healthy` || LifecycleState==`InService`].InstanceId' \
        --output text 2>/dev/null | tr '\t' '\n' | sort)
    
    INSTANCE_INDEX=0
    for ID in $ALL_INSTANCE_IDS; do
        if [ "$ID" = "$INSTANCE_ID" ]; then
            break
        fi
        INSTANCE_INDEX=$((INSTANCE_INDEX + 1))
    done
    
    echo "Instance $INSTANCE_ID is at index $INSTANCE_INDEX in ASG $ASG_NAME"
    
    # Get list of service names in order
    SERVICES_ARRAY=($(echo '${services}' | jq -r '.[].name'))
    TOTAL_SERVICES=$${#SERVICES_ARRAY[@]}
    
    if [ $$TOTAL_SERVICES -gt 0 ]; then
        # Associate EIP based on instance index (modulo to handle multiple instances)
        SERVICE_INDEX=$$((INSTANCE_INDEX % TOTAL_SERVICES))
        ASSIGNED_SERVICE=$${SERVICES_ARRAY[$$SERVICE_INDEX]}
        
        echo "Assigning EIP for service: $$ASSIGNED_SERVICE (service index: $$SERVICE_INDEX)"
        associate_eip_for_service "$$ASSIGNED_SERVICE"
    else
        echo "No services found in configuration"
    fi
else
    # Fallback: if we can't determine ASG, associate first service's EIP
    echo "Could not determine ASG name, associating first service EIP as fallback"
    FIRST_SERVICE=$(echo '${services}' | jq -r '.[0].name')
    if [ -n "$FIRST_SERVICE" ] && [ "$FIRST_SERVICE" != "null" ]; then
        associate_eip_for_service "$FIRST_SERVICE"
    fi
fi

# Wait for IP associations to propagate
sleep 10
echo "Elastic IP association process completed"
%{ endif }

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
  $$NAME:
    image: ${docker_registry}/$$IMAGE
    container_name: $$NAME
    restart: always
    ports:
      - "$$PORT:$$PORT"
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

