# Chapter 6. 실행 환경 관리 (Execution Environment Management)

대상 인프라의 리소스 수가 적다면 하나의 실행 환경으로도 충분하다.
하지만 **리소스가 500개 이상일 경우**, 실행 환경을 분리하는 것이 안정성과 효율성을 크게 높인다.

---

## 1. 실행 환경을 분리하지 않을 때 발생하는 문제

### ■ 동시에 한 명만 Terraform 실행 가능

Terraform은 state 파일 기반으로 작동하므로,
동시에 여러 사용자가 작업할 경우 충돌이 발생한다.

* 리소스 간 상관 관계가 없어도 lock 때문에 대기해야 한다.
* 전체 실행 환경을 독점하는 상황이 발생할 수 있다.

예시:

* EC2와 Route53은 서로 무관하지만 한 환경에 묶여 있으면 동시 작업 불가.

---

### ■ 플래닝 및 실행시간 증가

Terraform plan 시 다음을 수행한다:

* 상태 파일 동기화
* 변경점 계산

리소스가 많을수록 시간이 크게 늘어난다.
부수 리소스까지 포함되면 관리 대상이 급격히 증가한다.

---

### ■ 드리프트(상태 불일치) 발생 시 대응 난이도 상승

여러 리소스가 한 실행 환경에 엮여 있으면 복구가 어렵다.

---

## 2. 실행 환경 분리 사례

### (1) 배포 단계/계정별 분리

예시:

* development
* staging
* production

조직마다 stage 별 인프라 구성이 다르기 때문에
리소스가 동일하지 않다면 AWS 계정 분리도 고려한다.

---

### (2) 여러 계정에 걸쳐 공유되는 글로벌 리소스

#### IAM

* 리전에 종속되지 않는 글로벌 리소스
* 계정 간 동일 규칙 유지 필요
* 보안 측면에서 Terraform보단 별도 플랫폼 권장

#### S3

* 글로벌 리소스
* 버킷 이름이 전 세계 유일
* 여러 계정에서 공용 관리 가능

---

### (3) 여러 계정에 걸쳐 동시에 배포되는 리소스

예: Multi-VPC 환경에서 Transit Gateway 또는 VPC Peering 구성

문제:

> Peering 리소스는 어디에 정의해야 하는가?

해결:

* 교차 계정 전용 실행 환경을 별도로 구성

특징:

* 네트워크 리소스는 빈도는 낮지만 오류에 민감
* 중앙 배포 환경에서 관리가 적합

---

### (4) 도메인을 여러 AWS 계정에 나눠 관리하는 경우

예:

* 운영 계정 Hosted Zone: terraform.com
* 개발 계정 Hosted Zone: dev.terraform.com

dev 환경 생성 시 필요한 작업:

1. 개발 계정에서 Hosted Zone 생성
2. 운영 계정 Route53에 NS 레코드 등록

즉, **두 개 provider 사용 필요**:

* 개발 계정 provider
* 운영 계정 provider

---

---

# Chapter 7. 인라인 블록 (Inline Blocks)

## 1. Nested Block (중첩 블록)

리소스 내부에서 세부 설정을 정의할 때 사용한다.
대표적으로 SG ingress/egress에 사용된다.

