###################################################
# VPC
###################################################

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  enable_dns_hostnames = var.enable_dns_hostname
  enable_dns_support   = var.enable_dns_support

  tags = merge(
    local.tags,
    {
      Name = "${local.name_prefix}-vpc"
    },
  )
}