# =============================================================================
# Bastion Host Module (Jump Box) with Auto Recovery
# =============================================================================

# Elastic IP for Bastion (always created when allocate_eip is true)
resource "aws_eip" "bastion" {
  count  = var.allocate_eip ? 1 : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-bastion-eip"
      Role        = "Bastion"
      Persistent  = "true"
      AutoManaged = "true"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Launch Template for Bastion instances
resource "aws_launch_template" "bastion" {
  name_prefix   = "${var.project_name}-${var.environment}-bastion-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [var.security_group_id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    environment       = var.environment
    eip_allocation_id = var.enable_asg && var.allocate_eip ? aws_eip.bastion[0].id : ""
    associate_eip     = var.enable_asg && var.allocate_eip ? "true" : "false"
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
        Name = "${var.project_name}-${var.environment}-bastion"
        Role = "Bastion"
      }
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Data source for current AWS region (needed for null_resource)
data "aws_region" "current" {}

# Auto Scaling Group for Bastion (optional, for auto-recovery)
resource "aws_autoscaling_group" "bastion" {
  count = var.enable_asg ? 1 : 0

  name = "${var.project_name}-${var.environment}-bastion-asg"

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  health_check_type         = "EC2"
  health_check_grace_period = 300

  vpc_zone_identifier = [var.subnet_id]

  launch_template {
    id      = aws_launch_template.bastion.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-bastion"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "Bastion"
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
resource "null_resource" "bastion_eip_association" {
  count = var.enable_asg && var.allocate_eip && length(aws_autoscaling_group.bastion) > 0 ? 1 : 0

  triggers = {
    asg_name      = aws_autoscaling_group.bastion[0].name
    eip_allocation_id = aws_eip.bastion[0].id
    asg_arn       = aws_autoscaling_group.bastion[0].arn
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command = <<-EOT
      Start-Sleep -Seconds 30
      $asgName = "${aws_autoscaling_group.bastion[0].name}"
      $eipAllocId = "${aws_eip.bastion[0].id}"
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

  depends_on = [aws_autoscaling_group.bastion, aws_eip.bastion]
}

# EC2 Instance (when ASG is disabled)
resource "aws_instance" "bastion" {
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
    environment       = var.environment
    eip_allocation_id = ""
    associate_eip     = "false"
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-bastion"
      Role = "Bastion"
    }
  )
}

# Elastic IP Association (only when ASG is disabled)
resource "aws_eip_association" "bastion" {
  count         = var.enable_asg ? 0 : (var.allocate_eip ? 1 : 0)
  instance_id   = aws_instance.bastion[0].id
  allocation_id = aws_eip.bastion[0].id

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch Alarm for EC2 Auto Recovery (when ASG is disabled)
resource "aws_cloudwatch_metric_alarm" "bastion_instance_recovery" {
  count = var.enable_asg ? 0 : 1

  alarm_name          = "${var.project_name}-${var.environment}-bastion-recovery"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed_System"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "0"
  alarm_description   = "Trigger EC2 Auto Recovery when system status check fails for Bastion instance"

  dimensions = {
    InstanceId = aws_instance.bastion[0].id
  }

  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.name}:ec2:recover"
  ]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-bastion-recovery-alarm"
    }
  )
}

output "instance_id" {
  value = var.enable_asg ? (length(aws_autoscaling_group.bastion) > 0 ? null : null) : aws_instance.bastion[0].id
}

output "private_ip" {
  value = var.enable_asg ? null : aws_instance.bastion[0].private_ip
}

output "public_ip" {
  value = var.allocate_eip ? aws_eip.bastion[0].public_ip : (var.enable_asg ? null : aws_instance.bastion[0].public_ip)
}

output "eip_allocation_id" {
  value = var.allocate_eip ? aws_eip.bastion[0].id : null
}

output "asg_name" {
  value = var.enable_asg && length(aws_autoscaling_group.bastion) > 0 ? aws_autoscaling_group.bastion[0].name : null
}

