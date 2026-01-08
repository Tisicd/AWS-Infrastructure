# CloudWatch Log Group for EKS cluster logs
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-logs"
    }
  )
}

# EKS Cluster
locals {
  # Normalize public_access_cidrs: empty list means allow all (0.0.0.0/0)
  # AWS EKS interprets [] as [0.0.0.0/0], so we normalize to avoid update conflicts
  normalized_public_access_cidrs = var.endpoint_public_access ? (
    length(var.public_access_cidrs) == 0 ? ["0.0.0.0/0"] : var.public_access_cidrs
  ) : []
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.eks_cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = []
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = local.normalized_public_access_cidrs
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  depends_on = [
    aws_cloudwatch_log_group.eks_cluster
  ]

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )
}

# Data source for EKS cluster auth
data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# Managed Node Group (only if node_role_arn is provided)
resource "aws_eks_node_group" "main" {
  count           = var.node_role_arn != "" ? 1 : 0
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids

  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  ami_type       = var.ami_type
  disk_size      = var.disk_size

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-node-group"
    }
  )

  depends_on = [
    aws_eks_cluster.main
  ]
}

# Launch Template for self-managed nodes (fallback when node_role_arn is not provided)
# Get EKS optimized AMI for the cluster version
# Note: This data source only runs when node_role_arn is empty (self-managed nodes)
data "aws_ami" "eks_worker" {
  count       = var.node_role_arn == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  # Search for EKS optimized AMI - try multiple patterns
  filter {
    name = "name"
    values = var.kubernetes_version != null && var.kubernetes_version != "" ? [
      "amazon-eks-node-${replace(var.kubernetes_version, ".", "-")}-*",
      "amazon-eks-node-AL2-${replace(var.kubernetes_version, ".", "-")}-*"
      ] : [
      "amazon-eks-node-*"
    ]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  userdata = var.node_role_arn == "" ? base64encode(templatefile("${path.module}/userdata.sh", {
    cluster_name = aws_eks_cluster.main.name
  })) : ""
}

resource "aws_launch_template" "eks_nodes" {
  count         = var.node_role_arn == "" ? 1 : 0
  name          = "${var.cluster_name}-nodes"
  image_id      = data.aws_ami.eks_worker[0].id
  instance_type = var.instance_types[0]
  key_name      = ""

  vpc_security_group_ids = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]

  user_data = local.userdata

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        Name                                        = "${var.cluster_name}-node"
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
      }
    )
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-launch-template"
    }
  )
}

# Auto Scaling Group for self-managed nodes
resource "aws_autoscaling_group" "eks_nodes" {
  count               = var.node_role_arn == "" ? 1 : 0
  name                = "${var.cluster_name}-nodes-asg"
  vpc_zone_identifier = var.subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_size

  launch_template {
    id      = aws_launch_template.eks_nodes[0].id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-node"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [
    aws_eks_cluster.main
  ]
}




