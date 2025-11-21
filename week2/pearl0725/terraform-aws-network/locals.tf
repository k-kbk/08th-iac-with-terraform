locals {
  name_prefix = var.project 

  az_suffix = [
    for az in var.azs :
    replace(az, "/.*-(..)$/", "$1")
  ]

  tags = {
    Project = var.project
  }
}