# 주제

테라폼 실습

# 요약

- VPC와 보안 그룹 모듈의 출력값을 활용하는 EC2 모듈 만들기
- 다른 실행 환경의 출력값을 참조하는 네트워크 실행 환경 구성하기

# 학습 내용

## 소주제

### VPC와 보안 그룹 모듈의 출력값을 활용하는 EC2 모듈 만들기

#### 요구사항

- EC2 인스턴스별로 하나의 YAML 파일을 갖는다.
- 앞서 만든 모듈에서 생성된 서브넷과 보안 그룹만 사용한다.
- 루트 볼륨 외 추가 볼륨을 원하는 대로 붙일 수 있어야 한다.
- 퍼블릭 인스턴스인 경우, 반드시 EIP를 연결한다.
- AMI의 아이디는 직접 입력한다.
  > AMI의 아이디를 직접 입력해야 하는 이유:  
  > 아마존 리눅스너 우분투의 최신 이미지 등을 키워드만 입력해서 아이디를 자동으로 찾아오도록 구성한다면 더 사용성이 좋지 않을까?
  > 결론부터 말하자면, 계획은 그럴싸하지만 실제로 그렇게 구성하는 것은 매우 힘들다.  
  > 예를 들어 우분투의 가장 최근(테라폼 반영 명령을 실행하는 시점을 기준으로) 이미지를 검색해서 사용한다면, 기대 상태와 현재 상태 사이에서 리소스 드리프트가 발생하며, 계속해서 EC2 인스턴스를 다시 생성하게 될 것이다.  
  > 그럼 특정 시점에서의 최신 이미지를 검색하는 방법은 없을까? 아쉽게도, AWS AMI 검색 API에서 그러한 필터를 지원하지 않는다. 원하는 종류의 이미지의 아이디를 모두 가져온 다음, 직접 특정 시점에서의 최신 이미지를 찾아내는 로직을 구현해야 할 것이다.
  > 그렇다면 `aws_instance` 리소스 블록에서 `ami_id`값의 변경사항을 `ignore_changes` 플래그를 통해 무시하는 것은 어떨까? 그러면 초기에 EC2 인스턴스를 생성할 당시의 최신 이미지만을 사용할 수 있기 때문에, 이미지를 바꾸고 싶을 때에도 바꾸지 못하는 상황이 발생할 수 있다.  
  > 그러나 이런 점을 모두 차치하더라도 검색을 통해 이미지를 지정하는 것에는 매우 큰 단점이 존재하는데, 애초에 검색이 힘들다는 점이다.
- EC2 키 페어와 IAM 역할은 이미 생성된 것을 사용하거나 지정하지 않는다.
- 필요한 경우 프라이빗 IP를 지정할 수 있어야 한다.
- EBS의 장치 이름은 OS별 AWS 권장사항을 따라야 한다.

#### 입력값 명세

```yaml
env: production
team: devops
service: application

# network 정보
subnet: pri-app
az: a
security_groups:
  - linux

# instance 정보
ami_id: ami-045f2d6eeb07ce8c0
instance_type: t3.micro
ec2_key: terraform-ec2-key
ec2_role: terraform-ec2-role

# volume 정보
root_volume:
  size: 10
additional_volumes:
  - device: /dev/sdf
    type: gp3
    size: 10
```

#### 입력값을 모듈에 전달할 방법 정하기

- VPC별로 순회하며 EC2 모듈을 호출하고, 호출된 모듈 안에서 EC2 인스턴스를 여러 대 만드는 방식 사용

#### 모듈 만들기

- 변수 설정
- 공통 태그 설정
- EC2 인스턴스 생성
- 변수 및 공통 태그 재정의
- 퍼블릭 인스턴스인 경우의 EIP
- 추가 EBS 볼륨
- 변수 타입, 입력값 유효성 검사