```hcl
resource "aws_security_group" "example" {
  name        = "example-security-group"
  description = "Security group for example usage"
  vpc_id      = aws_vpc.example.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

---

## 2. Dynamic Block

중첩 블록 반복을 줄여 선언을 간결하게 한다.

### locals 정의

```hcl
locals {
  sg_rules = {
    inbound_https = {
      type        = "ingress"
      port        = 443
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/16"]
    }

    inbound_http = {
      type        = "ingress"
      port        = 80
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/16"]
    }

    outbound_all = {
      type        = "egress"
      port        = 0
      protocol    = -1
      cidr_blocks = ["10.0.0.0/16"]
    }
  }
}
```

### dynamic 적용

```hcl
resource "aws_security_group" "example" {
  name        = "example-security-group"
  description = "Security group for example usage"
  vpc_id      = aws_vpc.example.id

  dynamic "ingress" {
    for_each = {
      for k, v in local.sg_rules : k => v
      if v.type == "ingress"
    }
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  dynamic "egress" {
    for_each = {
      for k, v in local.sg_rules : k => v
      if v.type == "egress"
    }
    content {
      from_port   = egress.value.port
      to_port     = egress.value.port
      protocol    = egress.value.protocol
      cidr_blocks = egress.value.cidr_blocks
    }
  }
}
```

---

## 3. 중첩 블록 vs 별도 리소스 블록

별도 리소스 블록을 권장한다.

이유:

* 중첩 블록은 순서 제어 불가
* Terraform이 순서 차이를 변경으로 판단해 재생성할 수 있음

---

## 4. Lifecycle Block

모든 리소스에서 사용 가능.

### ignore_changes

```hcl
resource "aws_autoscaling_group" "this" {
  max_size         = 5
  min_size         = 2
  desired_capacity = 4

  lifecycle {
    ignore_changes = [
      desired_capacity
    ]
  }
}
```

사용 목적:

* 변경을 무시하고 현재 리소스를 유지

### create_before_destroy

서비스 중단 방지

### prevent_destroy

삭제 시 오류 발생

### replace_triggered_by

특정 리소스 변경 시 재생성하도록 강제

---

# 유효성 검사

## validation block

변수 입력을 제한하거나 검증할 수 있다.

## precondition/postcondition 예제

```hcl
data "aws_ami" "this" {
  owners = ["amazon"]

  filter {
    name   = "image-id"
    values = ["ami-06f37ad9b29fcbdc3"]
  }
}

resource "aws_instance" "x86_64" {
  ami           = data.aws_ami.this.id
  instance_type = "t3.medium"

  lifecycle {
    precondition {
      condition     = data.aws_ami.this.architecture == "x86_64"
      error_message = "x86_64 아키텍처 AMI ID를 입력해주세요."
    }

    postcondition {
      condition     = self.public_dns != ""
      error_message = "Public DNS가 생성되지 않았습니다."
    }
  }
}
```

---

---

# Terraform + GitOps

Terraform은 인프라를 만든다.
GitOps는 그 인프라 변경을 **안전하게 운영하도록 만든다.**

둘은 대체 관계가 아니라 보완 관계이다.

---

## Terraform만 단독 사용할 때의 문제

### ◼ 로컬에서 apply 가능

* 개발자가 직접 terraform apply 실행 가능
* 운영환경이 사람의 PC에 의존

### ◼ IAM 권한을 개인에게 줘야 한다

보안 리스크 증가

### ◼ 변경 이력 추적이 충분하지 않다

* plan/apply 누가 언제 실행했는지 남지 않음

### ◼ 협업 비효율

* 상태 파일 충돌
* 동시에 작업 불가

---

# 왜 GitOps가 필요해지는가?

Git 기반 자동화를 통해 다음을 해결한다:

* **사람이 직접 apply하지 않음**
* 변경사항은 Git PR에서 검증
* 모든 변경 이력은 Git으로 추적
* drift 발생 시 자동 감지
* 시행 주체는 개발자가 아니라 시스템

---

# Terraform GitOps 구조

```
GitHub
  ↓
자동화 파이프라인
  ↓
Terraform plan/apply
  ↓
S3 (state 파일 저장)
DynamoDB (lock 관리)
```

### 결과:

* 인프라 변경이 Git과 pipline에 의해 자동 적용
* 사람이 apply 명령어를 실행하지 않는다
* 접근 권한을 최소화할 수 있다

---

# GitOps 도구

## 1. Atlantis

Terraform을 GitOps 방식으로 실행하는 대표 OSS

### 특징

* PR 기반 plan/apply
* 적용 결과를 PR에 포맷팅
* Lock 기능 제공
* IAM 권한을 개발자가 아닌 Atlantis에 부여

---

## 2. Terraform Cloud

* VCS 연동
* RBAC
* Remote backend 관리
* state 자동 저장

---

---

# Terraform과 GitOps의 역할 분리

| 역할        | 담당                       |
| --------- | ------------------------ |
| 인프라 상태 정의 | Terraform                |
| 상태 파일 관리  | Backend                  |
| 변경 요청 검증  | Git PR                   |
| 실행 자동화    | GitOps (Atlantis, TFC 등) |
| 배포/롤백     | Git 기반                   |

---

# 결국...

Terraform은 인프라를 정의하고,
GitOps는 그 인프라의 변경을 **안전하게 실행**하도록 만들어준다.

둘을 조합해야 완성된 인프라 운영 체계가 된다!