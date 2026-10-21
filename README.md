# EzbaseViewer

공식 공개 저장소: <https://github.com/hinosisi/EzbaseViewer>

EzbaseViewer는 Ezbase와 연계하는 Windows 원격제어 제품이다. 관리자 앱은 업체별 클라이언트 호스트를 조회·관리·접속하고, 대상 PC에는 TeamViewer Host와 같은 Host 전용 에이전트만 설치한다. Host 에이전트에는 대상 검색이나 원격 접속 시작 기능을 두지 않는다.

EzbaseViewer 자체 개발 소스는 Apache-2.0으로 공개한다. 저장소 최상위의 `LICENSE`와 `NOTICE`가 적용되며, 저작권 표시는 `EzbaseViewer contributors`이다. 계약상 비공개 SDK, 업체 정보, 운영 키와 서명 키는 공개 범위에 포함하지 않는다. 세부 기준은 [공개 소스 운영 정책](OPEN_SOURCE.md)을 따른다.

현재 구현은 1단계 엔진 선정·개념검증을 지원하는 제어 영역(control plane) 골격이다. 화면 캡처·입력 주입·중계 데이터 경로는 엔진 PoC가 끝난 뒤 선택한 엔진 어댑터로 추가한다.

## 현재 구현

- 60초 일회용 실행 코드 발급과 원자적 1회 소비
- 실행 코드에 사용자·조직·업체·장치·허용 기능 결합
- 5분 단기 앱 토큰
- 업체 등록과 업체별 클라이언트 Host 목록 조회
- 클라이언트의 `HostOnly` 설치 모드 강제
- 승인형/무인 세션 요청 및 무인 접속 정책
- 요청 기능 상향 방지
- 메모리 기반 감사 이벤트와 상관관계 ID
- 핵심 보안 규칙 6개에 대한 패키지 의존성 없는 자동 시험

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
- 엔진 PoC 단계: Node.js 22.19+/24.11+/26+, npm, 승인된 REA와 분석 제공자

## 빌드와 시험

```powershell
dotnet build .\EzbaseViewer.slnx --configuration Release
dotnet run --project .\tests\EzbaseViewer.Core.Tests\EzbaseViewer.Core.Tests.csproj --configuration Release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-api.ps1
```

## 제어 서버 실행

개발용 내부 키를 현재 PowerShell 프로세스에만 설정하고 서버를 실행한다. 운영 키로 재사용하지 않는다.

```powershell
$env:EZBASEVIEWER_INTERNAL_KEY = "replace-with-a-development-only-secret"
dotnet run --project .\src\EzbaseViewer.Server\EzbaseViewer.Server.csproj --urls http://127.0.0.1:5080
```

`POST /v1/companies`, `POST /v1/clients/enrollments`, `POST /v1/launch-codes`에는 `X-Ezbase-Internal-Key` 헤더가 필요하다. 관리자 앱은 `GET /v1/companies`와 `GET /v1/companies/{companyId}/clients`로 업체별 Host를 관리한다. 실행 코드 교환 후 받은 앱 토큰은 `POST /v1/sessions`의 Bearer 토큰으로 사용한다.

## 작업 순서

1. `docs/phase-1/engine-evaluation.md`의 후보 자료와 공개 라이선스 호환성·상용 조건을 확정한다.
2. `docs/phase-1/poc-runbook.md`로 후보별 Windows·연결 PoC를 수행한다.
3. `docs/phase-1/rea-readiness.md`에 따라 REA를 별도 시험 환경에 준비한다.
4. 필수 게이트를 통과한 엔진을 ADR로 승인한다.
5. 승인된 엔진용 Viewer/Host/Relay 어댑터와 Windows 앱을 추가한다.

상위 계획은 [EzbaseViewer 개발 계획](../EzbaseViewer%20개발%20계획.md)을 따른다.
