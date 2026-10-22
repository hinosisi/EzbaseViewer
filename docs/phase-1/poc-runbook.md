# RustDesk 통합 PoC 실행서

## 준비

- 격리된 Windows 10/11 x64 시험 PC 또는 VM
- 관리자 PC 2대, 호스트 4대 이상
- 사내망과 서로 다른 인터넷 회선 2개
- 표준 사용자·관리자 사용자, 다중 모니터 1대 이상
- 패킷 메타데이터·CPU·GPU·메모리·대역폭 측정 수단
- RustDesk Client `1.4.9`와 Server OSS `1.1.16` 소스·릴리스 자산
- AGPL-3.0 원문, 포크 공개·대응 소스 제공 절차

## Host 시험 패키지 준비

빌드 PC에서 다음 명령을 실행한다. Flutter Windows 플러그인 심볼릭 링크를 위해 Windows 개발자 모드가 켜져 있어야 한다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-rustdesk-host-poc.ps1
Get-FileHash .\artifacts\rustdesk-host-poc\EzbaseViewerHost-win-x64.zip -Algorithm SHA256
```

시험 PC에는 `EzbaseViewerHost-win-x64.zip`만 복사한다. 압축을 새 폴더에 풀고 `build-manifest.json`의 `ExecutableSHA256`과 다음 명령의 결과가 같은지 확인한다.

```powershell
Get-FileHash .\rustdesk.exe -Algorithm SHA256
(Get-Item .\rustdesk.exe).VersionInfo | Select-Object ProductName,FileDescription,CompanyName,ProductVersion
Get-AuthenticodeSignature .\rustdesk.exe | Select-Object Status,SignerCertificate
```

현재 PoC 패키지의 기대 제품명은 `EzbaseViewer Host`, 회사명은 `EzbaseViewer Contributors`다. 개발 패키지는 미서명이므로 격리 시험 PC에서만 실행한다. `rustdesk.exe`와 같은 폴더의 DLL 및 `data` 디렉터리를 함께 유지해야 한다.

Host 프로필은 fail-closed로 동작한다. EzbaseViewer 자체 rendezvous 서버를 명시하기 전에는 서버 등록, NAT 검사와 자동 업데이트 통신을 시작하지 않아야 한다. `rustdesk.com`과 그 하위 도메인은 포트가 붙은 주소도 허용하지 않는다. 자체 `hbbs`·`hbbr`를 준비하기 전의 실행 시험에서는 Host 프로세스와 제품 메타데이터만 확인하고 외부 접속 성공을 기대하지 않는다.

## 실행 순서

1. RustDesk 소스 태그·커밋과 설치 파일의 버전, 서명자, SHA-256, 획득 URL을 기록한다.
2. 관리자 Viewer·HostOnly·`hbbs`·`hbbr` 구성요소와 프로세스 트리를 기록한다.
3. rendezvous 설정이 없는 Host가 오프라인을 유지하고 RustDesk 공용 인프라에 연결하지 않는지 확인한 뒤 자체 `hbbs`·`hbbr` 주소와 공개키를 적용한다.
4. 같은 사내망, 서로 다른 인터넷 회선에서 접속한다.
5. 직접 경로를 차단하고 제한 시간, 오류, 중계 전환 여부를 기록한다.
6. 일반 데스크톱, UAC 보안 데스크톱, 잠금·로그온 화면에서 보기와 입력을 시험한다.
7. 사용자 전환·로그오프·서비스 재시작·PC 재부팅을 수행한다.
8. 다중 모니터 전환과 서로 다른 DPI·해상도를 시험한다.
9. 1GB 파일과 다수 소파일을 양방향 전송하고 SHA-256을 비교한다.
10. 무인 접속 허용·철회, 현장 종료, 관리자 종료 후 재접속을 시험한다.
11. 8시간 연속 세션, 반복 연결 100회를 수행한다.
12. Ezbase 제어 서버의 사용자·업체·기능 권한을 엔진에 적용할 수 있는 지점을 확인한다.
13. Host 빌드에 Viewer·대상 검색·접속 시작 기능이 포함되지 않았는지 확인한다.
14. AGPL 고지, 포크 소스 공개와 재현 빌드 절차를 검증한다.
15. 증거를 검토하고 RustDesk 필수 게이트를 승인한다.

## 결과 기록

```text
RustDesk Client/Server 버전·커밋:
설치 파일 SHA-256/서명자:
시험 환경:
시나리오 ID:
사전 조건:
수행 절차:
기대 결과:
실제 결과:
직접/중계 경로:
CPU/GPU/메모리/대역폭:
로그·화면·캡처 증거:
보안·개인정보 관찰:
통과 여부와 결함 ID:
수행자/검토자/일시:
```

## 중단 기준

- 허가되지 않은 대상 파일이나 라이선스 우회가 필요해진 경우
- 회사 시험 계정 밖의 제3자 시스템으로 트래픽이 전송되는 경우
- UAC·로그온 화면 시험이 업체 PC 보호 설정을 약화해야만 성공하는 경우
- 실행 파일 서명 또는 공급 경로를 확인할 수 없는 경우
