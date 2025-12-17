# 주제

Chapter 13. VPC와 보안 그룹 모듈의 출력값을 활용하는 EC2 모듈 만들기

Chapter 14. 다른 실행 환경의 출력값을 참조하는 네트워크 실행 환경 구성하기 (VPC Peering)

# 요약

-   13장: 기존 VPC와 보안 그룹의 출력값을 활용해 EC2 인스턴스와 EBS 볼륨을 생성하는 모듈을 구현하며, precondition을 통해 OS별 장치 이름 등 입력값의 유효성을 엄격히 검증하는 방법을 다룬다
-   14장은 서로 다른 실행 환경(Region/Account)에 있는 VPC 정보를 **Remote State(S3)**를 통해 참조하여, 다중 프로바이더 환경에서 VPC Peering을 맺고 라우팅 테이블을 자동으로 업데이트하는 네트워크 환경 구성을 설명한다.

# 학습 내용

# Chapter 13. VPC와 보안 그룹 모듈의 출력값을 활용하는 EC2 모듈 만들기

VPC와 보안 그룹은 이미 생성된 상태에서, 이를 조합하여 EC2 인스턴스를 생성하는 모듈을 개발함. 1:N 관계(VPC 하나에 여러 EC2)를 처리하기 위해 반복문 로직이 핵심임

## 1. 요구사항 및 설계

### 1.1 주요 요구사항

-   **1 Instance = 1 YAML:** EC2 인스턴스 하나당 하나의 YAML 파일로 관리
-   **입력값 제한:** 서브넷과 보안 그룹은 기존 모듈의 출력값을 사용
-   **볼륨:** 루트 볼륨 외 추가 EBS 볼륨 부착 가능, OS별 권장 장치 이름 강제
-   **네트워크:** 퍼블릭 서브넷일 경우 EIP 자동 할당, 프라이빗 IP 지정 가능
-   **AMI:** ID 직접 입력 (자동 검색 미사용)
-   **제외:** 키 페어와 IAM 역할은 테라폼으로 생성하지 않고 외부/콘솔 생성분 사용

### 1.2 AMI ID를 직접 입력하는 이유

-   **최신 이미지 검색의 문제점:** `most_recent = true`로 설정 시, 테라폼 실행 시점마다 최신 이미지가 달라져 의도치 않은 리소스 재생성(Drift) 발생 가능
-   **필터링의 어려움:** OS 버전, 아키텍처, SQL 서버 포함 여부 등 명명 규칙이 복잡하고 일관성이 부족함
-   **결론:** 운영 안정성을 위해 AMI ID를 명시적으로 고정

### 1.3 입력값 구조 (YAML)

`info_files/vpc명/ec2/` 경로에 위치

```yaml
YAML
# env/info_files/production/ec2/amazon-linux.yaml
env: production
team: devops
service: application
subnet: pri-app
az: a
security_groups: [linux]
ami_id: ami-045f2d6eeb07ce8c0
instance_type: t3.micro
root_volume:
  size: 10
additional_volumes:
  - device: /dev/sdf
    type: gp3
    size: 10
```

## 2. 모듈 구현 (Main Logic)

### 2.1 EC2 리소스 선언

VPC별로 모듈을 호출하고, 모듈 내부에서 `ec2_set`을 순회하며 인스턴스 생성

**핵심 코드: `aws_instance`**

```bash
resource "aws_instance" "this" {
  for_each = var.ec2_set

  ami           = each.value.ami_id
  instance_type = each.value.instance_type
  # VPC 모듈의 출력값(subnet_id_map) 활용
  subnet_id     = var.subnet_id_map[each.value.subnet][each.value.az]
  # 보안 그룹 모듈의 출력값(sg_id_map) 활용
  vpc_security_group_ids = [for sg_name in each.value.security_groups : var.sg_id_map[sg_name]]

  root_block_device {
    volume_type = each.value.root_volume.type
    volume_size = each.value.root_volume.size
    tags = merge(
      local.ec2_tags[each.key],
      { Name = "${each.value.full_name}-root" } # 루트 볼륨 태그 별도 지정
    )
  }

  tags = local.ec2_tags[each.key]
}
```

### 2.2 태그 관리 최적화 (`locals`)

