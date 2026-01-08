# SSH Connection Troubleshooting Guide

## Problem Description

When deploying infrastructure to AWS Academy accounts, SSH connections to EC2 instances (particularly the Bastion Host) may fail with:

```
Error establishing SSH connection to your instance. Try again later.
Failed to connect to your instance
```

Even though:
- ✅ The instance is running
- ✅ The Security Group has port 22 open
- ✅ The correct key pair is configured
- ✅ The public IP is accessible

## Root Cause

**AWS Academy accounts or certain ISP configurations use NAT/Proxy/VPN** that changes the effective source IP address when connecting to AWS resources. This causes:

1. Your detected public IP (e.g., `157.100.135.84`) may not match the actual source IP AWS sees
2. Security Group rules restricting SSH to `your_ip/32` block the connection
3. Even though `Test-NetConnection` shows the instance is reachable, the Security Group drops the packets

## Solutions

### ✅ Solution 1: Open SSH to 0.0.0.0/0 (Development Only)

**When to use:** Development/testing environments where security is less critical.

**Steps:**

```bash
# 1. Identify your Bastion Security Group ID
terraform output bastion_security_group_id
# Or manually:
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*bastion*" \
  --query 'SecurityGroups[0].GroupId' --output text

# 2. Add SSH rule for all IPs
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# 3. Wait 10 seconds for propagation
Start-Sleep -Seconds 10  # PowerShell
sleep 10  # Bash

# 4. Test connectivity
Test-NetConnection -ComputerName <bastion-ip> -Port 22  # PowerShell
nc -zv <bastion-ip> 22  # Bash

# 5. Connect via SSH
ssh -i ~/.ssh/academic-platform-key.pem ec2-user@<bastion-ip>
```

**⚠️ Security Warning:**
- This exposes SSH to the entire internet
- Only use in development environments
- Ensure strong SSH key authentication
- Consider SSH hardening (disable password auth, fail2ban, etc.)
- For production, use Solution 2

**To implement permanently in Terraform:**

Edit `modules/security-groups/main.tf`:

```hcl
# Bastion Security Group
resource "aws_security_group" "bastion" {
  # ...
  
  ingress {
    description = "SSH from Internet (AWS Academy compatibility)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Changed from var.your_ip_cidr
  }
}
```

### ✅ Solution 2: AWS Systems Manager Session Manager (RECOMMENDED)

**When to use:** Production environments or when maximum security is required.

**Benefits:**
- ✅ No port 22 exposure to internet
- ✅ Works from any IP address
- ✅ Session logging in CloudTrail
- ✅ No SSH key management
- ✅ IAM-based access control

**Prerequisites:**

1. **Install Session Manager Plugin:**

```bash
# Windows (PowerShell as Administrator)
Invoke-WebRequest -Uri https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe -OutFile SessionManagerPluginSetup.exe
.\SessionManagerPluginSetup.exe /quiet

# Mac
brew install --cask session-manager-plugin

# Linux (Ubuntu/Debian)
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
```

2. **Verify Installation:**

```bash
session-manager-plugin --version
```

**Usage:**

```bash
# 1. Get instance ID
terraform output bastion_instance_id
# Or manually:
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*bastion*" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text

# 2. Start SSM session (interactive shell)
aws ssm start-session --target i-xxxxxxxxx

# 3. SSH tunnel through SSM (for SCP/SFTP)
aws ssm start-session \
  --target i-xxxxxxxxx \
  --document-name AWS-StartSSHSession \
  --parameters "portNumber=22"
```

**SSH ProxyCommand Configuration:**

Add to `~/.ssh/config`:

```
# Bastion Host via SSM
Host bastion-ssm
  HostName i-xxxxxxxxx
  User ec2-user
  ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
  IdentityFile ~/.ssh/academic-platform-key.pem
```

Then connect:

```bash
ssh bastion-ssm
```

**Terraform Configuration:**

