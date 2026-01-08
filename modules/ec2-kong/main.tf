# =============================================================================
# Kong API Gateway Module
# =============================================================================

resource "aws_instance" "kong" {
  count = var.instance_count

  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  subnet_id     = var.subnet_ids[count.index % length(var.subnet_ids)]

  vpc_security_group_ids = [var.security_group_id]

  root_block_device {
    volume_size = 20
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
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-kong-${count.index + 1}"
      Role = "Kong-API-Gateway"
    }
  )
}

resource "aws_eip" "kong" {
  count  = var.allocate_eip_per_instance ? var.instance_count : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-kong-eip-${count.index + 1}"
    }
  )
}

resource "aws_eip_association" "kong" {
  count         = var.allocate_eip_per_instance ? var.instance_count : 0
  instance_id   = aws_instance.kong[count.index].id
  allocation_id = aws_eip.kong[count.index].id
}

output "instance_ids" {
  value = aws_instance.kong[*].id
}

output "private_ips" {
  value = aws_instance.kong[*].private_ip
}

output "public_ips" {
  value = var.allocate_eip_per_instance ? aws_eip.kong[*].public_ip : aws_instance.kong[*].public_ip
}

output "kong_proxy_endpoint" {
  value = var.allocate_eip_per_instance ? "http://${aws_eip.kong[0].public_ip}" : "http://${aws_instance.kong[0].public_ip}"
}

output "kong_admin_endpoint" {
  value = var.allocate_eip_per_instance ? "http://${aws_eip.kong[0].public_ip}:8001" : "http://${aws_instance.kong[0].public_ip}:8001"
}

