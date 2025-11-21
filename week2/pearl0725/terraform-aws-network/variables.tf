variable "region" {
  type        = string
  description = "AWS Region"
  default     = "ap-northeast-2"
}

variable "project" {
  type        = string
  description = "Project name"
  default     = "practice"
}

variable "all_cidr" {
  type        = string
  description = "Any IPv4 CIDR"
  default     = "0.0.0.0/0"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "enable_dns_hostname" {
  type        = bool
  description = "Enable DNS hostnames"
  default     = true
}

variable "enable_dns_support" {
  type        = bool
  description = "Enable DNS support"
  default     = true
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDR block"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDR block"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Enable NAT gateway"
  default     = true
}

variable "map_public_ip_on_launch" {
  type        = bool
  description = "Public IP on"
  default     = true
}