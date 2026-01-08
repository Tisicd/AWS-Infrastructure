# AWS Infrastructure - Terraform

Complete infrastructure as code for the Academic Platform, optimized for AWS Academy accounts with EIP limitations.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [AWS Account Setup](#aws-account-setup)
- [GitHub Actions Configuration](#github-actions-configuration)
- [EIP Management](#eip-management)
- [Environments](#environments)
- [Modules](#modules)
- [Troubleshooting](#troubleshooting)

## 🎯 Prerequisites

- **Terraform** >= 1.6.0
- **AWS CLI** >= 2.0
- **AWS Academy Account** (or regular AWS account)
- **GitHub Repository** with Actions enabled
- **Existing VPC** (for AWS Academy accounts)

## 🚀 Quick Start

### 1. Configure AWS Credentials

For AWS Academy accounts, use your credentials from the AWS Details page:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_SESSION_TOKEN="your-session-token"  # Required for AWS Academy
export AWS_REGION="us-east-1"
```

### 2. Identify Your VPC and Subnets

```bash
# List VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table

# List Subnets
aws ec2 describe-subnets --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch,Tags[?Key==`Name`].Value|[0]]' --output table

# Check current EIP usage
aws ec2 describe-addresses --query 'length(Addresses)'
```

### 3. Configure Environment Variables

Edit the appropriate tfvars file:

```bash
# For dev environment
cd environments/dev
nano terraform.tfvars
```

**Required values:**
```hcl
existing_vpc_id             = "vpc-xxxxxxxxxxxxx"
existing_public_subnet_ids  = ["subnet-xxxxxxxxx", "subnet-yyyyyyyyy"]
existing_private_subnet_ids = ["subnet-zzzzzzzzz", "subnet-wwwwwwwww"]
```

### 4. Initialize and Deploy

```bash
cd infrastructure/terraform

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file="environments/dev/terraform.tfvars"

# Apply (if plan looks good)
terraform apply -var-file="environments/dev/terraform.tfvars"
```

## 🔐 AWS Account Setup

### For AWS Academy Accounts

1. **Start Lab** in AWS Academy Learner Lab
2. **Copy Credentials** from AWS Details
3. **Set Environment Variables** (expires every 4 hours)
4. **Identify VPC Resources** (pre-created in AWS Academy)

### For Regular AWS Accounts

Use IAM users or OIDC federation (GitHub Actions).

## 🔧 GitHub Actions Configuration

### Step 1: Configure GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

#### For Each Environment (DEV, QA, PROD):

**VPC Configuration:**
```
USE_EXISTING_VPC_DEV=true
VPC_ID_DEV=vpc-xxxxxxxxxxxxx
PUBLIC_SUBNET_IDS_DEV=["subnet-xxx","subnet-yyy"]
PRIVATE_SUBNET_IDS_DEV=["subnet-zzz","subnet-www"]
```

**AWS Credentials (Academy):**
```
AWS_ACCESS_KEY_ID_DEV=your-access-key
AWS_SECRET_ACCESS_KEY_DEV=your-secret-key
AWS_SESSION_TOKEN_DEV=your-session-token
```

**OR AWS Role ARN (OIDC - Recommended for Production):**
```
AWS_ROLE_ARN_DEV=arn:aws:iam::123456789012:role/GitHubActionsRole
AWS_ROLE_ARN_QA=arn:aws:iam::123456789012:role/GitHubActionsRole
AWS_ROLE_ARN_PROD=arn:aws:iam::987654321098:role/GitHubActionsRole
```

### Step 2: Enable GitHub Actions

The workflow file `.github/workflows/terraform-deploy.yml` is already configured and will automatically run on:

- **Push to main** → Deploy to PROD
- **Push to qa** → Deploy to QA
- **Push to dev** → Deploy to DEV
- **Pull Request** → Run plan only
- **Manual Dispatch** → Choose environment and action

## 🌐 EIP Management

### AWS Academy Limit: **5 Elastic IPs**

This infrastructure is designed to work within this constraint:

| Resource          | EIPs Used | Notes                               |
|-------------------|-----------|-------------------------------------|
| NAT Gateway(s)    | 1-2       | Configurable via `nat_gateway_count`|
| API Gateway (ALB) | 0         | Uses default AWS DNS               |
| Bastion Host      | 0-1       | Optional, not included by default  |
| **Total**         | 1-3       | **Within 5 EIP limit** ✅           |

### EIP Optimization Strategies

#### Development (1 EIP):
```hcl
nat_gateway_count  = 1
single_nat_gateway = true
api_gateway_requires_eip = false
```

#### QA (2 EIPs):
```hcl
nat_gateway_count  = 2
single_nat_gateway = false
api_gateway_requires_eip = false
```

#### Production (2-3 EIPs):
```hcl
nat_gateway_count  = 2
single_nat_gateway = false
api_gateway_requires_eip = false  # Or true if needed
```

### Check EIP Usage

```bash
# Current usage
aws ec2 describe-addresses --query 'length(Addresses)'

# After Terraform apply
terraform output eips_used_count
terraform output eips_remaining
```

## 🌍 Environments

### Development (`dev`)
- Minimal resources
- 1 NAT Gateway
- Single-AZ databases
- No Container Insights
- Auto-scaling disabled

### QA (`qa`)
- Medium resources
- 2 NAT Gateways
- Multi-AZ option
- Container Insights enabled
- Auto-scaling enabled

### Production (`prod`)
- High-availability
- 2 NAT Gateways
- Multi-AZ databases
- Container Insights enabled
- Aggressive auto-scaling
- Enhanced monitoring

## 📦 Modules

### Core Modules

| Module           | Purpose                              | EIPs Used |
|------------------|--------------------------------------|-----------|
| `networking`     | VPC, Subnets, NAT Gateway, IGW       | 1-2       |
| `security-groups`| Security groups for all services     | 0         |
| `iam`            | IAM roles and policies               | 0         |
| `secrets-manager`| Secrets management                   | 0         |
| `rds`            | PostgreSQL database                  | 0         |
| `elasticache`    | Redis cache                          | 0         |
| `ecs`            | ECS Fargate cluster and services     | 0         |
| `api-gateway`    | Application Load Balancer            | 0-1       |
| `monitoring`     | CloudWatch logs, alarms, SNS         | 0         |

### Module Usage

All modules are called from `main.tf` and can be enabled/disabled via variables:

```hcl
enable_rds = true
enable_elasticache = true
enable_ecs = true
enable_api_gateway = true
```

## 🐛 Troubleshooting

### Error: AddressLimitExceeded

```
Error: Error allocating EIP: AddressLimitExceeded
```

**Solution:** Reduce `nat_gateway_count` or release unused EIPs:

```bash
# List all EIPs
aws ec2 describe-addresses

# Release unassociated EIP
aws ec2 release-address --allocation-id eipalloc-xxxxx
```

### Error: No credentials provided

**For AWS Academy:**
```bash
# Ensure session token is set
export AWS_SESSION_TOKEN="your-session-token"
```

### Error: VPC not found

Update the `existing_vpc_id` in your tfvars file with the correct VPC ID.

### GitHub Actions fails with "role-to-assume"

For AWS Academy, use access keys instead of OIDC:

```yaml
# Replace in workflow file (temporarily for Academy)
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID_DEV }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY_DEV }}
    aws-session-token: ${{ secrets.AWS_SESSION_TOKEN_DEV }}
    aws-region: us-east-1
```

## 📊 Cost Estimation

### Development (~$15-30/month)
- RDS t3.micro: ~$12/month
- ElastiCache t3.micro: ~$11/month
- ECS Fargate (1 task, 0.25 vCPU, 0.5GB): ~$3-5/month
- NAT Gateway (1): ~$32/month
- **Total**: ~$58-60/month

### QA (~$40-70/month)
- RDS t3.small: ~$25/month
- ElastiCache t3.small: ~$23/month
- ECS Fargate (2 tasks): ~$6-10/month
- NAT Gateway (2): ~$64/month
- **Total**: ~$118-122/month

### Production (~$150-250/month)
- RDS t3.medium Multi-AZ: ~$115/month
- ElastiCache t3.medium Multi-AZ: ~$92/month
- ECS Fargate (3-10 tasks): ~$15-50/month
- NAT Gateway (2): ~$64/month
- WAF, CloudWatch, etc.: ~$20/month
- **Total**: ~$306-341/month

> **Note:** Actual costs depend on usage, data transfer, and AWS Academy credits.

## 📚 Additional Resources

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Academy Learner Lab Guide](https://awsacademy.instructure.com/)
- [GitHub Actions - OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)

## 🔧 Known Issues & Solutions

### SSH Connection Failures

**Problem:** Cannot connect to Bastion Host via SSH even though Security Group rules are configured correctly.

**Symptoms:**
```
Error establishing SSH connection to your instance. Try again later.
```

**Root Cause:** AWS Academy accounts or certain ISP configurations use NAT/Proxy that changes the effective source IP address, making IP-specific Security Group rules ineffective.

**Solution:**

**Option 1: Open SSH to 0.0.0.0/0 (DEVELOPMENT ONLY)**
```bash
# Allow SSH from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id <bastion-sg-id> \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

⚠️ **WARNING:** This is less secure. Only use in development environments. For production, use Option 2.

**Option 2: Use AWS Systems Manager Session Manager (RECOMMENDED)**
```bash
# Connect without opening port 22
aws ssm start-session --target <instance-id>

# SSH tunnel through SSM
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartSSHSession \
  --parameters "portNumber=22"
```

Benefits:
- No port 22 exposure
- Works from any IP
- Session logging in CloudTrail
- No SSH key management

**Implementation:** The current Terraform configuration uses `0.0.0.0/0` for Bastion SSH access to ensure compatibility with AWS Academy. In production, migrate to SSM Session Manager.

## 🆘 Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review Terraform logs: `TF_LOG=DEBUG terraform apply`
3. Check [Known Issues](#known-issues--solutions)
4. Open an issue in the repository

---

**Last Updated:** January 7, 2026  
**Terraform Version:** 1.6.0  
**AWS Provider Version:** 5.x
