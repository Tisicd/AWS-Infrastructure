# =============================================================================
# Kong API Gateway Module with ALB and ASG Support
# =============================================================================

# Elastic IP for Kong (always created for hub account, always 1 EIP)
# Requirement: Kong must always have a dedicated Elastic IP that persists across instance replacements
resource "aws_eip" "kong" {
  # Always create exactly 1 EIP for Kong, regardless of ASG configuration
  # When ASG is disabled: associate with first instance via aws_eip_association
  # When ASG is enabled: association happens via user-data script
  # If instance is terminated, EIP persists and can be re-associated automatically
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-kong-eip"
      Role        = "Kong-API-Gateway"
      Purpose     = "Kong-Gateway-EIP"
      AutoManaged = "true"
      Persistent  = "true"  # EIP persists across instance replacements
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Launch Template for Kong instances
resource "aws_launch_template" "kong" {
  name_prefix   = "${var.project_name}-${var.environment}-kong-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [var.security_group_id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    kong_version        = var.kong_version
    kong_database_host  = var.kong_database_host
    kong_database_port  = var.kong_database_port
    kong_database_name  = var.kong_database_name
    environment         = var.environment
    instance_index      = 0  # ASG instances start at 0
    eip_allocation_id   = var.enable_asg ? aws_eip.kong.id : ""
    associate_eip       = var.enable_asg ? "true" : "false"
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30  # Amazon Linux 2023 AMI requires minimum 30GB
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-${var.environment}-kong"
        Role = "Kong-API-Gateway"
      }
    )
  }
}

# Application Load Balancer for Kong
resource "aws_lb" "kong" {
  name               = "${var.project_name}-${var.environment}-kong-alb"
  internal           = var.load_balancer_internal
  load_balancer_type = "application"
  security_groups    = var.load_balancer_security_group_ids
  subnets            = var.load_balancer_subnet_ids

  enable_deletion_protection = false
  enable_http2               = true
  enable_cross_zone_load_balancing = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-kong-alb"
    }
  )
}

# Target Group for Kong
resource "aws_lb_target_group" "kong" {
  name     = "${var.project_name}-${var.environment}-kong-tg"
  port     = var.target_group_port
  protocol = var.target_group_protocol
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    protocol            = var.target_group_protocol
    matcher             = var.health_check_matcher
  }

  deregistration_delay = 30

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-kong-tg"
    }
  )
}

# ALB Listener
resource "aws_lb_listener" "kong" {
  load_balancer_arn = aws_lb.kong.arn
  port              = var.load_balancer_listener_port
  protocol          = var.load_balancer_listener_protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong.arn
  }
}