```hcl
locals {
  vpc_name = var.vpc_name
  vpc_id   = var.vpc_id

  module_tag = merge(
    var.tags,
    {
      tf_module = "chapter13_ec2"
    }
  )

  # ec2_set 변수 재정의
  ec2_set = {
    for k, v in var.ec2_set : k => merge(v, {
      full_name = "${var.vpc_name}-${split("-", v.subnet)[0]}-${k}",
    })
  }

  # EC2별로 태그를 미리 선언
  ec2_tags = {
    for k, v in local.ec2_set : k => merge(
      local.module_tag,
      {
        Name    = v.full_name
        EC2     = v.full_name
        Env     = v.env
        Team    = v.team
        Service = v.service
        OS      = upper(v.os_type)
      }
    )
  }

  # 유효성 검사를 위한 변수들
  valid_env           = ["develop", "staging", "rc", "production"]
  valid_ebs_type      = ["standard", "gp2", "gp3", "io1", "io2", "sc1", "st1"]
  valid_iops_ebs_type = ["gp3", "io1", "io2"]

  device_name_patterns = {
    linux   = "/dev/sd[fp]" # 리눅스 권장 볼륨 장치 이름
    windows = "xvd[fp]"     # 윈도우 권장 볼륨 장치 이름
  }
}

###################################################
# Create EC2
###################################################
resource "aws_instance" "this" {
  for_each = local.ec2_set

  # required: 반드시 들어가야 하는 값들
  ami                    = each.value.ami_id
  instance_type          = each.value.instance_type
  subnet_id              = var.subnet_id_map[each.value.subnet][each.value.az]
  vpc_security_group_ids = [for sg_name in each.value.security_groups : var.sg_id_map[sg_name]]

  # optional: 입력 안 할 시 null 값이 들어간다.
  iam_instance_profile = each.value.ec2_role
  key_name             = each.value.ec2_key
  private_ip           = each.value.private_ip

  # 루트 볼륨 설정
  root_block_device {
    volume_type           = each.value.root_volume.type
    volume_size           = each.value.root_volume.size
    delete_on_termination = true

    tags = merge(
      local.ec2_tags[each.key],
      {
        Name = "${each.value.full_name}-root"
      }
    )
  }

  tags = local.ec2_tags[each.key]

  lifecycle {
    precondition { # 1. env 이름 유효성 검사
      condition     = contains(local.valid_env, each.value.env)
      error_message = "[${local.vpc_name} VPC/${each.key} EC2] env 값은 반드시 [${join(", ", local.valid_env)}] 중 하나여야 합니다."
    }

    precondition { # 2. 볼륨 타입 유효성 검사
      condition     = contains(local.valid_ebs_type, each.value.root_volume.type)
      error_message = "[${local.vpc_name} VPC/${each.key} EC2] ${each.value.root_volume.type}: 유효하지 않은 볼륨 타입입니다. root_volume.type은 반드시 [${join(", ", local.valid_ebs_type)}] 중 하나여야 합니다."
    }

    precondition { # 4. OS 타입 이름 유효성 검사
      condition     = contains(keys(local.device_name_patterns), each.value.os_type)
      error_message = "[${local.vpc_name} VPC/${each.key} EC2] ${each.value.os_type} : 유효하지 않은 운영체제 타입입니다. os_type은 반드시 [${join(", ", keys(local.device_name_patterns))}] 중 하나여야 합니다."
    }
  }
}

###################################################
# Create EIP
###################################################
# Public EC2인 경우
resource "aws_eip" "this" {
  for_each = {
    for k, v in local.ec2_set : k => v
    if split("-", v.subnet)[0] == "pub"
  }

  domain = "vpc"

  instance                  = aws_instance.this[each.key].id
  associate_with_private_ip = aws_instance.this[each.key].private_ip

  tags = local.ec2_tags[each.key]
}

###################################################
# Additional EBS Volumes
###################################################
locals {
  ec2_volume_set = [
    for ec2_name, ec2_attribute in local.ec2_set : {
      for volume in ec2_attribute.additional_volumes : "${ec2_name}_${volume.device}" => merge(
        { ec2_name = ec2_name }, volume, ec2_attribute
      )
    }
  ]

  merged_ec2_volume_set = module.merge_ec2_volume_set.output
}

module "merge_ec2_volume_set" {
  source = "../chapter9_utility/3_merge_map_in_list"
  input  = local.ec2_volume_set
}

# EBS 볼륨 생성
resource "aws_ebs_volume" "this" {
  for_each          = local.merged_ec2_volume_set
  availability_zone = aws_instance.this[each.value.ec2_name].availability_zone
  size              = each.value.size
  type              = each.value.type
  iops              = each.value.iops

  tags = merge(
    local.ec2_tags[each.value.ec2_name],
    {
      Name = "${each.value.full_name}-${each.value.device}"
    }
  )

  lifecycle {
    precondition { # 2. 볼륨 타입 유효성 검사
      condition     = contains(local.valid_ebs_type, each.value.type)
      error_message = "[${local.vpc_name} VPC/${each.value.full_name} EC2:${each.value.device} EBS] ${each.value.type}: 유효하지 않은 볼륨 타입입니다. additional_volumes.*.type은 반드시 [${join(", ", local.valid_ebs_type)}] 중 하나여야 합니다."
    }

    precondition { # 3. iops 타입 유효성 검사
      condition     = !(!contains(local.valid_iops_ebs_type, each.value.type) && each.value.iops != null)
      error_message = "[${local.vpc_name} VPC/${each.value.full_name} EC2:${each.value.device} EBS] iops를 지정할 수 없는 볼륨 타입입니다. iops를 해제해주세요. iops는 [${join(", ", local.valid_iops_ebs_type)}] 타입들만 지정할 수 있습니다."
    }

    precondition { # 5. 볼륨 장치 이름 유효성 검사
      condition     = can(regex(local.device_name_patterns[each.value.os_type], each.value.device))
      error_message = "[${local.vpc_name} VPC/${each.value.ec2_name} EC2:${each.value.device} EBS] 허용하지 않는 장치 이름입니다. ${each.value.os_type} OS에서 사용 가능한 장치 이름 패턴은 ${local.device_name_patterns[lower(each.value.os_type)]} 입니다."
    }
  }
}

# EBS 볼륨: EC2 인스턴스 연결
resource "aws_volume_attachment" "this" {
  for_each    = local.merged_ec2_volume_set
  device_name = each.value.device
  volume_id   = aws_ebs_volume.this[each.key].id
  instance_id = aws_instance.this[each.value.ec2_name].id
}
```

