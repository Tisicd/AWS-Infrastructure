# Academic Platform - Infrastructure as Code

This directory contains Terraform configurations for deploying the Academic Platform infrastructure on AWS using a multi-account architecture (Hub + Service Accounts).

## Quick Start

### Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- PowerShell (for Windows) or Bash (for Linux/Mac)

### Deployment

#### Hub Account (Single Account)

```powershell
.\scripts\setup-hub-account.ps1 -Environment qa
```

#### Multi-Account Deployment (Hub + Service Accounts)

```powershell
.\scripts\setup-multi-account-qa.ps1
```

#### Service Accounts Only (after Hub is deployed)

```powershell
.\scripts\setup-service-accounts-only.ps1
```

#### Destruction

```powershell
.\scripts\destroy-multi-account.ps1
```

## Architecture

- **Hub Account**: Contains shared resources (Bastion, Database, Kong API Gateway, Monitoring)
- **Service Accounts**: Contain microservices deployed via Auto Scaling Groups with Application Load Balancers

## Key Features

- **Auto-Recovery**: All EC2 instances automatically recover via Auto Scaling Groups
- **Elastic IPs**: Dedicated EIPs for all services with automatic re-association
- **High Availability**: Application Load Balancers and Auto Scaling Groups for all services
- **Multi-Account**: Hub & Spoke architecture with cross-account connectivity

## Scripts

- `setup-hub-account.ps1`: Deploy hub account infrastructure
- `setup-multi-account-qa.ps1`: Deploy hub + all service accounts
- `setup-service-accounts-only.ps1`: Deploy only service accounts (requires existing hub)
- `destroy-multi-account.ps1`: Destroy all infrastructure across accounts

## Configuration

Environment-specific configurations are in `environments/qa/`:
- `terraform.tfvars.hub`: Hub account configuration
- `terraform.tfvars.service`: Service accounts configuration

## Modules

- `modules/key-pair`: EC2 Key Pair management
- `modules/bastion-host`: Bastion host with ASG and EIP
- `modules/ec2-database`: Database server with PostgreSQL, Redis, TimescaleDB, MongoDB
- `modules/ec2-kong`: Kong API Gateway with ALB and ASG
- `modules/asg-microservices`: Microservices deployment with ASG, ALB, and EIPs
- `modules/security-groups`: Security group configurations
- `modules/monitoring`: CloudWatch alarms and SNS topics (Hub only)

## Important Notes

- Key pairs (`.pem` files) are excluded from Git for security
- Terraform state files are excluded from Git
- Deployment-specific files in `deployments/` are excluded from Git
- All credentials and sensitive data are excluded via `.gitignore`
