#!/bin/bash
# Bastion Host User Data Script
# This script initializes the Bastion Host instance

set -e

ENVIRONMENT="${environment}"
EIP_ALLOCATION_ID="${eip_allocation_id}"
ASSOCIATE_EIP="${associate_eip}"

# Update system
yum update -y

# Install useful tools
yum install -y htop tmux vim git aws-cli

# Configure SSH
echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
systemctl restart sshd

# Associate Elastic IP if ASG is enabled
# This is MANDATORY - EIP must always be associated
if [ "$ASSOCIATE_EIP" = "true" ] && [ -n "$EIP_ALLOCATION_ID" ]; then
    echo "Starting EIP association process..."
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    
    echo "Instance ID: $INSTANCE_ID"
    echo "EIP Allocation ID: $EIP_ALLOCATION_ID"
    echo "Region: $REGION"
    
    # Wait for AWS CLI to be ready and instance to be fully initialized
    echo "Waiting for instance to be ready..."
    sleep 15
    
    # Disassociate EIP from any existing instance (with retries)
    echo "Disassociating EIP from any existing instance..."
    for i in {1..3}; do
        aws ec2 disassociate-address --allocation-id "$EIP_ALLOCATION_ID" --region "$REGION" 2>&1 | tee -a /var/log/eip-association.log || true
        sleep 5
    done
    
    # Associate EIP with this instance (with retries)
    echo "Associating EIP with instance..."
    MAX_RETRIES=5
    RETRY_COUNT=0
    SUCCESS=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$SUCCESS" = false ]; do
        if aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$EIP_ALLOCATION_ID" --region "$REGION" --allow-reassociation 2>&1 | tee -a /var/log/eip-association.log; then
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
    fi
elif [ -z "$EIP_ALLOCATION_ID" ]; then
    echo "WARNING: EIP_ALLOCATION_ID is empty, skipping EIP association" | tee -a /var/log/eip-association.log
fi

# Create welcome message
cat > /etc/motd <<WELCOME
================================================
Academic Platform - Bastion Host
Environment: $ENVIRONMENT
================================================
WELCOME

# Log completion
echo "Bastion host initialization completed at $(date)" >> /var/log/user-data.log
