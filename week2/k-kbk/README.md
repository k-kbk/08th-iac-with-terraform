# 주제

- 테라폼 작동 방식
- 테라폼 기본 문법

# 요약

- 테라폼은 상태 파일을 기반으로 실제 리소스와 선언적 구성을 동기화한다.
- HCL 문법을 기반으로 변수, 반복문, 조건문, 모듈 등을 활용해 재사용성과 자동화를 극대화할 수 있다.

# 학습 내용

## 테라폼 작동 방식

### 테라폼 프로젝트 구조

- 구성 파일: 인프라의 기대 상태를 HCL로 기술한 파일, `.tf`
- 루트 모듈: 테라폼 명령어를 실행하는 작업 디렉터리의 최상위 모듈
- 상태 파일: 테라폼이 코드에 정의한 리소스와 실제 인프라 리소스를 동기화하기 위해 사용하는 파일, `.tfstate`

### 테라폼 상태의 역할

- 리소스의 실제 상태와 코드에 정의된 기대 상태의 차이를 비교하여, 어떤 작업이 필요한지 판단
- 기대 상태와 실제 인프라 리소스의 매핑: 비슷한 종류의 리소스가 프로비저닝된 상황에서도 모호함 없이 수정 및 삭제 가능
  > 리소스 드리프트(Resource Drift): 수동 작업 등의 이유로 코드와 실제 인프라가 일치하지 않는 상태
- 관리 대상 명시적 지정: 테라폼 상태로 저장한 리소스가 아닌 경우 인프라 조작의 대상으로 인식하지 않음
- 리소스 조작 순서와 의존성 지정: 리소스를 올바른 순서로 조작
- 상태 백엔드를 사용한 협업: 상태 파일을 AWS S3 버킷 등에 저장하여 공유, 상태 락(State Locking) 제공

### 테라폼 명령과 작동

- `terraform refresh`: 현재 실제 인프라 상태를 조회하여, 상태 파일을 최신 상태로 동기화
  > v0.15.4 이후 `terraform apply -refresh-only`로 대체
- `terraform plan`: 실제 상태와 기대 상태를 비교하여, 리소스 변경 사항을 계산
- `terraform apply`: 구성 파일에 정의한 기대 상태를 실제 인프라에 반영
- `terraform destroy`: 테라폼의 명시적 관리 대상이 되는 모든 인프라 제거
- `terraform state list`: 상태 목록 조회
- `terraform state show`: 상태 상세 조회
- `terraform state mv`: 상태 이동
- `terraform state rm`: 상태 삭제
- `terraform import`: 상태 가져오기

### 테라폼 프로바이더

- 프로바이더(Provider): 테라폼이 외부 인프라와 상호작용할 수 있도록 해주는 플러그인
- `terraform init`을 수행하면 현재 디렉터리에 있는 구성 파일을 읽고, 필요한 프로바이더를 자동으로 인식 및 다운로드
- 테라폼 레지스트리로 다양한 프로바이더 다운로드 가능

## 테라폼 기본 문법

### 데이터 타입

- string: 유니코드 문자열
- number: 정수/실수/음수
- bool: true/false
- list(또는 tuple): 0부터 시작
- set: 순서 없음
- map: { name = "bk", age = 26 }

### 반복문

- count: 정수를 매개변수로 받아, 해당 정수의 값만큼 리소스를 반복 생성
  ```hcl
  resource "aws_instance" "this" {
    count         = 3
    ami           = "ami-..."
    instance_type = "t3.medium"
  }
  ```
- for_each: map이나 set을 매개변수로 받아, 각 데이터를 순회하여 리소스를 생성, 권장

  ```hcl
  resource "aws_instance" "this" {
    for_each = {
        windows = {
            ami  = "ami-..."
            type = "t3.medium"
        }

        linux = {
            ami  = "ami-..."
            type = "r5.large"
        }
    }

    ami           = each.value.ami
    instance_type = each.value.type

    subnet_id = "subnet-..."
    vpc_security_group_ids = ["sg-..."]

    tags = {
        Name = each.key
    }
  }
  ```

### 조건문

- 삼항 연산자: 조건 ? 참일 때의 값 : 거짓일 때의 값

  ```hcl
  variable "is_production" {
    type    = bool
    default = false
  }

  resource "aws_instance" "this" {
    ami           = "ami-..."
    instance_type = var.is_production ? "m5.large" : "t3.medium"
  }

  # 결과: instance_type = "t3.medium"


  variable "env" {
    type    = string
    default = "develop"
  }

  resource "aws_instance" "nginx" {
    count         = var.env == "production" ? 1: 0
    ami           = "ami-..."
    instance_type = "t3.medium"
  }

  # 결과: count = 0
  ```

