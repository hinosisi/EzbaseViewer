# ADR-0001: RustDesk 원격제어 엔진 선정

- 상태: 승인
- 결정일: 2026-10-21
- 결정자: 제품 책임자

## 배경

EzbaseViewer는 Windows 관리자 앱과 Host 전용 에이전트, 직접 연결 실패 시 자체 중계, UAC·로그온 화면, 재부팅 후 재접속을 요구한다. 제품 소스는 공개하며 업체·사용자·장치 권한은 EzbaseViewer 제어 서버가 결정한다.

## 결정

RustDesk를 원격제어 엔진으로 사용한다. PoC 기준선은 RustDesk Client `1.4.9`와 RustDesk Server OSS `1.1.16`이다. 서버는 `hbbs`를 ID·rendezvous·signaling 용도로, `hbbr`를 직접 연결 실패 시 중계 용도로 자체 운영한다.

대상 PC에는 RustDesk 기반 EzbaseViewer HostOnly 빌드만 설치한다. 관리자 측 데이터 경로는 RustDesk Viewer 기능을 사용하되 업체 목록, 사용자 인증, 장치 선택과 세션 허가는 EzbaseViewer가 담당한다.

## 라이선스 결정

현재 EzbaseViewer 제어 서버 저장소는 Apache-2.0을 유지한다. RustDesk 클라이언트·서버 코드를 포함하거나 수정하는 포크는 별도 저장소와 빌드 경계로 관리하고 AGPL-3.0에 따라 원본 고지, 변경 소스와 대응 소스를 공개한다. 구체적인 링크·결합 방식은 법무 검토를 통과해야 하며, 이 ADR은 법률 의견을 대신하지 않는다.

## 결과

- 엔진 후보 비교 작업을 종료하고 RustDesk 통합 PoC로 전환한다.
- `hbbs`·`hbbr` 자체 운영, 공개키 배포와 포트 정책을 인프라 설계에 포함한다.
- HostOnly UI 제거, Ezbase 세션 허가 결합, UAC·로그온·재부팅은 여전히 필수 검증 게이트다.
- upstream 보안 수정과 릴리스를 주기적으로 추적하고, 채택 버전·커밋·해시를 릴리스마다 기록한다.

## 재검토 조건

- 필수 Windows 게이트를 포크 수정으로도 충족하지 못함
- 심각한 미해결 보안 취약점 또는 유지보수 중단
- AGPL 의무를 제품 배포 구조에서 이행할 수 없음
- 성능·중계 용량이 승인된 목표를 지속적으로 충족하지 못함
