#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# Install required packages
yum update -y
yum install -y amazon-efs-utils

# Configure kubelet
/etc/eks/bootstrap.sh ${cluster_name}

# Install SSM agent
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent


