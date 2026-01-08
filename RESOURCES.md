# Terraform Resources Documentation

This document describes all AWS resources created by the `infra-terraform` module and their purpose.

## Table of Contents

- [Network Resources](#network-resources)
- [EKS Resources](#eks-resources)
- [Conditional Resources](#conditional-resources)

---

## Network Resources

### VPC (Virtual Private Cloud)

**Resource**: `aws_vpc.main`  
**Module**: `modules/network`  
**Conditional**: Only created if `use_existing_vpc = false`

**Purpose**:  
Creates an isolated virtual network in AWS. This is the foundation of your network infrastructure where all other resources will be deployed.

**Key Features**:

- DNS hostnames and DNS support enabled
- Custom CIDR block (default: `10.0.0.0/16`)
- Provides network isolation and security boundaries

**When to use**:  
Use when you need a completely new VPC. If you already have a VPC, set `use_existing_vpc = true` and provide the `vpc_id`.

---

### Internet Gateway (IGW)

**Resource**: `aws_internet_gateway.main`  
**Module**: `modules/network`  
**Conditional**: Only created if `use_existing_vpc = false`

**Purpose**:  
Enables communication between resources in your VPC and the internet. Attached to the VPC to provide public internet access.

**Key Features**:

- Allows public subnets to have internet connectivity
- Required for public-facing resources
- Provides outbound and inbound internet access

**When to use**:  
Automatically created with new VPCs. Required for public subnets to access the internet.

---

### Public Subnets

**Resource**: `aws_subnet.public`  
**Module**: `modules/network`  
**Conditional**: Only created if `use_existing_vpc = false`

**Purpose**:  
Subnets with direct internet access via Internet Gateway. Used for resources that need public connectivity (e.g., Load Balancers, NAT Gateways).

**Key Features**:

- Automatically assigns public IP addresses (`map_public_ip_on_launch = true`)
- Tagged for Kubernetes ELB (Elastic Load Balancer) support
- Distributed across multiple availability zones for high availability

**Configuration**:

- Default: 2 public subnets (one per availability zone)
- Configurable via `public_subnet_count` variable
- CIDR blocks automatically calculated from VPC CIDR

**When to use**:  
Required for:

- NAT Gateways (for private subnet internet access)
- Public-facing load balancers
- Bastion hosts
- Resources that need direct internet access

---

### Private Subnets

**Resource**: `aws_subnet.private`  
**Module**: `modules/network`  
**Always Created**: Yes (if `private_subnet_cidrs` is provided)

**Purpose**:  
Subnets without direct internet access. Used for application workloads, databases, and EKS worker nodes that should not be directly accessible from the internet.

**Key Features**:

- No public IP addresses assigned
- Tagged for Kubernetes internal ELB support
- Internet access via NAT Gateway (outbound only)
- More secure for sensitive workloads

**Configuration**:

- CIDR blocks must be specified in `private_subnet_cidrs`
- Must be within the VPC CIDR range
- Distributed across availability zones

**When to use**:  
Ideal for:

- EKS worker nodes
- Application servers
- Databases
- Any resource that doesn't need direct internet access

---

### Elastic IPs (EIP)

**Resource**: `aws_eip.nat`  
**Module**: `modules/network`  
**Conditional**: Created when private subnets exist

**Purpose**:  
Static public IP addresses used by NAT Gateways. Provides a consistent public IP for outbound internet traffic from private subnets.

**Key Features**:

- One EIP per NAT Gateway
- VPC-scoped (not released when NAT Gateway is deleted)
- Required for NAT Gateway functionality

**When to use**:  
Automatically created when private subnets are configured. Each NAT Gateway requires one Elastic IP.

---

### NAT Gateways

**Resource**: `aws_nat_gateway.main`  
**Module**: `modules/network`  
**Conditional**: Created when private subnets exist

**Purpose**:  
Enables outbound internet access for resources in private subnets while keeping them secure from inbound internet traffic.

**Key Features**:

- Allows private subnets to access internet (outbound only)
- Provides high availability (one per availability zone)
- Managed service (no maintenance required)
- Charges apply for data transfer and hourly usage

**Configuration**:

- One NAT Gateway per private subnet (or shared across subnets in same AZ)
- Placed in public subnets
- Uses Elastic IP for public IP address

**When to use**:  
Required when:

- Private subnets need to download packages, updates, or container images
- EKS worker nodes need to pull images from Docker Hub, ECR, etc.
- Applications need to make outbound API calls

**Cost Note**:  
NAT Gateways incur charges (~$0.045/hour + data transfer). Consider using fewer NAT Gateways if cost is a concern.

---

### Public Route Table

**Resource**: `aws_route_table.public`  
**Module**: `modules/network`  
**Conditional**: Only created if `use_existing_vpc = false`

**Purpose**:  
Defines routing rules for public subnets. Routes all internet traffic (`0.0.0.0/0`) to the Internet Gateway.

**Key Features**:

- Routes traffic to Internet Gateway
- Associated with public subnets
- Enables public internet access

**When to use**:  
Automatically created with new VPCs. Required for public subnet internet access.

---

### Private Route Tables

**Resource**: `aws_route_table.private`  
**Module**: `modules/network`  
**Conditional**: Created when private subnets exist

**Purpose**:  
Defines routing rules for private subnets. Routes all internet traffic (`0.0.0.0/0`) to NAT Gateways for outbound access.

**Key Features**:

- One route table per private subnet (or shared)
- Routes traffic to NAT Gateway
- Enables outbound-only internet access

**Configuration**:

- Automatically routes to appropriate NAT Gateway
- One route table per private subnet for better isolation

**When to use**:  
Automatically created with private subnets. Required for private subnet outbound internet access.

---

### Route Table Associations

**Resources**:

- `aws_route_table_association.public`
- `aws_route_table_association.private`  
  **Module**: `modules/network`

**Purpose**:  
Associates subnets with their respective route tables, enabling the routing rules to take effect.

**Key Features**:

- Links subnets to route tables
- Required for routing to work
- One association per subnet

**When to use**:  
Automatically created. Required for routing functionality.

---

## EKS Resources

### CloudWatch Log Group

**Resource**: `aws_cloudwatch_log_group.eks_cluster`  
**Module**: `modules/eks`  
**Always Created**: Yes

**Purpose**:  
Stores logs from the EKS cluster control plane. Captures API server logs, audit logs, authentication logs, and more.

**Key Features**:

- Centralized logging for EKS cluster
- Configurable retention period (default: 7 days)
- Enables troubleshooting and security auditing

**Log Types Captured**:

- `api`: API server logs
- `audit`: Audit logs
- `authenticator`: Authentication logs
- `controllerManager`: Controller manager logs
- `scheduler`: Scheduler logs

**When to use**:  
Always enabled for production clusters. Essential for debugging and compliance.

**Cost Note**:  
CloudWatch Logs charges for ingestion and storage. Adjust `log_retention_days` to control costs.

---

### EKS Cluster

**Resource**: `aws_eks_cluster.main`  
**Module**: `modules/eks`  
**Always Created**: Yes

**Purpose**:  
Managed Kubernetes control plane. Provides the Kubernetes API server, etcd, and control plane components.

**Key Features**:

- Fully managed Kubernetes service
- High availability (multi-AZ)
- Automatic updates and patching
- Integrated with AWS services (IAM, VPC, CloudWatch)

**Configuration**:

- Deployed across multiple availability zones
- Uses existing IAM role (no role creation)
- Configurable Kubernetes version
- Public and/or private API endpoints

**Network Configuration**:

- Uses both public and private subnets
- Security groups managed by EKS
- Endpoint access configurable (public/private)

**When to use**:  
Core resource for running Kubernetes workloads. Required for container orchestration.

**Cost Note**:  
EKS charges ~$0.10/hour (~$73/month) for the control plane, regardless of node count.

---

### Managed Node Group

**Resource**: `aws_eks_node_group.main`  
**Module**: `modules/eks`  
**Conditional**: Created when `node_role_arn` is provided

**Purpose**:  
Managed group of EC2 instances that run your Kubernetes workloads. AWS manages the lifecycle, updates, and scaling.

**Key Features**:

- Fully managed by AWS
- Automatic updates and patching
- Integrated with EKS
- Auto-scaling support
- Supports both ON_DEMAND and SPOT instances

**Configuration**:

- Instance types: Configurable (default: `t3.micro`)
- Scaling: Min, max, and desired capacity
- AMI type: AL2_x86_64 (K8s 1.32-) or AL2023_x86_64_STANDARD (K8s 1.33+)
- Disk size: Configurable (default: 20 GB)

**When to use**:  
Recommended for production workloads. Easier to manage than self-managed nodes.

**Advantages**:

- AWS handles node updates and patching
- Automatic node replacement on failure
- Better integration with EKS
- Less operational overhead

---

### Launch Template (Self-Managed Nodes)

**Resource**: `aws_launch_template.eks_nodes`  
**Module**: `modules/eks`  
**Conditional**: Created when `node_role_arn` is empty

**Purpose**:  
Template for launching EC2 instances as self-managed EKS worker nodes. Used when Managed Node Groups are not available.

**Key Features**:

- Defines EC2 instance configuration
- Uses EKS-optimized AMI
- Includes bootstrap script for joining cluster
- Configurable instance types and security groups

**Configuration**:

- AMI: Automatically selected based on Kubernetes version
- User data: Bootstrap script to join EKS cluster
- Security groups: Uses EKS cluster security group

**When to use**:  
Fallback option when Managed Node Groups cannot be used (e.g., custom AMI requirements, specific instance configurations).

**Note**:  
Requires more manual management than Managed Node Groups.

---

### Auto Scaling Group (Self-Managed Nodes)

**Resource**: `aws_autoscaling_group.eks_nodes`  
**Module**: `modules/eks`  
**Conditional**: Created when `node_role_arn` is empty

**Purpose**:  
Manages a group of EC2 instances that run Kubernetes workloads. Automatically scales based on demand.

**Key Features**:

- Auto-scaling based on metrics
- Distributes instances across availability zones
- Health checks and automatic replacement
- Configurable min, max, and desired capacity

**Configuration**:

- Uses Launch Template for instance configuration
- Deployed across multiple subnets (availability zones)
- Tagged for Kubernetes cluster recognition

**When to use**:  
Used with self-managed nodes when Managed Node Groups are not available.

**Scaling**:  
Can be configured with Kubernetes Cluster Autoscaler for automatic scaling based on pod resource requests.

---

## Conditional Resources Summary

### Resources Created with New VPC (`use_existing_vpc = false`):

- ✅ VPC
- ✅ Internet Gateway
- ✅ Public Subnets (2 by default)
- ✅ Public Route Table
- ✅ Public Route Table Associations

### Resources Created with Existing VPC (`use_existing_vpc = true`):

- ❌ VPC (uses existing)
- ❌ Internet Gateway (uses existing)
- ❌ Public Subnets (uses existing)
- ✅ Private Subnets (always created if `private_subnet_cidrs` provided)
- ✅ NAT Gateways (if private subnets exist)
- ✅ Elastic IPs (if NAT Gateways exist)
- ✅ Private Route Tables (if private subnets exist)

### Resources Created Based on Node Configuration:

**With Managed Node Group** (`node_role_arn` provided):

- ✅ Managed Node Group
- ❌ Launch Template
- ❌ Auto Scaling Group

**With Self-Managed Nodes** (`node_role_arn` empty):

- ❌ Managed Node Group
- ✅ Launch Template
- ✅ Auto Scaling Group
- ✅ Data source for EKS AMI

### Always Created Resources:

- ✅ CloudWatch Log Group
- ✅ EKS Cluster
- ✅ Private Subnets (if `private_subnet_cidrs` provided)
- ✅ NAT Gateways (if private subnets exist)
- ✅ Route Tables and Associations (as needed)

---

## Resource Dependencies

### Creation Order:

1. **Network Layer**:
   - VPC (if creating new)
   - Internet Gateway (if creating new)
   - Public Subnets (if creating new)
   - Public Route Table (if creating new)
   - Private Subnets
   - Elastic IPs
   - NAT Gateways
   - Private Route Tables

2. **EKS Layer**:
   - CloudWatch Log Group
   - EKS Cluster (depends on subnets)
   - Managed Node Group OR Launch Template + ASG (depends on EKS Cluster)

### Destruction Order:

1. Managed Node Group / Auto Scaling Group
2. EKS Cluster
3. NAT Gateways
4. Elastic IPs
5. Route Table Associations
6. Route Tables
7. Subnets
8. Internet Gateway
9. VPC (if created)
10. CloudWatch Log Group

---

## Cost Considerations

### Monthly Estimated Costs (us-east-1):

**Always Created**:

- EKS Cluster: ~$73/month (~$0.10/hour)
- CloudWatch Logs: ~$0.50-5/month (depends on log volume)

**With Private Subnets**:

- NAT Gateway: ~$32/month per gateway (~$0.045/hour + data transfer)
- Elastic IP: Free (when attached to NAT Gateway)

**With Managed Node Group** (2x t3.micro):

- EC2 Instances: ~$15/month per instance
- EBS Storage: ~$2/month per 20GB

**Total Estimated Cost** (minimal setup):

- ~$120-150/month for basic EKS cluster with 2 nodes

**Cost Optimization Tips**:

1. Use fewer NAT Gateways (share across AZs if possible)
2. Use SPOT instances for non-critical workloads
3. Right-size instances based on actual usage
4. Adjust CloudWatch log retention
5. Use Reserved Instances for predictable workloads

---

## Security Considerations

### Network Security:

- ✅ Private subnets isolate workloads from internet
- ✅ NAT Gateway provides outbound-only access
- ✅ Security groups managed by EKS
- ✅ VPC provides network isolation

### Access Control:

- ✅ IAM roles for EKS and nodes (must be provided)
- ✅ Public endpoint access can be restricted via CIDR blocks
- ✅ Private endpoint for internal access
- ✅ CloudWatch logs for audit trail

### Best Practices:

- Use private subnets for worker nodes
- Restrict public endpoint access in production
- Enable both private and public endpoints
- Regularly review CloudWatch logs
- Use least-privilege IAM policies

---

## Additional Notes

### Data Sources (Read-Only):

- `data.aws_vpc.existing`: Fetches existing VPC details
- `data.aws_availability_zones.available`: Gets available AZs in region
- `data.aws_eks_cluster_auth.main`: Gets authentication token for EKS
- `data.aws_ami.eks_worker`: Finds EKS-optimized AMI (self-managed nodes only)

### Tags:

All resources are tagged with:

- `Environment`: From `environment` variable
- `Project`: From `project_name` variable
- `ManagedBy`: "Terraform"
- `Name`: Resource-specific name

### Outputs:

The module provides outputs for:

- VPC and subnet IDs
- Internet Gateway and NAT Gateway IDs
- EKS cluster details (name, ARN, endpoint, version)
- Node group and ASG names

These outputs can be used by other Terraform modules or scripts.