- 모듈 출력값 설정

```hcl
output "ec2_id" {
  description = "EC2 ID 맵"
  value = {
    for k, v in aws_instance.this : k => v.id
  }
}

output "ec2_info" {
  description = "EC2 정보 맵"
  value = {
    for k, v in aws_instance.this : k => {
      full_name         = local.ec2_set[k].full_name
      instance_id       = v.id
      private_ip        = v.private_ip
      public_ip         = try(aws_eip.this[k].public_ip, "")
      eni_id            = v.primary_network_interface_id
      availability_zone = v.availability_zone
    }
  }
}
```

#### 더 고려해볼 만한 것

- 사용자 데이터 추가
- 런치 템플릿과 오토스케일링 그룹
- 직접 도메인 연결
- AMI 정보 활용

### 다른 실행 환경의 출력값을 참조하는 네트워크 실행 환경 구성하기

#### 미리 고려해야 할 점

- 다중 프로바이더 환경에서의 피어링 요청 수락
  > `aws_peering_connection_acceptor` 리소스 블록의 `auto_accept` 설정값 활용
- 모듈로 두 개의 프로바이더 전달하기
  > 테라폼 프로바이더에는 반복문을 사용할 수 없다. 모듈을 선언할 때 요청자와 수락자 프로바이더를 각각 입력받을 수 있도록 해야 하며, 실행 환경에서 프로바이더의 쌍만큼 모듈을 호출해야 한다.

#### 요구사항 정리하기

- `topology.yaml` 파일을 생성하여 네트워크 구성을 기술하고, 이것을 사용해 피어링 모듈을 호출한다.
- `env_seoul`과 `env_virginia` 실행 환경에서 만든 VPC를 사용해야 한다. 즉 다른 실행 환경의 상태에 있는 출력값을 가져와야 한다. 이를 위해 원격 상태를 AWS S3를 통해 구성해야 한다.
- VPC 피어링을 맺게 되는 경우, 항상 DNS Resolution을 활성화한다.
- VPC 피어링을 맺게 되는 경우, 상태 VPC로의 라우트를 각 VPC에 속한 모든 라우트 테이블에 자동으로 추가한다.

#### 원격 상태 설정하기

```hcl
# env_seoul
terraform {
  backend "s3" {
    bucket  = "terraform-overdose-tfstate"
    key     = "seoul.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
    profile = "terraform"
  }
}

# env_virginia
terraform {
  backend "s3" {
    bucket  = "terraform-overdose-tfstate"
    key     = "virginia.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
    profile = "terraform"
  }
}
```

#### 입력값과 전달 방식 정의하기

```yaml
# topology.yaml

prod_peering:
  requester:
    tf_env: seoul
    vpc: seoul-prod
  accepter:
    tf_env: virginia
    vpc: virginia-prod

dev_peering:
  requester:
    tf_env: seoul
    vpc: seoul-dev
  accepter:
    tf_env: virginia
    vpc: virginia-dev

seoul_peering:
  requester:
    tf_env: seoul
    vpc: seoul-prod
  accepter:
    tf_env: seoul
    vpc: seoul-dev
```

```hcl
locals {
  topology = yamldecode(file("./topology.yaml"))

  # 테라폼 상태 파일 이름의 리스트
  tf_vpc_env_list = distinct(flatten([
    for k, v in local.topology : [v.requester.tf_env, v.accepter.tf_env]
  ]))

  vpc_ids = {
    for k, v in data.terraform_remote_state.vpc : k => v.outputs.vpc_id
  }

  env_tags = {
    tf_env = "part4/chapter14/env_network"
  }
}

# VPC ID 정보를 받아오기 위한 원격 상태 불러오기
data "terraform_remote_state" "vpc" {
  for_each = toset(local.tf_vpc_env_list)
  backend  = "s3"
  config = {
    bucket  = "terraform-overdose-tfstate"
    key     = "${each.key}.tfstate"
    region  = "ap-northeast-2"
    profile = "terraform"
  }
}
```

