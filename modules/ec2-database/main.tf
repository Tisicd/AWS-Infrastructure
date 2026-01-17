# =============================================================================
# Database Server Module (PostgreSQL + Redis + TimescaleDB) with Auto Recovery
# =============================================================================

data "aws_region" "current" {}

# Elastic IP for Database (always created when allocate_eip is true)
resource "aws_eip" "database" {
  count  = var.allocate_eip ? 1 : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-database-eip"
      Role        = "Database"
      Persistent  = "true"
      AutoManaged = "true"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Data source to get subnet availability zone
data "aws_subnet" "database_subnet" {
  id = var.subnet_id
}

# EBS Volume for Database Data (persists across instance replacements)
resource "aws_ebs_volume" "data" {
  availability_zone = var.subnet_availability_zone != "" ? var.subnet_availability_zone : data.aws_subnet.database_subnet.availability_zone
  size              = var.data_volume_size
  type              = var.data_volume_type
  encrypted         = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-database-data"
      Role        = "Database"
      Persistent  = "true"
      AutoManaged = "true"
    }
  )

  lifecycle {
    prevent_destroy = false
  }
}

# Launch Template for Database instances
resource "aws_launch_template" "database" {
  name_prefix   = "${var.project_name}-${var.environment}-database-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [var.security_group_id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    postgres_version   = var.postgres_version
    redis_version      = var.redis_version
    enable_timescaledb = var.enable_timescaledb
    enable_mongodb     = var.enable_mongodb
    mongodb_version    = var.mongodb_version
    environment        = var.environment
    eip_allocation_id  = var.enable_asg && var.allocate_eip ? aws_eip.database[0].id : ""
    associate_eip      = var.enable_asg && var.allocate_eip ? "true" : "false"
    data_volume_id     = var.enable_asg ? aws_ebs_volume.data.id : ""
    attach_data_volume = var.enable_asg ? "true" : "false"
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.root_volume_size
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-${var.environment}-database"
        Role = "Database"
      }
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for Database (optional, for auto-recovery)
resource "aws_autoscaling_group" "database" {
  count = var.enable_asg ? 1 : 0

  name = "${var.project_name}-${var.environment}-database-asg"

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  health_check_type         = "EC2"
  health_check_grace_period = 600  # Database needs more time to initialize

  vpc_zone_identifier = [var.subnet_id]

  launch_template {
    id      = aws_launch_template.database.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-database"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "Database"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# Null resource to associate EIP with ASG instances after they are created
# This ensures EIP is associated automatically via Terraform, not just user-data
resource "null_resource" "database_eip_association" {
  count = var.enable_asg && var.allocate_eip && length(aws_autoscaling_group.database) > 0 ? 1 : 0

  triggers = {
    asg_name      = aws_autoscaling_group.database[0].name
    eip_allocation_id = aws_eip.database[0].id
    asg_arn       = aws_autoscaling_group.database[0].arn
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command = <<-EOT
      Start-Sleep -Seconds 60
      $asgName = "${aws_autoscaling_group.database[0].name}"
      $eipAllocId = "${aws_eip.database[0].id}"
      $region = "${data.aws_region.current.name}"
      
      $instanceId = aws autoscaling describe-auto-scaling-groups `
        --auto-scaling-group-names $asgName `
        --query 'AutoScalingGroups[0].Instances[?HealthStatus==`Healthy`].InstanceId' `
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

  depends_on = [aws_autoscaling_group.database, aws_eip.database]
}

# EC2 Instance (when ASG is disabled)
resource "aws_instance" "database" {
  count = var.enable_asg ? 0 : 1

  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [var.security_group_id]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    postgres_version   = var.postgres_version
    redis_version      = var.redis_version
    enable_timescaledb = var.enable_timescaledb
    enable_mongodb     = var.enable_mongodb
    mongodb_version    = var.mongodb_version
    environment        = var.environment
    eip_allocation_id  = ""
    associate_eip      = "false"
    data_volume_id     = ""
    attach_data_volume = "false"
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-database"
      Role = "Database"
    }
  )
}

# Volume Attachment (only when ASG is disabled)
resource "aws_volume_attachment" "data" {
  count       = var.enable_asg ? 0 : 1
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.database[0].id
}

# Elastic IP Association (only when ASG is disabled)
resource "aws_eip_association" "database" {
  count         = var.enable_asg ? 0 : (var.allocate_eip ? 1 : 0)
  instance_id   = aws_instance.database[0].id
  allocation_id = aws_eip.database[0].id

  lifecycle {
    create_before_destroy = true
  }
}

# Note: When ASG is enabled, we cannot reliably get the private IP during plan phase
# The ASG instances are created dynamically and their IPs are only known after apply
# For endpoints, we will return null when ASG is enabled - the actual IP will be available
# after the first apply when instances are created by the ASG

# CloudWatch Alarm for EC2 Auto Recovery (when ASG is disabled)
resource "aws_cloudwatch_metric_alarm" "database_instance_recovery" {
  count = var.enable_asg ? 0 : 1

  alarm_name          = "${var.project_name}-${var.environment}-database-recovery"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed_System"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "0"
  alarm_description   = "Trigger EC2 Auto Recovery when system status check fails for Database instance"

  dimensions = {
    InstanceId = aws_instance.database[0].id
  }

  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.name}:ec2:recover"
  ]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-database-recovery-alarm"
    }
  )
}

output "instance_id" {
  # When ASG is enabled, instance IDs are managed by ASG and not directly accessible
  # Use the ASG name to query instances via AWS CLI or console
  value = var.enable_asg ? null : (length(aws_instance.database) > 0 ? aws_instance.database[0].id : null)
}

# Data source to get ASG instance private IP (when ASG is enabled)
# This will attempt to get the private IP from the first healthy instance in the ASG
# Note: This data source will return empty during the first plan if instances don't exist yet
data "aws_instances" "database_asg_instances" {
  count = var.enable_asg && length(aws_autoscaling_group.database) > 0 ? 1 : 0

  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.database[0].name]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }

  # Explicit dependency to ensure ASG exists before querying
  depends_on = [aws_autoscaling_group.database]
}

output "private_ip" {
  description = "Private IP of Database Server. When ASG is enabled, this may be null initially until instances are created."
  # When ASG is enabled, try to get IP from ASG instances data source
  # Otherwise use direct instance reference
  # Note: If ASG instances don't exist yet (first apply), this will return null
  value = var.enable_asg ? (
    length(aws_autoscaling_group.database) > 0 && length(data.aws_instances.database_asg_instances) > 0 && 
    length(data.aws_instances.database_asg_instances[0].private_ips) > 0 ? 
    data.aws_instances.database_asg_instances[0].private_ips[0] : null
  ) : (
    length(aws_instance.database) > 0 ? aws_instance.database[0].private_ip : null
  )
}

output "public_ip" {
  value = var.allocate_eip ? (length(aws_eip.database) > 0 ? aws_eip.database[0].public_ip : null) : null
}

output "eip_allocation_id" {
  value = var.allocate_eip ? aws_eip.database[0].id : null
}

output "data_volume_id" {
  value = aws_ebs_volume.data.id
}

output "asg_name" {
  value = var.enable_asg && length(aws_autoscaling_group.database) > 0 ? aws_autoscaling_group.database[0].name : null
}

output "postgres_endpoint" {
  # When ASG is enabled, endpoint will be null initially
  # After apply, use the EIP public IP or query the ASG instance IP directly
  value = var.enable_asg ? null : (length(aws_instance.database) > 0 ? "${aws_instance.database[0].private_ip}:5432" : null)
}

output "redis_endpoint" {
  # When ASG is enabled, endpoint will be null initially
  # After apply, use the EIP public IP or query the ASG instance IP directly
  value = var.enable_asg ? null : (length(aws_instance.database) > 0 ? "${aws_instance.database[0].private_ip}:6379" : null)
}

output "timescaledb_endpoint" {
  # When ASG is enabled, endpoint will be null initially
  # After apply, use the EIP public IP or query the ASG instance IP directly
  value = var.enable_asg ? null : (var.enable_timescaledb && length(aws_instance.database) > 0 ? "${aws_instance.database[0].private_ip}:5433" : null)
}

output "mongodb_endpoint" {
  # When ASG is enabled, endpoint will be null initially
  # After apply, use the EIP public IP or query the ASG instance IP directly
  value = var.enable_asg ? null : (var.enable_mongodb && length(aws_instance.database) > 0 ? "${aws_instance.database[0].private_ip}:27017" : null)
}
