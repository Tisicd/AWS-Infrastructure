# =============================================================================
# Microservices Auto Scaling Group Module
# =============================================================================

# Elastic IPs for Microservices (one per service)
# These EIPs will be associated with instances automatically via user-data script
resource "aws_eip" "microservices" {
  count = var.enable_elastic_ips ? length(var.services) : 0

  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-eip-${var.services[count.index].name}"
      Service     = var.services[count.index].name
      Purpose     = "Microservice-EIP"
      AutoManaged = "true"
      Index       = tostring(count.index)
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Data source to get EIP information for user-data
data "aws_region" "current" {}

resource "aws_launch_template" "microservices" {
  name_prefix   = "${var.project_name}-${var.environment}-microservices-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [var.security_group_id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    environment           = var.environment
    database_host         = var.database_host
    redis_host            = var.redis_host
    kong_endpoint         = var.kong_endpoint
    services              = jsonencode(var.services)
    docker_registry       = var.docker_registry
    docker_username       = var.docker_registry_username
    docker_password       = var.docker_registry_password
    enable_elastic_ips    = var.enable_elastic_ips ? "true" : "false"
    aws_region            = data.aws_region.current.name
    eip_tag_name          = "${var.project_name}-${var.environment}-eip-"
    project_name          = var.project_name
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
        Name = "${var.project_name}-${var.environment}-microservice"
        Role = "Microservices"
      }
    )
  }
}

# Application Load Balancer
resource "aws_lb" "microservices" {
  count = var.enable_load_balancer ? 1 : 0

  # AWS Load Balancer name limit: 32 characters
  # Using shortened name: acad-plat-qa-ms-alb (19 chars)
  name               = "acad-plat-${var.environment}-ms-alb"
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
      Name = "${var.project_name}-${var.environment}-microservices-alb"
    }
  )
}

# Target Group for Microservices
resource "aws_lb_target_group" "microservices" {
  count = var.enable_load_balancer ? 1 : 0

  # AWS Target Group name limit: 32 characters
  # Using shortened name: acad-plat-qa-ms-tg (17 chars)
  name     = "acad-plat-${var.environment}-ms-tg"
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
      Name = "${var.project_name}-${var.environment}-microservices-tg"
    }
  )
}

# ALB Listener
resource "aws_lb_listener" "microservices" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.microservices[0].arn
  port              = var.load_balancer_listener_port
  protocol          = var.load_balancer_listener_protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.microservices[0].arn
  }
}

resource "aws_autoscaling_group" "microservices" {
  name = "${var.project_name}-${var.environment}-microservices-asg"

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  health_check_type         = var.enable_load_balancer ? "ELB" : var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.microservices.id
    version = "$Latest"
  }

  # Automatic Target Group registration when Load Balancer is enabled
  # All instances are automatically registered to the target group on creation
  target_group_arns = var.enable_load_balancer ? [aws_lb_target_group.microservices[0].arn] : []

  # Instance replacement policy for high availability
  termination_policies = ["OldestInstance"]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-microservice"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
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

# Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  count = var.enable_scaling_policies ? 1 : 0

  name                   = "${var.project_name}-${var.environment}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.microservices.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = var.scale_up_adjustment
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_down" {
  count = var.enable_scaling_policies ? 1 : 0

  name                   = "${var.project_name}-${var.environment}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.microservices.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = var.scale_down_adjustment
  cooldown               = 300
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.enable_scaling_policies ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.scale_up_cpu_threshold

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.microservices.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_up[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  count = var.enable_scaling_policies ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.scale_down_cpu_threshold

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.microservices.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_down[0].arn]
}