### for 표현식

- for 표현식으로 리스트 또는 집합 생성하기  
  [ for `<element>` in collection>: `<expression>` ]

  ```hcl
  [ for i in ["a", "b", "c"] : "resource ${i}" ]

  [
    "resource a",
    "resource b",
    "resource c"
  ]
  ```

- for 표현식으로 맵 생성하기  
  { for `<element>` in `<collection>`: `<key_expression>` => `<value_expression>` }

  ```hcl
  { for k, v in aws_vpc.this : k => { id = v.id, cidr = v.cidr_block } }

  # 결과:
  {
    "a" = {
      "cidr" = "10.0.0.0/16"
      "id" = "vpc-..."
    }
    "b" = {
      "cidr" = "10.0.0.0/16"
      "id" = "vpc-..."
    }
    "c" = {
      "cidr" = "10.0.0.0/16"
      "id" = "vpc-..."
    }
  }
  ```

- for 표현식에서의 if

  ```hcl
  locals {
    server_map = {
      ad_server = {
        active    = true
        is_window = true
      }
      squid_proxy = {
        active    = false
        is_window = false
      }
      web_server = {
        active    = true
        is_window = false
      }
    }
  }

  active_server = [
    for k, v in local.server_map : k
    if v.active
  ]

  # 결과: ["ad_server", "web_server"]
  ```

## 테라폼 블록

### 테라폼 블록

- 테라폼 실행 환경 자체의 동작 및 환경 설정을 정의

  ```hcl
  terraform {
    required_version = ">= 0.12.0"  # 0.12.0 이후의 버전

    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "~> 3.0"  # 3.0 이후의 버전
      }
    }

    backend "s3" {  # 상태 파일을 관리할 상태 백엔드
      bucket = "terraform-state-bucket"
      key    = "state/terraform.tfstate"
      region = "ap-northeast-2"
    }
  }
  ```

### 프로바이더 블록

- 클라우드 서비스나 외부 시스템과의 상호작용을 위한 설정을 정의

  ```hcl
  # 기본
  provider "aws" {
    region     = "ap-northeast-2"
    access_key = "my-access-key"
    secret_key = "my-secret-key"
  }

  # profile 사용
  provider "aws" {
    region  = "ap-northeast-2"
    profile = "terraform-a"
  }

  # assume role 사용
  provider "aws" {
    region  = "ap-northeast-2"
    profile = "terraform-a"

    assume_role {
      role_arn = "arn:aws:iam::${account_id}:role/AssumeRole"
    }
  }

  # 추가 프로바이더
  provider "aws" {
    region  = "ap-northeast-2"
    profile = "terraform-b"
    alias   = "terraform-b"
  }
  ```

### 리소스 블록

- 관리할 클라우드 서비스나 인프라 리소스를 정의

  ```hcl
  resource "aws_instance" "windows" {
    ami           = "ami-..."
    instance_type = "t3.medium"
  }

  resource "aws_instance" "linux" {
    ami           = "ami-..."
    instance_type = "t3.medium"
  }
  ```

### 데이터 블록

- 이미 존재하는 외부 리소스의 정보를 읽어와 참조할 때 사용

  ```hcl
  # Ubuntu 20.04 AMI 정보 조회
  data "aws_ami" "ubuntu" {
    most_recent = true
    owners      = ["099720109477"]  # Ubuntu의 공식 AMI

    # 특정 이미지 패턴 검색
    filter {
      name   = "name"
      values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
    }
  }

  # 현재 AWS Account ID 조회
  data "aws_caller_identity" "current" {}
  output "account_id" {
    value = data.aws_caller_identity.current.account_id
  }
  ```

### 모듈 블록

- 모듈 호출을 위해 사용

  ```hcl
  module "module_name" {
    source = "path/to/module/source"
    # 모듈에 전달할 입력 변수
  }
  ```

### 변수 블록

- 인프라 구성에서 재사용 가능한 입력값 정의

  ```hcl
  variable "variable_name" {
    type        = <type>
    default     = <default_value>
    description = <description>
  }
  ```

### 로컬 블록

- 반복 사용되는 값이나 복잡한 표현식을 간결하게 정의해 재사용할 때 사용(= 로컬 변수)

  ```hcl
  locals {
    service_name = "web-app"

    common_tags = {
      Service   = local.service_name
      ManagedBy = "Terraform"
    }
  }
  ```

