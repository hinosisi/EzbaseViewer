# RustDesk 엔진 선정 및 검증 작업표

> 결정 상태: RustDesk 확정
> 결정일: 2026-10-21
> PoC 기준선: RustDesk Client `1.4.9` (`6c57829`), RustDesk Server OSS `1.1.16` (`73523b3`)

## 선정 결과

EzbaseViewer의 원격 화면·입력·파일 전송 엔진과 직접/중계 연결 기반으로 RustDesk를 사용한다. 자체 인프라에는 RustDesk Server OSS의 `hbbs`와 `hbbr`를 배치한다. RealVNC, TightVNC, UltraVNC와 VncSharp는 구현 후보에서 제외하고 장애 시 재검토 자료로만 남긴다.

버전 기준선은 2026-10-21 확인 시점의 최신 안정 클라이언트 `1.4.9`와 최신 Server OSS `1.1.16`이다. nightly 및 pre-release는 보안 수정 검토용으로만 사용하며 시범 배포 기준선으로 삼지 않는다.

## 구성 경계

| 구성 | 기준 | 라이선스·저장소 원칙 |
|---|---|---|
| EzbaseViewer 제어 서버·공용 계약 | 현재 .NET 저장소 | Apache-2.0 유지 |
| EzbaseViewer 관리자 앱의 RustDesk 데이터 경로 | RustDesk 클라이언트 포크 또는 명확한 프로세스 어댑터 | RustDesk 코드를 포함·수정하는 저장소와 산출물은 AGPL-3.0 의무를 적용 |
| EzbaseViewer Host | RustDesk Windows 설치형 클라이언트 포크, HostOnly 프로필 | 포크 원본·변경 소스·빌드 스크립트를 AGPL-3.0으로 공개 |
| 접속 조정·중계 | RustDesk Server OSS `hbbs`·`hbbr` | 서버 원본·변경 소스와 대응 소스 제공 의무 이행 |
| Ezbase 인증·업체 관리 | EzbaseViewer 제어 서버 | RustDesk 장치 ID와 EzbaseViewer 장치 ID 매핑, 세션 허가 전 정책 검사 |

AGPL 코드를 Apache-2.0 파일로 복사하거나 라이선스 고지를 제거하지 않는다. 링크·IPC·배포 묶음의 법적 효과는 구현 방식이 정해진 뒤 법무 검토 기록으로 확정한다.

## 필수 PoC 게이트

| 게이트 | 현재 상태 | 완료 증거 | 담당 |
|---|---|---|---|
| UAC 보안 데스크톱 | 검증대기 | 설치형 Host에서 보기·입력 녹화 | Windows A |
| 로그온·잠금 화면 | 검증대기 | 로그오프·잠금 상태 접속 기록 | Windows A |
| 재부팅 후 재접속 | 검증대기 | 서비스 자동 시작과 재접속 로그 | Windows B |
| 직접→중계 전환 | 공식 구조 확인, 실측대기 | 직접 경로 차단 후 `hbbr` 연결 로그 | 서버 개발 |
| HostOnly 빌드 | 검증대기 | 대상 검색·접속 시작 UI/CLI 부재 확인 | Windows B |
| Ezbase 세션 허가 결합 | 설계완료, 구현대기 | 만료·철회·업체 경계 통합시험 | 서버 개발·보안 |
| 파일·무인 정책 차단 | 검증대기 | 서버 정책에 따른 기능 거부 시험 | Windows B |
| AGPL 대응 소스 제공 | 절차정의 | 포크 저장소·빌드 재현·고지 검토 | 기술 책임자·법무 |
| 유지보수·보안 추적 | 기준선 확정 | upstream 릴리스·보안 변경 검토 기록 | 기술 책임자 |

기술 엔진 선정은 완료됐지만 위 게이트를 통과하기 전에는 시범 업체에 배포하지 않는다. 필수 게이트 실패 시 RustDesk를 즉시 교체하지 않고 포크 수정 가능성, 일정과 보안 영향을 먼저 재평가한다.

## 공식 근거

- RustDesk Client 저장소와 라이선스: <https://github.com/rustdesk/rustdesk>
- RustDesk Client 릴리스: <https://github.com/rustdesk/rustdesk/releases>
- RustDesk Server OSS 저장소: <https://github.com/rustdesk/rustdesk-server>
- RustDesk Server OSS 릴리스: <https://github.com/rustdesk/rustdesk-server/releases>
- `hbbs`·`hbbr` 구성 문서: <https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/>
- 자체 서버 클라이언트 설정: <https://rustdesk.com/docs/en/self-host/client-configuration/>

## VncSharp 처리

VncSharp는 RFB 프로토콜과 과거 .NET Viewer 구현을 이해하기 위한 참고 자료로만 유지한다. EzbaseViewer 제품 코드나 엔진 어댑터의 기반으로 사용하지 않는다.