# Null resource to associate EIPs with ASG instances after they are created
# This ensures EIPs are associated automatically via Terraform, not just user-data
# One null_resource per service to ensure each service gets its EIP
resource "null_resource" "microservices_eip_association" {
  for_each = var.enable_elastic_ips ? { for idx, svc in var.services : svc.name => idx } : {}

  triggers = {
    asg_name         = aws_autoscaling_group.microservices.name
    eip_allocation_id = aws_eip.microservices[each.value].id
    service_name     = each.key
    asg_arn          = aws_autoscaling_group.microservices.arn
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command = <<-EOT
      Start-Sleep -Seconds 60
      $asgName = "${aws_autoscaling_group.microservices.name}"
      $eipAllocId = "${aws_eip.microservices[each.value].id}"
      $serviceName = "${each.key}"
      $serviceIndex = ${each.value}
      $region = "${data.aws_region.current.name}"
      
      # Get all instance IDs from ASG (healthy instances)
      $instanceIdsOutput = aws autoscaling describe-auto-scaling-groups `
        --auto-scaling-group-names $asgName `
        --query 'AutoScalingGroups[0].Instances[?HealthStatus==`Healthy` || LifecycleState==`InService`].InstanceId' `
        --output text 2>&1
      
      if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to query ASG instances: $instanceIdsOutput"
        exit 1
      }
      
      # Split by whitespace (tabs or spaces) and filter empty values
      $instanceIds = @()
      if ($instanceIdsOutput -and $instanceIdsOutput.Trim() -ne "") {
        # Split by whitespace (spaces, tabs, newlines) and filter for valid instance IDs
        $instanceIds = ($instanceIdsOutput.Trim() -split '\s+' | Where-Object { 
          $_ -and $_.Trim() -ne "" -and $_ -match '^i-[0-9a-f]+$' 
        })
      }
      
      if ($instanceIds.Count -eq 0) {
        Write-Host "No healthy instances found in ASG yet for service $serviceName. Output: $instanceIdsOutput"
        exit 1
      }
      
      # Use modulo to distribute EIPs evenly across instances
      # Each service EIP gets assigned to a specific instance based on service index
      $targetInstanceIndex = $serviceIndex % $instanceIds.Count
      $instanceId = $instanceIds[$targetInstanceIndex]
      
      if (-not $instanceId -or $instanceId -notmatch "^i-[0-9a-f]+$") {
        $errorMsg = "Invalid instance ID extracted: '$instanceId' (index: $targetInstanceIndex, total: $($instanceIds.Count))"
        Write-Host $errorMsg
        exit 1
      }
      
      if ($instanceId -and $instanceId -match "^i-[0-9a-f]+$") {
        Write-Host "Associating EIP $eipAllocId ($serviceName, index $serviceIndex) with instance $instanceId (instance index $targetInstanceIndex)"
        
        # Disassociate EIP from any existing instance first
        try {
          $currentAssociation = aws ec2 describe-addresses --allocation-ids $eipAllocId --region $region --query 'Addresses[0].AssociationId' --output text 2>&1
          if ($LASTEXITCODE -eq 0 -and $currentAssociation -and $currentAssociation -ne "None" -and $currentAssociation.Trim() -ne "") {
            Write-Host "Disassociating EIP $eipAllocId from current association..."
            aws ec2 disassociate-address --association-id $currentAssociation --region $region 2>&1 | Out-Null
            Start-Sleep -Seconds 2
          }
        } catch {
          # Ignore errors during disassociation
        }
        
        # Associate EIP with target instance
        aws ec2 associate-address `
          --instance-id $instanceId `
          --allocation-id $eipAllocId `
          --allow-reassociation `
          --region $region
        
        if ($LASTEXITCODE -eq 0) {
          Write-Host "Successfully associated EIP $eipAllocId ($serviceName) with instance $instanceId"
        } else {
          Write-Host "Failed to associate EIP $eipAllocId with instance $instanceId"
          exit 1
        }
      } else {
        $errorMsg = "Invalid instance ID format for service $serviceName" + ": " + $instanceId
        Write-Host $errorMsg
        exit 1
      }
    EOT
  }

  depends_on = [aws_autoscaling_group.microservices, aws_eip.microservices]
}

# Note: Auto-recovery for microservices is handled automatically by the ASG health checks.
# The ASG will replace unhealthy instances based on health checks (ELB or EC2).
# No additional CloudWatch alarm with ec2:recover is needed because:
# - ASG automatically replaces instances that fail health checks
# - Target Group registration happens automatically on instance creation
# - EIP association happens automatically via user-data script AND null_resource
# - Instance replacement preserves desired_capacity, ensuring continuous service availability

output "asg_name" {
  value = aws_autoscaling_group.microservices.name
}

output "current_instance_count" {
  value = aws_autoscaling_group.microservices.desired_capacity
}

output "load_balancer_dns_name" {
  value = var.enable_load_balancer ? aws_lb.microservices[0].dns_name : null
}

output "load_balancer_arn" {
  value = var.enable_load_balancer ? aws_lb.microservices[0].arn : null
}

output "target_group_arn" {
  value = var.enable_load_balancer ? aws_lb_target_group.microservices[0].arn : null
}

output "elastic_ips" {
  value = var.enable_elastic_ips ? {
    for idx, eip in aws_eip.microservices : var.services[idx].name => eip.public_ip
  } : {}
}

output "elastic_ip_ids" {
  value = var.enable_elastic_ips ? aws_eip.microservices[*].id : []
}
