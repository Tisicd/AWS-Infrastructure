# NAT Gateway Module (Optional for private subnets)
resource "aws_eip" "nat" {
  count  = var.nat_gateway_count
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}" })
}

resource "aws_nat_gateway" "main" {
  count         = var.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  tags          = merge(var.tags, { Name = "${var.project_name}-${var.environment}-nat-${count.index + 1}" })
}

resource "aws_route_table" "private" {
  count  = var.single_nat_gateway ? 1 : length(var.private_subnet_ids)
  vpc_id = var.vpc_id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index % var.nat_gateway_count].id
  }
  tags = merge(var.tags, { Name = "${var.project_name}-${var.environment}-private-rt-${count.index + 1}" })
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_ids)
  subnet_id      = var.private_subnet_ids[count.index]
  route_table_id = var.single_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[count.index % length(aws_route_table.private)].id
}

output "nat_gateway_ids" { value = aws_nat_gateway.main[*].id }
output "nat_gateway_ips" { value = aws_eip.nat[*].public_ip }

