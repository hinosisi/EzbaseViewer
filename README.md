# EzbaseViewer

공식 공개 저장소: <https://github.com/hinosisi/EzbaseViewer>

EzbaseViewer는 Ezbase와 연계하는 Windows 원격제어 제품이다. 관리자 앱은 업체별 클라이언트 호스트를 조회·관리·접속하고, 대상 PC에는 TeamViewer Host와 같은 Host 전용 에이전트만 설치한다. Host 에이전트에는 대상 검색이나 원격 접속 시작 기능을 두지 않는다.

EzbaseViewer 자체 개발 소스는 Apache-2.0으로 공개한다. 실제 Ezbase 내부 API·DB·SSO에 접근하는 어댑터와 운영정보는 비공개 저장소로 분리하며 이 저장소에는 중립 계약만 둔다. 저장소 최상위의 `LICENSE`와 `NOTICE`가 적용되며, 세부 기준은 [공개 소스 운영 정책](OPEN_SOURCE.md)과 [공개·비공개 경계](docs/public-private-boundary.md)를 따른다.

원격제어 엔진은 RustDesk로 확정했다. 현재 구현은 RustDesk 통합 PoC를 지원하는 제어 영역(control plane) 골격이며, 화면 캡처·입력 주입·중계 데이터 경로는 RustDesk Client `1.4.9`와 Server OSS `1.1.16` 기준으로 검증·통합한다.

RustDesk 변경 소스는 AGPL-3.0 공개 포크 [hinosisi/EzbaseViewer-rustdesk](https://github.com/hinosisi/EzbaseViewer-rustdesk)의 `ezbaseviewer-hostonly` 브랜치에서 관리한다. 최초 Host 프로필은 RustDesk의 incoming-only 정책을 컴파일 시 강제하고 원격 접속 시작 UI와 코어 연결 경로를 차단한다.

## 현재 구현

- 60초 일회용 실행 코드 발급과 원자적 1회 소비
- 실행 코드에 사용자·조직·업체·장치·허용 기능 결합
- 5분 단기 앱 토큰
- 업체 등록과 업체별 클라이언트 Host 목록 조회
- 클라이언트의 `HostOnly` 설치 모드 강제
- 승인형/무인 세션 요청 및 무인 접속 정책
- 요청 기능 상향 방지
- 메모리 기반 감사 이벤트와 상관관계 ID
- 핵심 보안 규칙, RustDesk 엔진 고정과 Ezbase 내부망 제한을 확인하는 8개 자동 시험

현재 저장소는 탐색용 기반이며 다음 기능은 아직 제품 구현이 아니다.

- 원격 화면·키보드·마우스·파일 전송 엔진
- Windows 서비스와 사용자 세션 프로세스
- 영구 데이터베이스, 실제 IdP, 분산 캐시
- 접속 조정·중계 서버
- 설치·코드 서명·업데이트·복구
- 실제 Ezbase 호출 규격과 사용자 지정 URI 등록

## 요구 환경

- Windows 10/11 x64
- .NET 8 SDK 이상
- 엔진 PoC 단계: Visual Studio 2022 C++ workload, Rust `1.75.0`, Flutter `3.24.5`, LLVM `15.0.6`, 고정 vcpkg
- REA는 수정 바이너리나 실행 시점 동작에 추가 증거가 필요할 때만 사용

## 빌드와 시험

```powershell
dotnet build .\EzbaseViewer.slnx --configuration Release
dotnet run --project .\tests\EzbaseViewer.Core.Tests\EzbaseViewer.Core.Tests.csproj --configuration Release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-api.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-public-boundary.ps1
```

RustDesk 고정 소스와 도구 체인이 `work/`에 준비된 PC에서는 다음 명령으로 원본 Client와 Server Windows 빌드를 재현한다. 생성 바이너리는 시험용이며 제품 배포 전에 브랜딩·정책·서명 절차를 거쳐야 한다.

```powershell
pwsh -NoProfile -File .\scripts\check-rustdesk-poc-prerequisites.ps1
pwsh -NoProfile -File .\scripts\build-rustdesk-poc.ps1
pwsh -NoProfile -File .\scripts\smoke-rustdesk-server.ps1
```

긴 작업 경로에서는 빌드 스크립트가 기본적으로 임시 `R:` 드라이브를 사용한다. 이미 사용 중이면 `-ShortDrive S`처럼 다른 문자를 지정한다. 스크립트는 종료 시 임시 드라이브와 Client의 임시 의존성 변경을 복원한다.
서버 스모크 시험은 로컬 PoC 포트에서 `hbbs`·`hbbr`를 잠시 실행해 수신 포트와 키 생성을 검사한 뒤 항상 종료한다. 생성 키와 로그는 Git에서 제외된 `work/poc-runtime/`에 둔다.

## 제어 서버 실행

개발용 내부 키를 현재 PowerShell 프로세스에만 설정하고 서버를 실행한다. 운영 키로 재사용하지 않는다.

```powershell
$env:EZBASEVIEWER_INTERNAL_KEY = "replace-with-a-development-only-secret"
dotnet run --project .\src\EzbaseViewer.Server\EzbaseViewer.Server.csproj --urls http://127.0.0.1:5080
```

`GET /v1/system/engine`, `POST /v1/companies`, `POST /v1/clients/enrollments`, `POST /v1/launch-codes` 등 내부 엔드포인트는 사설망/루프백 연결과 `X-Ezbase-Internal-Key`를 모두 요구한다. 인터넷 경로에는 이 엔드포인트를 라우팅하지 않는다. 실제 Ezbase 내부 연동 구현과 설정은 비공개 저장소에서 관리한다. 실행 코드 교환 후 받은 앱 토큰은 `POST /v1/sessions`의 Bearer 토큰으로 사용한다.

## 작업 순서

1. [RustDesk 선정 ADR](docs/adr/0001-select-rustdesk-engine.md)과 [통합 설계](docs/phase-1/rustdesk-integration.md)를 기준선으로 사용한다.
2. `docs/phase-1/poc-runbook.md`로 RustDesk Windows·직접/중계 PoC를 수행한다.
3. [PoC 준비 현황](docs/phase-1/rustdesk-poc-readiness.md)과 `scripts/check-rustdesk-poc-prerequisites.ps1`로 고정 도구 체인을 준비한다.
4. `docs/phase-1/rea-readiness.md`에 따라 설명이 부족한 바이너리 동작만 REA로 보완 분석한다.
5. 공개 포크의 `ezbaseviewer-hostonly` 브랜치를 기준으로 Host 시험 빌드를 만들고 관리자 Viewer 어댑터와 `hbbs`·`hbbr` 시험 환경을 구성한다.
6. 필수 게이트 증거를 승인한 뒤 핵심 원격제어 개발로 전환한다.

상위 계획은 [EzbaseViewer 개발 계획](docs/EzbaseViewer%20개발%20계획.md)을 따른다.
