# 주제

YAML 설정을 통한 유연한 Terraform VPC 모듈 설계 및 구현 (IaC 로직과 데이터 분리)

# 요약

-   인프라의 로직(Terraform Code)과 설정값(YAML Configuration)을 분리하여 관리하는 방법 학습
-   AWS VPC 구성 모범 사례(Best Practice)인 고가용성(Multi-AZ)과 확장성을 준수
-   복잡한 네트워크 연산(CIDR 계산, 서브넷 할당) 자동화 모듈 설계 요구사항 정의

# 학습 내용

## VPC 인프라 구성 다양성 및 모범 사례 (Best Practice)

-   구성의 다양성
    -   엔지니어 및 조직 컨벤션에 따라 CIDR 크기, 서브넷 기준, NAT 개수 등 구성 방식 상이
-   모범 사례 (암묵적 합의)
    -   서브넷: 동일 용도 서브넷은 최소 2개 이상 가용 영역(AZ)에 분산 배치하여 고가용성 확보
    -   NAT 게이트웨이: 원칙적으로 가용 영역별(최소 2개) 생성하여 안정성 확보 (단, 개발 환경 등 비용 우선 시 1개 운영)

2. 모듈 설계 요구사항

-   서브넷 규격: 모든 서브넷은 동일한 크기(CIDR) 보유
-   이름 및 라우팅 규칙:

    -   pub-: 퍼블릭 서브넷 (IGW 연결, 라우트 테이블 1개)
    -   pri-: 프라이빗 서브넷 (NAT 연결, AZ 개수만큼 라우트 테이블 생성)

-   유연성: 용도별 서브넷의 가용 영역(AZ) 개수 임의 지정 가능
-   게이트웨이 자동화:
    -   IGW: 퍼블릭 서브넷 존재 시 자동 생성
    -   NAT: 설정 플래그(create, per_az)에 따라 생성 여부 및 개수 제어

3. 입력값(YAML) 명세 구조

-   cidr: VPC 전체 IP 대역
-   subnet_newbits: 서브넷 분할을 위한 추가 비트 수 (고정값, 변경 시 재생성 필요)
-   subnet_azs: 사용할 가용 영역 접미사 목록 (예: a, c, b, d)
-   subnets: {이름}: {네트워크 넘버 리스트} 형태의 맵핑
    -   예: pri-db: [4, 5] → 4번째, 5번째 네트워크 대역 할당
-   nat: 생성 여부 및 배치 전략 설정 파라미터

# 실습

## 디렉터리 구조

```bash
.
├── env
│   ├── main.tf        # YAML 파싱 및 리소스 생성 로직
│   └── versions.tf    # Terraform Provider 설정
└── vpc_info_files
    └── production
        └── vpc.yaml   # 교재 내 정의된 설정 파일
```

## 파일 상세

A. `vpc_info_files/production/vpc.yaml`

교재 코드 11-1 내용 적용

```yaml
cidr: 10.0.0.0/16
env: production
team: devops

subnet_newbits: 8
subnet_azs: [a, c, b, d]

subnets:
    pub-nat: [0, 1]
    pri-app: [2, 3]
    pri-db: [4, 5]
    pri-network: [6, 7]
    pri-msk: [8, 9, 10]

nat:
    create: true
    subnet: pub-nat
    per_az: true
```

B. `env/versions.tf`

```tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}
```

C. `env/main.tf` (핵심 로직)
YAML 파일 로드 및 동적 리소스 생성 구현

```tf
locals {
  # 1. YAML 파일 로드
  config = yamldecode(file("${path.module}/../vpc_info_files/production/vpc.yaml"))

  # 2. 서브넷 데이터 가공 (Flatten)
  subnet_list = flatten([
    for name, netnums in local.config.subnets : [
      for index, netnum in netnums : {
        name       = name
        netnum     = netnum
        cidr       = cidrsubnet(local.config.cidr, local.config.subnet_newbits, netnum)
        # subnet_azs 리스트 순환 할당
        az_suffix  = local.config.subnet_azs[index % length(local.config.subnet_azs)]
        is_public  = startswith(name, "pub-")
      }
    ]
  ])
}

# --- VPC 생성 ---
resource "aws_vpc" "this" {
  cidr_block           = local.config.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${local.config.team}-${local.config.env}-vpc"
    Environment = local.config.env
    Team        = local.config.team
  }
}

# --- 서브넷 생성 (Dynamic) ---
resource "aws_subnet" "this" {
  for_each = { for subnet in local.subnet_list : "${subnet.name}-${subnet.netnum}" => subnet }

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = "ap-northeast-2${each.value.az_suffix}"

  # pub- 접두사 서브넷은 퍼블릭 IP 자동 할당
  map_public_ip_on_launch = each.value.is_public

  tags = {
    Name = "${local.config.env}-${each.value.name}-${each.value.az_suffix}"
  }
}

# --- 인터넷 게이트웨이 ---
resource "aws_internet_gateway" "this" {
  # 퍼블릭 서브넷 존재 시 1개 생성
  count = anytrue([for s in local.subnet_list : s.is_public]) ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.config.env}-igw"
  }
}

# --- 결과 확인용 Output ---
output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "created_subnets" {
  value = [for s in aws_subnet.this : "${s.tags.Name} : ${s.cidr_block}"]
}
```