# Auto Scaling Group (optional)
resource "aws_autoscaling_group" "kong" {
  count = var.enable_asg ? 1 : 0

  name = "${var.project_name}-${var.environment}-kong-asg"

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.kong.id
    version = "$Latest"
  }

  # Automatic Target Group registration via ASG
  target_group_arns = [aws_lb_target_group.kong.arn]

  # Instance replacement policy for high availability
  termination_policies = ["OldestInstance"]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-kong"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "Kong-API-Gateway"
    propagate_at_launch = true
  }

  tag {
    key                 = "AutoManaged"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Null resource to associate EIP with ASG instances after they are created
# This ensures EIP is associated automatically via Terraform, not just user-data
resource "null_resource" "kong_eip_association" {
  count = var.enable_asg && var.allocate_eip_per_instance && length(aws_autoscaling_group.kong) > 0 ? 1 : 0

  triggers = {
    asg_name      = aws_autoscaling_group.kong[0].name
    eip_allocation_id = aws_eip.kong.id
    asg_arn       = aws_autoscaling_group.kong[0].arn
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command = <<-EOT
      Start-Sleep -Seconds 45
      $asgName = "${aws_autoscaling_group.kong[0].name}"
      $eipAllocId = "${aws_eip.kong.id}"
      $region = "${data.aws_region.current.name}"
      
      $instanceId = aws autoscaling describe-auto-scaling-groups `
        --auto-scaling-group-names $asgName `
        --query 'AutoScalingGroups[0].Instances[?HealthStatus==`Healthy` || LifecycleState==`InService`].InstanceId' `
        --output text | Select-Object -First 1
      
      if ($instanceId -and $instanceId -ne "None" -and $instanceId.Trim() -ne "") {
        Write-Host "Associating EIP $eipAllocId with instance $instanceId"
        aws ec2 associate-address `
          --instance-id $instanceId `
          --allocation-id $eipAllocId `
          --allow-reassociation `
          --region $region
      } else {
        Write-Host "No healthy instances found in ASG yet"
      }
    EOT
  }

  depends_on = [aws_autoscaling_group.kong, aws_eip.kong]
}

# Note: When ASG is enabled, auto-recovery is handled automatically by the ASG health checks.
# The ASG will replace unhealthy instances based on ELB health checks.
# No additional CloudWatch alarm is needed for ASG-based instances.

# Data source for current AWS region
data "aws_region" "current" {}

# EC2 Instances (when ASG is disabled)
resource "aws_instance" "kong" {
  count = var.enable_asg ? 0 : var.instance_count

  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  subnet_id     = var.subnet_ids[count.index % length(var.subnet_ids)]

  vpc_security_group_ids = [var.security_group_id]

  root_block_device {
    volume_size = 30  # Amazon Linux 2023 AMI requires minimum 30GB
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    kong_version        = var.kong_version
    kong_database_host  = var.kong_database_host
    kong_database_port  = var.kong_database_port
    kong_database_name  = var.kong_database_name
    environment         = var.environment
    instance_index      = count.index
    eip_allocation_id   = var.allocate_eip_per_instance ? aws_eip.kong.id : ""
    associate_eip       = var.allocate_eip_per_instance ? "true" : "false"
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-kong-${count.index + 1}"
      Role = "Kong-API-Gateway"
    }
  )
}

# Register EC2 instances with Target Group (when ASG is disabled)
# Note: When ASG is enabled, target group registration happens automatically via target_group_arns
resource "aws_lb_target_group_attachment" "kong" {
  count = var.enable_asg ? 0 : var.instance_count

  target_group_arn = aws_lb_target_group.kong.arn
  target_id        = aws_instance.kong[count.index].id
  port             = var.target_group_port

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch Alarm for EC2 Auto Recovery (when ASG is disabled)
# This ensures instances are automatically recovered if they become impaired
resource "aws_cloudwatch_metric_alarm" "kong_instance_recovery" {
  for_each = var.enable_asg ? {} : { for idx in range(var.instance_count) : idx => idx }

  alarm_name          = "${var.project_name}-${var.environment}-kong-${each.value + 1}-recovery"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed_System"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "0"
  alarm_description   = "Trigger EC2 Auto Recovery when system status check fails for Kong instance ${each.value + 1}"

  dimensions = {
    InstanceId = aws_instance.kong[each.value].id
  }

  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.name}:ec2:recover"
  ]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-kong-recovery-alarm-${each.value + 1}"
    }
  )
}

# Elastic IP Association (only when ASG is disabled - when ASG is enabled, association happens via user-data)
# Associates the single Kong EIP with the first instance when ASG is disabled
resource "aws_eip_association" "kong" {
  count         = var.enable_asg ? 0 : (var.allocate_eip_per_instance && var.instance_count > 0 ? 1 : 0)
  instance_id   = aws_instance.kong[0].id
  allocation_id = aws_eip.kong.id

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "instance_ids" {
  value = var.enable_asg ? (length(aws_autoscaling_group.kong) > 0 ? [] : []) : aws_instance.kong[*].id
  description = "Instance IDs (empty when using ASG)"
}

output "private_ips" {
  value = var.enable_asg ? [] : aws_instance.kong[*].private_ip
  description = "Private IPs (empty when using ASG)"
}

output "public_ips" {
  value = var.enable_asg ? [aws_eip.kong.public_ip] : (var.allocate_eip_per_instance ? [aws_eip.kong.public_ip] : aws_instance.kong[*].public_ip)
  description = "Public IPs (always uses EIP when allocate_eip_per_instance is true)"
}

output "kong_eip_allocation_id" {
  value = aws_eip.kong.id
  description = "Elastic IP allocation ID for Kong (for ASG association or manual association)"
}

output "kong_proxy_endpoint" {
  value = "http://${aws_lb.kong.dns_name}"
  description = "Kong Proxy endpoint via ALB"
}

output "kong_admin_endpoint" {
  value = var.allocate_eip_per_instance ? "http://${aws_eip.kong.public_ip}:8001" : (var.enable_asg ? "http://${aws_lb.kong.dns_name}:8001" : (length(aws_instance.kong) > 0 ? "http://${aws_instance.kong[0].private_ip}:8001" : ""))
  description = "Kong Admin API endpoint (uses EIP when allocate_eip_per_instance is true)"
}

output "load_balancer_dns_name" {
  value = aws_lb.kong.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "load_balancer_arn" {
  value = aws_lb.kong.arn
  description = "ARN of the Application Load Balancer"
}

output "target_group_arn" {
  value = aws_lb_target_group.kong.arn
  description = "ARN of the Target Group"
}

output "asg_name" {
  value = var.enable_asg && length(aws_autoscaling_group.kong) > 0 ? aws_autoscaling_group.kong[0].name : null
  description = "Name of the Auto Scaling Group (if enabled)"
}

output "current_instance_count" {
  value = var.enable_asg && length(aws_autoscaling_group.kong) > 0 ? aws_autoscaling_group.kong[0].desired_capacity : (var.enable_asg ? 0 : length(aws_instance.kong))
  description = "Current number of Kong instances"
}