### 출력 블록

- 실행 결과로부터 외부에 전달하거나 확인할 값(출력값)을 정의할 때 사용

  ```hcl
  output "output_name" {
    value       = <value>
    description = <description>
    sensitive   = <true_or_false>
  }
  ```

## 테라폼 함수

### 수치 함수

```hcl
# 절댓값
abs(-23) = 23

# 올림
ceil(5.1) = 6

# 내림
floor(4.9) = 4

# 최댓값
max([12, 54, 3]) = 54

# 최솟값
min([12, 54, 3]) = 3
```

### 문자열 함수

```hcl
# 포맷팅
format("Hello, %s!", "Terraform") = "Hello, Terraform!"
format("테라폼 책 작가는 %d명입니다.", 2) = "테라폼 책 작가는 2명입니다."

# 교체
replace("1 + 2 + 3", "+", "-") = "1 - 2 - 3"

# 분할
split(",", "테,라,폼") = ["테", "라", "폼"]

# 포함 여부
strcontains("테라폼 사랑해요" , "폼 사") = true
strcontains("테라폼 사랑해요" , "폼사") = false

# 접두사
startswith("테라폼 사랑해요" , "테라폼") = true

# 접미사
endswith("테라폼 사랑해요" , "테라폼") = false
```

### 컬렉션 함수

```hcl
# 길이
length("테라폼미쳤다") = 6

# 맵 탐색
lookup({ a = 1, b = 2 }, "a", 0) = 1
lookup({ a = 1, b = 2 }, "c", 0) = 0

# 리스트 병합
concat(["a", ""], ["b", "c"]) = ["a", "", "b", "c"]

# 리스트 평탄화
flatten([["a", "b"], [], ["c"]]) = ["a", "b", "c"]

# 맵 병합
merge({ a = "b", c = "d" }, { e = "f", c = "z" }) = { a = "b", c = "z", e = "f" }
```

### 그 외

- 인코딩 함수: base64encode, jsonencode, urlencode 등
- 파일 시스템 함수: abspath, dirname, file 등
- 날짜/시간 함수: timestamp, formatdate 등
- 해시 함수: sha1, sha256, uuid 등
- IP 네트워크 함수: cidrsubnet, cidrnetmask 등
- 오류 핸들링 및 예외 처리 함수: can, try 등

# 추가

## 테라폼 컨벤션

> 참고: [테라폼 스타일 가이드](https://developer.hashicorp.com/terraform/language/style)

### 코드 스타일

- 커밋 전 `terraform fmt`, `terraform validate` 를 실행할 것을 권장
- 주석은 `#` 사용
- 리소스 이름 또는 데이터 소스 이름은 명사형 사용
- 여러 단어로 구성된 이름은 `_`로 구분
- 변수나 출력에 설명(description) 반드시 포함
- 변수나 로컬의 과다 사용은 피할 것

### 코드 포맷팅

- 들여쓰기는 스페이스 2칸
- 동일 들여쓰기 레벨에서 여러 인수가 있을 경우 `=` 기호 정렬
- 블록 내에서 인수들은 상단에, 중첩 블록은 하단에 배치, 인수와 블록 사이에 한 줄 공백 넣어 구분
- 메타 인수(count, for_each, depends_on, lifecycle 등)가 있는 경우, 다른 인수와 구분해서 배치, 인수 및 다른 블록과 한 줄 공백으로 구분
- 최상위 블록들 간에는 한 줄 공백을 넣어 구분

### 파일 및 디렉터리 구조

- modules/: 재사용 가능한 모듈 단위
- envs/: 환경별 구성
- global/: 모든 환경에 공통으로 적용되는 전역 리소스
- backend.tf
- main.tf
- outputs.tf
- providers.tf
- terraform.tf
- variables.tf
- locals.tf
- override.tf
- 리소스 파일을 너무 세분화하기보다는 목적에 따라 그룹화해서 network.tf, storage.tf, compute.tf 등의 이름으로 관리

## 네이밍 컨벤션

- 리소스 블록, 변수명, 출력명 모두 소문자 + `_` 조합 권장
- 리소스 블록의 이름(label)에는 리소스 타입을 반복하지 않는 것이 좋음
- boolean 변수에는 긍정형 표현 사용

## 워크플로우 및 운영 관련 권장 사항

- 코드 커밋 전에 자동화된 형식 및 유효성 검사를 CI/CD 파이프라인에 포함
- 상태 파일에는 민감한 정보가 포함될 수 있으므로, 원격 저장 및 암호화 구성을 사용하는 것 권장

등등...
