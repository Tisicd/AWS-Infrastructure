# =============================================================================
# Bastion Host Module (Jump Box)
# =============================================================================

resource "aws_instance" "bastion" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [var.security_group_id]

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
              #!/bin/bash
              # Update system
              yum update -y
              
              # Install useful tools
              yum install -y htop tmux vim git
              
              # Configure SSH
              echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
              systemctl restart sshd
              
              # Create welcome message
              cat > /etc/motd <<WELCOME
              ================================================
              Academic Platform - Bastion Host
              Environment: ${var.environment}
              ================================================
WELCOME
              EOF

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-bastion"
      Role = "Bastion"
    }
  )
}

resource "aws_eip" "bastion" {
  count  = var.allocate_eip ? 1 : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-bastion-eip"
    }
  )
}

resource "aws_eip_association" "bastion" {
  count         = var.allocate_eip ? 1 : 0
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion[0].id
}

output "instance_id" {
  value = aws_instance.bastion.id
}

output "private_ip" {
  value = aws_instance.bastion.private_ip
}

output "public_ip" {
  value = var.allocate_eip ? aws_eip.bastion[0].public_ip : aws_instance.bastion.public_ip
}

