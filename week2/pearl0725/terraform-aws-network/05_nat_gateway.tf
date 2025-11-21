###################################################
# NAT Gateway
###################################################

resource "aws_eip" "main" {
  domain = "vpc"

  depends_on = [
    aws_internet_gateway.main
  ]

  tags = merge(
    local.tags,
    {
      Name = "${local.name_prefix}-eip"
    },
  )
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.main.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [
    aws_internet_gateway.main
  ]

  tags = merge(
    local.tags,
    {
      Name = "${local.name_prefix}-nat"
    },
  )
}