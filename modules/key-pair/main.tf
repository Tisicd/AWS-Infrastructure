# =============================================================================
# Key Pair Module
# =============================================================================
# Crea un Key Pair SSH si no existe, o usa uno existente
# =============================================================================

# Generar clave privada localmente
resource "tls_private_key" "key_pair" {
  count = var.create_key_pair ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

# Crear Key Pair en AWS
resource "aws_key_pair" "this" {
  count = var.create_key_pair ? 1 : 0

  key_name   = var.key_pair_name
  public_key = tls_private_key.key_pair[0].public_key_openssh

  tags = merge(
    var.tags,
    {
      Name        = var.key_pair_name
      ManagedBy   = "Terraform"
      Created     = timestamp()
    }
  )
}

# Guardar clave privada localmente (opcional, solo si se especifica path)
resource "local_file" "private_key" {
  count = var.create_key_pair && var.save_private_key && var.private_key_path != "" ? 1 : 0

  content              = tls_private_key.key_pair[0].private_key_pem
  filename             = var.private_key_path
  file_permission      = "0600"
  directory_permission = "0755"

  depends_on = [aws_key_pair.this]
  
  # Lifecycle para evitar recrear el archivo si ya existe
  lifecycle {
    create_before_destroy = false
    ignore_changes = [content]
  }
}

# Data source para obtener key pair existente (si no se crea)
data "aws_key_pair" "existing" {
  count = var.create_key_pair ? 0 : 1

  key_name = var.key_pair_name

  # Si el key pair no existe, esto causará un error - esperado para validar
}
