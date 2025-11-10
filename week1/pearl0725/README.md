## 주제

- 1week
    - IaC 개념과 등장 배경
    - Terraform 구성 요소와 동작 원리

<br>

## IaC 개념과 등장 배경


테라폼은 하시코프(Hashicorp) 사에서 Go 언어를 기반으로 개발된 오픈소스 IaC 도구입니다. 해당 도구는 HCL 언어를 사용하여 리소스를 선언하여 관리한다.

테라폼이 등장하기 이전, 이미 클라우드 자원을 코드로 관리하기 위한 도구는 2011년에 AWS에서 CloudFormation 이라는 이름으로 출시되었다. 

CloudFormation과 같은 클라우드 환경에서 제공하는 YAML 또는 JSON 기반의 프로비저닝 도구는 특정 클라우드 환경에 종속성을 보이게 되는데, 여러 클라우드 플랫폼에서 사용할 수 있는 범용적인 관리 도구 필요성[1]이 언급되기 시작했다.  

이를 시작으로, 2021년도에 테라폼의 첫 메이저 버전 1.0이 릴리즈 되었다. 

[1] mitchellh / CloudFormation: The Big Picture: https://gist.github.com/mitchellh/b52314d30ba22bb76f3d6bb9ff098090

이를 통해 각 프로바이더에서 제공하는 API를 호출하여 표준화 된 구축 절차를 HCL 언어로 정의하여 리소스를 프로비저닝 할 수 있게 되었다. 

특히나 클라우드 환경은 기존 온프레미스 환경에서 제공하는 다양한 구성 요소를 S/W 방식으로 추상화 한 형태로 제공하는데, 이러한 구성 요소들을 모듈화하여 패키징 해두면 반복적인 구축 절차를 최소화하고 재사용성에 용이하다. 

<br>

## Terraform 구성 요소와 동작 원리

<img width="561" height="276" alt="Image" src="https://github.com/user-attachments/assets/5bc7d2b4-5945-4376-b0dc-d57384db9f00" />

<br>

**Main Commands**

```
$ terraform init # 현재 디렉터리 초기화
$ terraform vaildate # 유효성 검사
$ terraform fmt # 표준 스타일(형식) 자동 정렬
$ terraform plan # 수행 작업 테스트 실행
$ terraform apply # 실행(빌드)
$ terraform destory # 삭제
```

<br>

**Resource**

- `<PROVIDER>` 공급자 대상
- `<TYPE>` 제어 리소스 유형
- `<NAME>` 리소스 참조 식별자 정의

```
resource "<PROVIDER>_<TYPE>" "<NAME>" {
    [CONFIG...]
}
```

<br>

**Provider**

테라폼은 인프라 구성을 위해 하나 이상의 프로바이더를 지정해야 한다. 이를 통해 테라폼이 각 프로바이더에서 제공하는 API를 호출하여 상호작용을 할 수 있다.

<br>

**State**

테라폼은 상태 파일(State file)을 기반으로 구성 리소스에 대한 정보를 관리한다. 해당 파일은 테라폼이 인프라를 변경/삭제/생성 등을 하는데 필요한 모든 데이터가 포함된다.

상태 파일은 초기 `terraform.tfstate` 명칭으로 로컬 환경에 적재된다. 다만, 효율적인 관리를 위해서 원격 백엔드를 통해 관리하는 것을 권장한다.