#### 모듈 만들기

```hcl
###################################################
# 수락자 계정의 정보 불러오기
###################################################
module "accepter" {
  source = "../chapter9_utility/1_get_aws_metadata"
  providers = {
    aws = aws.accepter
  }
}

###################################################
# VPC 정보 불러오기
###################################################
data "aws_vpc" "requester" {
  provider = aws.requester
  id       = var.requester_vpc_id
}

data "aws_vpc" "accepter" {
  provider = aws.accepter
  id       = var.accepter_vpc_id
}

###################################################
# 라우팅 테이블 정보 불러오기
###################################################
data "aws_route_tables" "requester" {
  provider = aws.requester
  vpc_id   = var.requester_vpc_id
}

data "aws_route_tables" "accepter" {
  provider = aws.accepter
  vpc_id   = var.accepter_vpc_id
}

###################################################
# 로컬 변수 정의
###################################################
locals {
  # 피어링 맺을 때 필요한 accepter 프로바이더 정보
  accepter_account_id = module.accepter.account_id
  accepter_region     = module.accepter.region_name

  # 데이터 블록으로 조회한 VPC 정보
  requester_vpc = data.aws_vpc.requester
  accepter_vpc  = data.aws_vpc.accepter

  # 데이터 블록으로 조회한 라우팅 테이블들 정보
  requester_rtbs = data.aws_route_tables.requester.ids
  accepter_rtbs  = data.aws_route_tables.accepter.ids

  # 모듈 내 공통 태그
  module_tag = merge(
    var.tags,
    {
      Name          = var.name
      tf_module     = "chapter14_vpc_peering"
      Requester_VPC = lookup(local.requester_vpc.tags, "Name", "네임태그없음")
      Accepter_VPC  = lookup(local.accepter_vpc.tags, "Name", "네임태그없음")
    }
  )
}
```

```hcl
###################################################
# VPC Peering Connection
###################################################
resource "aws_vpc_peering_connection" "this" {
  provider = aws.requester

  vpc_id = local.requester_vpc.id

  peer_vpc_id   = local.accepter_vpc.id
  peer_owner_id = local.accepter_account_id
  peer_region   = local.accepter_region

  # accepter 리소스를 별도로 생성할 것이기 때문에 false
  auto_accept = false

  tags = local.module_tag
}

###################################################
# VPC Peering Accepter
###################################################
resource "aws_vpc_peering_connection_accepter" "this" {
  provider                  = aws.accepter
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
  auto_accept               = true # 여기에서 auto_accept 설정

  tags = local.module_tag
}

locals {
  # aws_vpc_peering_connection.this.id = aws_vpc_peering_connection_accepter.this.id
  # 수락이 완료된 후에 다른 리소스들을 생성하기 위해 accepter의 id를 사용
  peering_id = aws_vpc_peering_connection_accepter.this.id
}

###################################################
# VPC Peering Option
###################################################
resource "aws_vpc_peering_connection_options" "requester" {
  provider = aws.requester

  vpc_peering_connection_id = local.peering_id

  requester {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_vpc_peering_connection_options" "accepter" {
  provider = aws.accepter

  vpc_peering_connection_id = local.peering_id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}

###################################################
# 각 VPC 내 모든 라우팅 테이블에 라우트 추가
###################################################
resource "aws_route" "requester_to_accepter" {
  for_each = toset(local.requester_rtbs)
  provider = aws.requester

  route_table_id            = each.key
  destination_cidr_block    = local.accepter_vpc.cidr_block
  vpc_peering_connection_id = local.peering_id
}

resource "aws_route" "accepter_to_requester" {
  for_each = toset(local.accepter_rtbs)
  provider = aws.accepter

  route_table_id            = each.key
  destination_cidr_block    = local.requester_vpc.cidr_block
  vpc_peering_connection_id = local.peering_id
}
```

```hcl
variable "name" {
  description = "VPC 피어링의 이름"
  type        = string
}

variable "requester_vpc_id" {
  description = "요청자 VPC의 ID"
  type        = string
}

variable "accepter_vpc_id" {
  description = "수락자 VPC의 ID"
  type        = string
}

variable "tags" {
  description = "모든 리소스에 적용될 태그 (map)"
  type        = map(string)
  default     = {}
}
```

# 추가

- [Topology](https://www.ibm.com/kr-ko/think/topics/network-topology)
- [AWS VPC Peering](https://docs.aws.amazon.com/ko_kr/vpc/latest/peering/what-is-vpc-peering.html)
