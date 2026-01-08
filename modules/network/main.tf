# Data source for existing VPC
data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  id    = var.vpc_id
}

# VPC with DNS support enabled (only created if not using existing)
resource "aws_vpc" "main" {
  count                = var.use_existing_vpc ? 0 : 1
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-vpc"
    }
  )
}

# Local for VPC ID
locals {
  vpc_id = var.use_existing_vpc ? var.vpc_id : aws_vpc.main[0].id
}

# Internet Gateway for public subnets (only created if not using existing VPC)
resource "aws_internet_gateway" "main" {
  count  = var.use_existing_vpc ? 0 : 1
  vpc_id = local.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-igw"
    }
  )
}

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = length(var.availability_zones) > 0 ? var.availability_zones : data.aws_availability_zones.available.names
}

# Public subnets for EKS and public-facing resources (only created if not using existing)
resource "aws_subnet" "public" {
  count                   = var.use_existing_vpc ? 0 : var.public_subnet_count
  vpc_id                  = local.vpc_id
  cidr_block              = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.project_name}-public-subnet-${count.index + 1}"
      "kubernetes.io/role/elb"                    = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }
  )
}

# Route table for public subnets (only created if not using existing VPC)
resource "aws_route_table" "public" {
  count  = var.use_existing_vpc ? 0 : 1
  vpc_id = local.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-public-rt"
    }
  )
}

# Associate route table with public subnets (only if created)
resource "aws_route_table_association" "public" {
  count          = var.use_existing_vpc ? 0 : var.public_subnet_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# Private subnets
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = local.vpc_id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.project_name}-private-subnet-${count.index + 1}"
      "kubernetes.io/role/internal-elb"           = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }
  )
}

locals {
  public_subnet_list = var.use_existing_vpc ? var.public_subnet_ids : (var.public_subnet_count > 0 ? aws_subnet.public[*].id : [])
  nat_gateway_count  = length(var.private_subnet_cidrs) > 0 && length(local.public_subnet_list) > 0 ? min(length(local.public_subnet_list), length(var.private_subnet_cidrs)) : 0
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-nat-eip-${count.index + 1}"
    }
  )
}

# NAT Gateways (one per public subnet, up to number of private subnets)
resource "aws_nat_gateway" "main" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = local.public_subnet_list[count.index % length(local.public_subnet_list)]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-nat-${count.index + 1}"
    }
  )
}

# Route table for private subnets (one per AZ or single shared)
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs) > 0 ? length(var.private_subnet_cidrs) : 0
  vpc_id = local.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index % length(aws_nat_gateway.main)].id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-private-rt-${count.index + 1}"
    }
  )
}

# Associate route table with private subnets
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}