EC2 인스턴스와 루트 볼륨은 서로 다른 리소스이므로 태그를 분리해야 함. 가독성을 위해 `locals`에서 태그를 미리 병합하여 정의함

```bash
locals {
  ec2_set = {
    for k, v in var.ec2_set : k => merge(v, {
      full_name = "${var.vpc_name}-${split("-", v.subnet)[0]}-${k}"
    })
  }

  ec2_tags = {
    for k, v in local.ec2_set : k => merge(
      local.module_tag,
      {
        Name    = v.full_name
        Env     = v.env
        # ... 기타 태그
      }
    )
  }
}
```

### 2.3 퍼블릭 IP (EIP) 할당

서브넷 이름이 "pub"으로 시작하는 경우에만 EIP 생성 및 연결

```bash
resource "aws_eip" "this" {
  for_each = {
    for k, v in local.ec2_set : k => v
    if split("-", v.subnet)[0] == "pub" # 서브넷 이름 파싱하여 조건 처리
  }

  domain   = "vpc"
  instance = aws_instance.this[each.key].id
}
```

### 2.4 추가 EBS 볼륨 처리 (복잡도 높음)

EC2 1대당 N개의 볼륨이 붙으므로 'EC2 반복' 내부의 '볼륨 반복' 구조를 평탄화(Flatten)해야 함

1. `ec2_set`과 `additional_volumes`를 순회하며 리스트 생성
2. 유틸리티 모듈(`merge_map_in_list`)을 사용해 맵으로 변환
3. `aws_ebs_volume`과 `aws_volume_attachment` 리소스 생성

```bash
# 데이터 평탄화 (Flatten)
locals {
  ec2_volume_set = [
    for ec2_name, ec2_attr in local.ec2_set : {
      for volume in ec2_attr.additional_volumes : "${ec2_name}_${volume.device}" =>
      merge({ ec2_name = ec2_name }, volume, ec2_attr)
    }
  ]
}

# EBS 생성
resource "aws_ebs_volume" "this" {
  for_each = local.merged_ec2_volume_set # 평탄화된 맵 사용

  availability_zone = aws_instance.this[each.value.ec2_name].availability_zone
  size              = each.value.size
  # ...
}

# EBS 연결
resource "aws_volume_attachment" "this" {
  for_each    = local.merged_ec2_volume_set
  device_name = each.value.device
  volume_id   = aws_ebs_volume.this[each.key].id
  instance_id = aws_instance.this[each.value.ec2_name].id
}
```

## 3. 변수 유효성 검사 (Validation)

`precondition` 블록을 활용하여 리소스 생성 전 오류를 방지함. `validation` 블록보다 구체적인 에러 메시지(어떤 리소스가 실패했는지) 제공 가능

-   **환경변수 검증:** `develop`, `production` 등 허용된 값인지 확인
-   **볼륨 타입 검증:** `gp3`, `io1` 등 유효한 타입인지 확인
-   **IOPS 검증:** IOPS 설정이 가능한 볼륨 타입인지 확인
-   **장치 이름(Device Name) 검증:** OS별(Linux/Windows) AWS 권장 장치 명명 규칙 준수 여부 확인

**장치 이름 검증 코드 예시:**

```bash
locals {
  device_name_patterns = {
    linux   = "/dev/sd[fp]" # 리눅스 권장 패턴
    windows = "xvd[fp]"     # 윈도우 권장 패턴
  }
}

resource "aws_ebs_volume" "this" {
  lifecycle {
    precondition {
      condition     = can(regex(local.device_name_patterns[each.value.os_type], each.value.device))
      error_message = "유효하지 않은 디바이스 이름입니다."
    }
  }
}
```

---

# Chapter 14. 다른 실행 환경의 출력값을 참조하는 네트워크 실행 환경 구성하기 (VPC Peering)

단일 환경이 아닌, 서로 다른 리전/계정(다중 프로바이더) 간의 네트워크 연결(VPC Peering)을 구현함. 이를 위해 **Remote State(원격 상태)** 관리와 실행 환경 분리가 필수적임

## 1. 실행 환경 구조 재설계

기존의 단일 환경에서 역할별로 분리

-   `env_seoul`: 서울 리전 기본 리소스 (VPC 등)
-   `env_virginia`: 버지니아 리전 기본 리소스 (VPC 등)
-   `env_network`: 네트워크 전용 환경 (VPC Peering 관리) -> **여기서 작업**

