###################################################
# Public Subent
###################################################

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(
    local.tags,
    {
      Name = "${local.name_prefix}-sub-pub-${local.az_suffix[count.index]}"
    },
  )
}

###################################################
# Private Subent
###################################################

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(
    local.tags,
    {
      Name = "${local.name_prefix}-sub-pri-${local.az_suffix[count.index]}"
    },
  )
}