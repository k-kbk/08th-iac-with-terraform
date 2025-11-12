provider "aws" {
  region = "ap-northeast-1"
}

# VPC 생성
resource "aws_vpc" "tf-vpc" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "study-vpc"
  }
}

# ----------------------- Internet Gateway ------------------------------

# 인터넷 게이트웨이 생성
resource "aws_internet_gateway" "tf-igw" {
  vpc_id = aws_vpc.tf-vpc.id

  tags = {
    Name = "tf-igw"
  }
}

# ----------------------- Availability Zone ------------------------------

# AZ 데이터소스
data "aws_availability_zones" "available" {
  state = "available" # 현재 사용가능한 AZ만
}

# ----------------------- Public/Private Subnet ------------------------------

# AZ 3곳에 퍼블릭 서브넷 생성
resource "aws_subnet" "public_subnet" {
  count                   = 3
  vpc_id                  = aws_vpc.tf-vpc.id
  cidr_block              = "10.0.${count.index * 2}.0/24" 
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet AZ ${count.index + 1}"
  }
}

# AZ 3곳에 프라이빗 서브넷 생성
resource "aws_subnet" "private_subnet" {
  count             = 3
  vpc_id            = aws_vpc.tf-vpc.id
  cidr_block        = "10.0.${count.index * 2 + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "Private Subnet AZ ${count.index + 1}"
  }
}

# AZ 3곳에 폐쇄 서브넷 생성
resource "aws_subnet" "no_internet_subnet" {
  count             = 3
  vpc_id            = aws_vpc.tf-vpc.id
  cidr_block        = "10.0.${count.index + 6}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "No Internet Subnet AZ ${count.index + 1}"
  }
}


# ----------------------- Public NAT ------------------------------

# NAT에 할당할 Elastic IP 생성
resource "aws_eip" "nat_eip" {
  tags = {
    Name = "EIP for NAT Gateway"
  }
}

# NAT Gateway 생성(첫번째 퍼블릭 서브넷에 배포)
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet[0].id

  tags = {
    Name = "NAT Gateway"
  }
}

# ----------------------- Public Routing Table ------------------------------

# 퍼블릭 서브넷에 연결할 라우팅 테이블 생성
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.tf-vpc.id

  route { # 인터넷으로 나가는 라우팅
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tf-igw.id # 인터넷 게이트웨이
  }

  tags = {
    Name = "Public Route Table"
  }
}

# 퍼블릭 라우팅 테이블 Association
resource "aws_route_table_association" "public_subnet_route_table_assoc" {
  count          = 3
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# ----------------------- Private Routing Table ------------------------------

# 프라이빗 서브넷에 연결할 라우팅 테이블 생성
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.tf-vpc.id

  route { # 인터넷으로 나가는 라우팅
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gateway.id # NAT 게이트웨이
  }

  tags = {
    Name = "Private Route Table"
  }
}

# 프라이빗 라우팅 테이블 Association
resource "aws_route_table_association" "private_subnet_route_table_assoc" {
  count          = 3
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# ----------------------- No Internet Routing Table ------------------------------

# No Internet 서브넷에 연결할 라우팅 테이블 생성
resource "aws_route_table" "no_internet_route_table" {
  vpc_id = aws_vpc.tf-vpc.id

  route { # 라우팅 -> local
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  tags = {
    Name = "No Internet Route Table"
  }
}

# No Internet 라우팅 테이블 Association
resource "aws_route_table_association" "no_internet_subnet_route_table_assoc" {
  count          = 3
  subnet_id      = aws_subnet.no_internet_subnet[count.index].id
  route_table_id = aws_route_table.no_internet_route_table.id
}