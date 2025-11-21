###################################################
# Public Subent RT
###################################################

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = var.all_cidr
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.name_prefix}-sub-pub-rt"
    },
  )
}

###################################################
# Private Subent RT
###################################################

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = var.all_cidr
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.name_prefix}-sub-pri-rt"
    },
  )
}

###################################################
# Public Subent RT Association
###################################################

resource "aws_route_table_association" "public_rt" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

###################################################
# Private Subent RT Association
###################################################

resource "aws_route_table_association" "private_rt" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_rt.id
}