# =============================================================================
# Database Server Module (PostgreSQL + Redis + TimescaleDB)
# =============================================================================

resource "aws_instance" "database" {
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
    environment        = var.environment
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-database"
      Role = "Database"
    }
  )
}

resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.database.availability_zone
  size              = var.data_volume_size
  type              = var.data_volume_type
  encrypted         = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-database-data"
    }
  )
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.database.id
}

resource "aws_eip" "database" {
  count  = var.allocate_eip ? 1 : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-database-eip"
    }
  )
}

resource "aws_eip_association" "database" {
  count         = var.allocate_eip ? 1 : 0
  instance_id   = aws_instance.database.id
  allocation_id = aws_eip.database[0].id
}

output "instance_id" {
  value = aws_instance.database.id
}

output "private_ip" {
  value = aws_instance.database.private_ip
}

output "public_ip" {
  value = var.allocate_eip ? (length(aws_eip.database) > 0 ? aws_eip.database[0].public_ip : null) : null
}

output "postgres_endpoint" {
  value = "${aws_instance.database.private_ip}:5432"
}

output "redis_endpoint" {
  value = "${aws_instance.database.private_ip}:6379"
}

output "timescaledb_endpoint" {
  value = var.enable_timescaledb ? "${aws_instance.database.private_ip}:5433" : null
}

