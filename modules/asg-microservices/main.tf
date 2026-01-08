# =============================================================================
# Microservices Auto Scaling Group Module
# =============================================================================

resource "aws_launch_template" "microservices" {
  name_prefix   = "${var.project_name}-${var.environment}-microservices-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [var.security_group_id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    environment       = var.environment
    database_host     = var.database_host
    redis_host        = var.redis_host
    kong_endpoint     = var.kong_endpoint
    services          = jsonencode(var.services)
    docker_registry   = var.docker_registry
    docker_username   = var.docker_registry_username
    docker_password   = var.docker_registry_password
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
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

resource "aws_autoscaling_group" "microservices" {
  name = "${var.project_name}-${var.environment}-microservices-asg"

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.microservices.id
    version = "$Latest"
  }

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

output "asg_name" {
  value = aws_autoscaling_group.microservices.name
}

output "current_instance_count" {
  value = aws_autoscaling_group.microservices.desired_capacity
}