## 2. Remote State (원격 상태) 설정

다른 실행 환경(`env_seoul`, `env_virginia`)에서 생성된 VPC ID를 가져오기 위해 S3 Backend를 사용하고 출력값을 참조함

### 2.1 Backend 설정 및 Output (각 지역 환경)

```bash
# backend.tf (env_seoul)
terraform {
  backend "s3" {
    bucket = "terraform-tfstate-bucket"
    key    = "seoul.tfstate"
    region = "ap-northeast-2"
  }
}

# output.tf (env_seoul) - VPC ID 내보내기
output "vpc_id" {
  value = { for k, v in module.vpc : k => v.vpc_id }
}
```

### 2.2 Remote State 불러오기 (env_network)

`terraform_remote_state` 데이터 블록을 사용하여 S3에 저장된 상태 파일을 읽어옴

```bash
# env_network/main.tf
data "terraform_remote_state" "vpc" {
  for_each = toset(["seoul", "virginia"]) # 각 환경의 상태 파일 조회

  backend = "s3"
  config = {
    bucket = "terraform-tfstate-bucket"
    key    = "${each.key}.tfstate"
    region = "ap-northeast-2"
  }
}

# VPC ID 추출
locals {
  vpc_ids = {
    for k, v in data.terraform_remote_state.vpc : k => v.outputs.vpc_id
  }
}
```

## 3. VPC Peering 모듈 구현

### 3.1 토폴로지 정의 (topology.yaml)

피어링 대상을 정의하는 설정 파일

```yaml
prod_peering:
    requester:
        tf_env: seoul
        vpc: seoul-prod
    accepter:
        tf_env: virginia
        vpc: virginia-prod
```

### 3.2 모듈 호출의 한계 (Provider 문제)

**중요:** 테라폼은 `provider` 구문에 변수나 반복문을 사용할 수 없음. 따라서 프로바이더 조합(서울-버지니아, 서울-서울 등)마다 모듈을 명시적으로 따로 호출해야 함

```bash
# 서울 -> 버지니아 피어링 모듈 호출
module "seoul_to_virginia_peering" {
  source = "../modules/14_vpc_peering"

  providers = {
    aws.requester = aws.seoul
    aws.accepter  = aws.virginia
  }
  # ... topology 기반으로 for_each 필터링하여 전달
}
```

### 3.3 모듈 내부 로직

Requester(요청자)와 Accepter(수락자) 리소스를 각각 생성하고, 두 VPC의 모든 라우트 테이블에 경로를 추가함

**1. 피어링 연결 (Requester 측)**

```bash
resource "aws_vpc_peering_connection" "this" {
  provider      = aws.requester
  vpc_id        = local.requester_vpc.id
  peer_vpc_id   = local.accepter_vpc.id
  peer_region   = local.accepter_region
  auto_accept   = false # 다중 리전/계정이므로 false
}
```

**2. 피어링 수락 (Accepter 측)**

```bash
resource "aws_vpc_peering_connection_accepter" "this" {
  provider                  = aws.accepter
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
  auto_accept               = true
}
```

**3. DNS Resolution 및 라우팅 추가**

-   **DNS Resolution:** `aws_vpc_peering_connection_options` 리소스로 양쪽 모두 활성화
-   **라우팅:** `data "aws_route_tables"`로 각 VPC의 모든 라우트 테이블 ID를 가져와서 `aws_route` 리소스를 `for_each`로 생성

# 추가

-   **AMI 관리 전략:** 책에서는 ID 고정을 선택했지만, 실제 운영 환경에서는 **Golden Image Pipeline** (Packer + Ansible 등)을 구축하여 이미지를 생성하고, Parameter Store 등을 통해 최신 AMI ID를 안전하게 참조하는 방식이 더 일반적일 수 있음
-   **EBS `precondition`의 효용:** `aws_ebs_volume` 단계에서 장치 이름을 검사하는 이유는, 잘못된 이름으로 생성 후 `attachment` 단계에서 실패하면 볼륨 리소스만 덩그러니 남거나 상태 파일이 꼬이는 것을 방지하기 위함임 (Fail Fast 전략)
-   **UserData 활용:** 본문에는 없지만 `user_data`를 통해 부트스트래핑(초기 설정) 스크립트를 주입하는 것이 실무에서 필수적임
