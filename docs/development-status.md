# 개발 진행 현황

> 기준일: 2026-10-22

## 완료

- 한국어 상세 개발 계획 수립
- .NET 8 기반 엔진 독립 제어 서버 골격
- 공용 API 계약과 원격 기능 권한 모델
- 60초 일회용 실행 코드 발급, SHA-256 해시 저장, 원자적 1회 소비
- 사용자·조직·업체·장치·허용 기능의 실행 문맥 결합
- 5분 단기 앱 토큰과 Bearer 세션 요청
- 업체 등록, 업체별 클라이언트 조회, 업체 경계 확인, 승인형·무인 접속 상태
- 클라이언트를 `HostOnly` 역할로 강제하는 등록 계약
- 공개 소스 운영 방침, 기여 절차와 비공개 취약점 제보 기준
- `hinosisi/EzbaseViewer` 공개 저장소와 Apache-2.0 초기 커밋
- 무인 접속 정책과 기능 권한 상승 차단
- 상관관계 ID와 메모리 기반 감사 이벤트
- RustDesk 엔진 선정 ADR, 통합 설계와 PoC 실행서
- RustDesk Client `1.4.9`·Server OSS `1.1.16` 기준선을 고정한 엔진 프로필 API
- 공개 제품·공개 AGPL 포크·비공개 Ezbase 어댑터·비밀관리의 4단계 정보 경계
- Ezbase 내부 API의 사설망/루프백 제한과 내부 서비스 키 이중 검사
- 공개 반입 경계 검사 스크립트
- Pull Request와 `main` 푸시에서 경계·빌드·정책·API 시험을 수행하는 GitHub Actions
- RustDesk Client `1.4.9`·Server OSS `1.1.16` 공식 소스와 잠금 파일 해시 고정
- RustDesk Windows PoC 도구 체인 점검 스크립트와 준비 현황 기록
- RustDesk 공식 CI 기준 Rust `1.75.0`, Flutter `3.24.5`, LLVM `15.0.6`, bridge codegen `1.80.1`, vcpkg 커밋 고정
- 수정 없는 RustDesk Client `rustdesk.exe`와 Server `hbbs.exe`·`hbbr.exe` Windows Release 빌드 재현
- Client·Server 산출물 크기, SHA-256과 미서명 상태 기록
- 사전 점검부터 Client bridge·Windows Release·Server Release·산출물 검사까지 단일 재현 스크립트 연속 통과
- 임시 드라이브 변경 시 남는 Flutter CMake 절대 경로 캐시의 자동 정리와 경로 안전 검사
- `hbbs`·`hbbr` 로컬 기동, 기본 파생 포트, UDP rendezvous와 Ed25519 키 생성 스모크 검사
- REA 6.7.0 CLI 기동과 읽기 전용 doctor/dry-run 확인

## 검증 결과

| 검증 | 결과 |
|---|---|
| Release 전체 빌드 | 성공, 경고 0, 오류 0 |
| 실행 코드 1회 소비 | 통과 |
| 만료 코드 거부 | 통과 |
| 다른 업체 클라이언트 접근 거부 | 통과 |
| Host 전용 역할 강제 | 통과 |
| 무인 접속 정책 적용 | 통과 |
| 기능 권한 상승 거부 | 통과 |
| RustDesk 엔진 프로필 고정 | 통과 |
| 공인 주소의 Ezbase 내부 API 접근 차단 | 통과 |
| HTTP health·Host 등록·업체별 조회 | 통과 |
| HTTP RustDesk 엔진 프로필 조회 | 통과 |
| 코드 발급·교환·재사용 거부 | 통과 |
| 승인형 세션 요청 | 통과 |
| 감사 이벤트 수집 | 통과 |
| RustDesk Client 1.4.9 Windows Release 빌드 | 통과 (`rustdesk.exe`, `1.4.9+67`) |
| RustDesk Server OSS 1.1.16 Windows Release 빌드 | 통과 (`hbbs.exe`, `hbbr.exe`) |
| RustDesk 고정 도구 체인·서브모듈 검사 | 통과 |
| RustDesk 전체 재현 빌드 스크립트 | 통과 (`-ShortDrive S`, 종료 후 드라이브 해제·원본 `pubspec.yaml` 복원) |
| RustDesk Server 로컬 기동 스모크 | 통과 (`hbbs` TCP 22115·22116·22118/UDP 22116, `hbbr` TCP 22117·22119, 키 생성·종료) |

## 현재 제약

- 저장소는 메모리 기반 PoC다. 운영 데이터베이스와 실제 IdP를 연결하지 않았다.
- 화면·입력·파일·직접/중계 데이터 경로는 RustDesk 통합 PoC 전이므로 구현하지 않았다.
- RustDesk는 확정했고 Windows 바이너리 빌드도 재현했지만 다중 시험 장치에 `hbbs`·`hbbr`를 기동하지 않아 직접/중계, UAC·로그온·재부팅 PoC는 아직 수행하지 않았다.
- Apache-2.0 `LICENSE`와 `NOTICE`를 적용했으며 초기 저작권 표시는 `EzbaseViewer contributors`이다.
- Ezbase 실제 사용자·조직·업체·장치 식별자와 앱 실행 방식이 제공되지 않았다.
- 실제 Ezbase 내부 어댑터는 비공개 저장소가 준비된 뒤 구현한다. 공개 저장소에는 중립 계약만 유지한다.
- REA는 소스 분석의 대체 수단으로 사용하지 않는다. 이후 수정 바이너리·실행 시점 동작의 설명이 부족한 경우에만 보조 증거로 사용한다.

## 다음 게이트 입력

1. Ezbase 기술 인터페이스 문서와 개발 계정
2. 시범 업체의 지원 Windows 버전과 설치 권한 정책
3. RustDesk 공개 AGPL 포크 저장소와 격리 시험망의 자체 `hbbs`·`hbbr` 주소
4. AGPL-3.0 대응 소스 제공과 EzbaseViewer Apache 구성요소 경계의 서면 검토
5. GitHub 보호 브랜치·자동 검사와 비공개 보안 제보 채널 설정
6. UAC·로그온·재부팅 시험용 관리자 권한 Windows 장치 2대 이상

입력이 확보되면 `docs/phase-1/poc-runbook.md` 순서로 RustDesk 필수 게이트를 수행하고 결과를 선정 ADR에 연결한다.
