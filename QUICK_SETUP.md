# Quick Setup Guide - AWS Academic Platform

## 🎯 5-Minute Setup for AWS Academy

### Step 1: Get Your AWS Credentials (2 minutes)

1. **Log in to AWS Academy**
2. Click **"AWS Details"** button
3. Copy the credentials:
   ```
   aws_access_key_id = ASIA...
   aws_secret_access_key = xxx...
   aws_session_token = IQo...
   ```

### Step 2: Identify Your VPC (1 minute)

Run these commands in your terminal:

```bash
# Set credentials
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="xxx..."
export AWS_SESSION_TOKEN="IQo..."
export AWS_REGION="us-east-1"

# Get VPC ID
aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text

# Get Subnet IDs
aws ec2 describe-subnets --filters "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[*].SubnetId' --output json
aws ec2 describe-subnets --filters "Name=map-public-ip-on-launch,Values=false" --query 'Subnets[*].SubnetId' --output json
```

### Step 3: Configure Terraform (1 minute)

Edit `environments/dev/terraform.tfvars`:

```hcl
existing_vpc_id             = "vpc-xxxxx"  # From Step 2
existing_public_subnet_ids  = ["subnet-aaa", "subnet-bbb"]  # From Step 2
existing_private_subnet_ids = ["subnet-ccc", "subnet-ddd"]  # From Step 2
```

### Step 4: Create SSH Key Pair (1 minute)

```bash
# Create SSH key for EC2 access
aws ec2 create-key-pair \
  --key-name academic-platform-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/academic-platform-key.pem

# Set correct permissions (Linux/Mac)
chmod 400 ~/.ssh/academic-platform-key.pem

# Windows PowerShell: Set permissions
icacls "$HOME\.ssh\academic-platform-key.pem" /inheritance:r
icacls "$HOME\.ssh\academic-platform-key.pem" /grant:r "$($env:USERNAME):R"
```

### Step 5: Deploy! (2 minutes)

```bash
cd infrastructure/terraform
terraform init
terraform plan -var-file="environments/dev/terraform.tfvars"
terraform apply -var-file="environments/dev/terraform.tfvars" -auto-approve
```

### Step 6: Connect to Bastion (30 seconds)

```bash
# Get Bastion IP
terraform output bastion_public_ip

# Connect via SSH
ssh -i ~/.ssh/academic-platform-key.pem ec2-user@<bastion-ip>

# Or use AWS Systems Manager (no SSH key needed)
aws ssm start-session --target <bastion-instance-id>
```

## 🚀 GitHub Actions Setup (Optional)

### Configure GitHub Secrets

Go to your repo: **Settings → Secrets → Actions → New repository secret**

Add these secrets:

```
AWS_ACCESS_KEY_ID_DEV=ASIA...
AWS_SECRET_ACCESS_KEY_DEV=xxx...
AWS_SESSION_TOKEN_DEV=IQo...

VPC_ID_DEV=vpc-xxxxx
PUBLIC_SUBNET_IDS_DEV=["subnet-aaa","subnet-bbb"]
PRIVATE_SUBNET_IDS_DEV=["subnet-ccc","subnet-ddd"]
```

### Test GitHub Actions

Push to `dev` branch or manually trigger workflow:

**Actions → Terraform Deploy to AWS → Run workflow**

## ✅ Verification

After deployment, check outputs:

```bash
# Get all outputs
terraform output

# Check EIP usage
terraform output eips_used_count
terraform output eips_remaining

# Get RDS endpoint
terraform output rds_endpoint

# Get ALB DNS
terraform output alb_dns_name
```

## 🔍 What Gets Created?

| Resource              | Type           | Cost/Month |
|-----------------------|----------------|------------|
| VPC Resources         | Existing       | $0         |
| NAT Gateway           | 1              | ~$32       |
| RDS PostgreSQL        | db.t3.micro    | ~$12       |
| ElastiCache Redis     | cache.t3.micro | ~$11       |
| ECS Fargate           | 1 task         | ~$3-5      |
| ALB                   | 1              | ~$16       |
| CloudWatch Logs       | Standard       | ~$2        |
| **Total**             |                | **~$76-78**|

> AWS Academy provides $100 credit, so this should be covered!

## ⚠️ Important Notes

- **Session Expires**: AWS Academy credentials expire every 4 hours
- **EIP Limit**: Stay within 5 EIPs (currently using 1 for NAT)
- **Stop Lab**: Remember to stop your lab when not in use
- **Destroy Resources**: Run `terraform destroy` before lab expires

## 🆘 Quick Troubleshooting

### "SSH Connection Failed"

**Problem:** Cannot connect to instances via SSH.

**Solution:**
```bash
# 1. Verify port 22 is open
aws ec2 describe-security-groups --group-ids <sg-id> \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'

# 2. If needed, open SSH temporarily (DEV ONLY)
aws ec2 authorize-security-group-ingress \
  --group-id <bastion-sg-id> \
  --protocol tcp --port 22 --cidr 0.0.0.0/0

# 3. Test connectivity
Test-NetConnection -ComputerName <public-ip> -Port 22  # Windows
nc -zv <public-ip> 22  # Linux/Mac

# 4. Alternative: Use AWS Systems Manager (RECOMMENDED)
aws ssm start-session --target <instance-id>
```

### "AddressLimitExceeded"
```bash
# Check EIP usage
aws ec2 describe-addresses --query 'length(Addresses)'

# Release unused EIPs
aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].[AllocationId]' --output text | \
xargs -I {} aws ec2 release-address --allocation-id {}
```

### "Invalid Credentials"
```bash
# Re-export credentials from AWS Academy
export AWS_ACCESS_KEY_ID="new-key"
export AWS_SECRET_ACCESS_KEY="new-secret"
export AWS_SESSION_TOKEN="new-token"
```

### "VPC not found"
```bash
# Verify VPC exists
aws ec2 describe-vpcs --vpc-ids vpc-xxxxx
```

## 📱 Next Steps

After successful deployment:

1. **Configure DNS**: Point your domain to ALB DNS
2. **Deploy Services**: Push Docker images to ECR
3. **Configure Monitoring**: Add email to SNS topic
4. **Set up CI/CD**: Configure GitHub Actions for services

---

**Ready to deploy? Let's go!** 🚀