```hcl
# Remove SSH ingress rule from Bastion SG
resource "aws_security_group" "bastion" {
  # Remove port 22 ingress completely
  
  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Add IAM role for SSM (if not already present)
resource "aws_iam_role" "bastion_ssm" {
  name = "${var.project_name}-${var.environment}-bastion-ssm-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion_ssm" {
  name = "${var.project_name}-${var.environment}-bastion-ssm-profile"
  role = aws_iam_role.bastion_ssm.name
}

resource "aws_instance" "bastion" {
  # ... existing config ...
  iam_instance_profile = aws_iam_instance_profile.bastion_ssm.name
}
```

### Solution 3: IP Whitelist Range

**When to use:** When you know your organization's IP range but not your specific IP.

```bash
# Example: Whitelist entire subnet
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr 157.100.0.0/16  # Replace with your organization's CIDR
```

## Verification Steps

After applying any solution:

### 1. Verify Security Group Rules

```bash
aws ec2 describe-security-groups --group-ids <bastion-sg-id> \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
```

Expected output:
```json
[
  {
    "FromPort": 22,
    "IpProtocol": "tcp",
    "IpRanges": [
      {
        "CidrIp": "0.0.0.0/0",
        "Description": "SSH from Internet (AWS Academy compatibility)"
      }
    ],
    "ToPort": 22
  }
]
```

### 2. Test Port Connectivity

```bash
# PowerShell
Test-NetConnection -ComputerName <bastion-ip> -Port 22

# Bash
nc -zv <bastion-ip> 22
```

Expected output:
```
TcpTestSucceeded : True
```

### 3. Test SSH Connection

```bash
ssh -i ~/.ssh/academic-platform-key.pem -v ec2-user@<bastion-ip>
```

Successful connection shows:
```
debug1: Authentication succeeded (publickey).
Authenticated to <bastion-ip> ([<ip>]:22).
```

### 4. Verify Instance Console Logs

```bash
aws ec2 get-console-output --instance-id <bastion-id> \
  --query 'Output' --output text | grep -i sshd
```

Should show:
```
[  OK  ] Started OpenSSH server daemon.
```

## Best Practices

1. **Development:** Use Solution 1 (0.0.0.0/0) for speed and simplicity
2. **QA/Staging:** Start transitioning to Solution 2 (SSM)
3. **Production:** Always use Solution 2 (SSM) for maximum security

4. **Additional Security Measures:**
   - Enable SSH key rotation
   - Use short-lived credentials (AWS STS)
   - Enable CloudTrail logging
   - Configure session duration limits
   - Use MFA for AWS Console access
   - Implement fail2ban or similar on instances

## Common Errors and Fixes

### "Permission denied (publickey)"

**Cause:** Wrong SSH key or incorrect permissions.

**Fix:**
```bash
# Check key permissions (Linux/Mac)
ls -la ~/.ssh/academic-platform-key.pem
# Should be: -r-------- (400)

# Fix permissions
chmod 400 ~/.ssh/academic-platform-key.pem

# Windows: Reset permissions
icacls "$HOME\.ssh\academic-platform-key.pem" /inheritance:r
icacls "$HOME\.ssh\academic-platform-key.pem" /grant:r "$($env:USERNAME):R"
```

### "Connection timed out"

**Cause:** Port 22 blocked by Security Group or Network ACL.

**Fix:**
```bash
# Check Security Group
aws ec2 describe-security-groups --group-ids <sg-id>

# Check Network ACL
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=<vpc-id>"
```

### "Host key verification failed"

**Cause:** Instance was recreated with same IP but different key.

**Fix:**
```bash
ssh-keygen -R <bastion-ip>
```

## AWS Academy Specific Notes

- **Credentials Expire:** AWS Academy credentials expire after 4 hours. You'll need to refresh them regularly.
- **Lab Timer:** Resources will be automatically terminated when the lab session ends.
- **EIP Limits:** You only have 5 EIPs. Plan accordingly.
- **Service Restrictions:** Some AWS services (ECS, RDS, etc.) may be restricted.

## Additional Resources

- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [SSH Troubleshooting Guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/TroubleshootingInstancesConnecting.html)
- [Security Group Rules Reference](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)

---

**Last Updated:** January 7, 2026  
**Status:** Verified working in AWS Academy Learner Labs

