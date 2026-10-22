# RustDesk PoC 준비 현황

> 점검일: 2026-10-23
> 대상: RustDesk Client `1.4.9`, RustDesk Server OSS `1.1.16`

## 소스 기준선

| 대상 | 태그·커밋 | 잠금 파일 SHA-256 | 상태 |
|---|---|---|---|
| RustDesk Client | `1.4.9`, `6c578292e8ebbbec708b76986ba8c4bc7c509747` | `48F8A82E8C6FC0CCA8F5278BE948A91FC85107AED3238363C6095A9B8C74539C` | 공식 저장소 얕은 복제 완료 |
| `hbb_common` submodule | `7e1c392c62d39c364127307cd408421dd5f8cfb0` | 해당 없음 | Client가 지정한 커밋 복제 완료 |
| RustDesk Server OSS | `1.1.16`, `73523b31cfd25d77dee862e6fc9f5e1fb5e485ef` | `F5E17E33F48875A3A63C14002A6D94278AC6A02381C2E4C1934900823BC31528` | 공식 저장소 얕은 복제 완료 |
| Server `hbb_common` submodule | `83419b6549636ee39dacef7776c473f5802e08d6` | 해당 없음 | Server가 지정한 커밋 복제 완료 |
| Client·Server 라이선스 본문 | AGPL-3.0 | `6F1E622C82A380075843BB084A7EC3B1F1D12A4A02526D75E78B0924A860AA75` | 동일 본문 해시 확인 |

원본 복제 소스는 공개 저장소의 `work/`에 두고 Git 추적에서 제외했다. 제품 변경은 AGPL-3.0 공개 포크 [hinosisi/EzbaseViewer-rustdesk](https://github.com/hinosisi/EzbaseViewer-rustdesk)의 `ezbaseviewer-hostonly` 브랜치에 반영한다. 최초 HostOnly 변경은 `b7c2bad`, 제품 메타데이터 반영은 `f063ba2`, 자체 rendezvous 설정 전 fail-closed 동작은 `1348903`이다.

## Windows 빌드 기준

Client `1.4.9`의 고정 파일과 공식 워크플로에서 다음 값을 확인했다.

| 항목 | 기준 |
|---|---|
| Rust 최소 버전 | `1.75` (`Cargo.toml`) |
| Flutter | `3.24.5` (`flutter-build.yml`) |
| LLVM | `15.0.6` (`flutter-build.yml`) |
| vcpkg | commit `120deac3062162151622ca4860575a33844ba10b` |
| Windows target | `x86_64-pc-windows-msvc`, `windows-2022` 기준 워크플로 |
| 빌드 진입점 | `python3 build.py --portable --flutter --skip-portable-pack --hwcodec` 계열 |

RustDesk 공식 Windows 빌드 문서는 MSVC C++ workload, Rust, vcpkg, LLVM/libclang과 Git Bash를 요구한다. PoC는 공식 일반 문서의 최신 값보다 선택한 `1.4.9` 소스 내부의 고정 버전을 우선한다.

## 현재 PC 점검 결과

| 항목 | 상태 | 조치 |
|---|---|---|
| Git·Git Bash | 준비 | 유지 |
| Visual Studio 2022 Community C++ workload | 준비 | Developer 환경에서 사용 |
| Visual Studio 번들 CMake·Ninja | 준비 | 절대 경로 또는 Developer 환경으로 노출 |
| Rust·Cargo | 준비 | Rustup으로 공식 CI 기준 `1.75.0-x86_64-pc-windows-msvc`와 해당 `rustfmt 1.7.0`을 나란히 설치·확인 |
| Flutter-Rust bridge | 준비 | `cargo-expand 1.0.95`, `flutter_rust_bridge_codegen 1.80.1` 설치·생성 성공 |
| LLVM/libclang `15.0.6` | 준비 | `C:\Program Files\LLVM\bin` 설치, 빌드 환경에 `LIBCLANG_PATH` 설정 필요 |
| Flutter | 준비 | 기존 `3.29.3`을 변경하지 않고 `3.24.5`를 `work/toolchains`에 나란히 복제 |
| vcpkg | 준비 | 지정 커밋을 `work/toolchains/vcpkg-full`에 완전 복제·bootstrap하고 Client 매니페스트를 target·host 모두 `x64-windows-static`으로 설치 완료 |
| Docker | 미설치 | Server OSS는 우선 Windows `hbbs.exe`·`hbbr.exe` 빌드/릴리스로 시험하고 Docker는 운영 배치 결정 시 추가 |

## 원본 빌드 재현 결과

수정하지 않은 고정 소스에서 Client와 Server의 Windows Release 빌드를 완료했다. 빌드 결과는 `work/` 아래에 있으며 Git 추적·배포 대상이 아니다. 제품 배포 전에는 EzbaseViewer 이름·아이콘·정책 반영, SBOM, 코드 서명과 악성코드 검사를 별도 수행한다.

| 산출물 | 크기 | SHA-256 | Authenticode |
|---|---:|---|---|
| Client `rustdesk.exe` (`1.4.9+67`) | 358,400 bytes | `48D3A98CBC7EDCF412DAA91947AE01D56A6CD3DB38E5A8D7DF732B2A9747E9FA` | 미서명 |
| Server `hbbs.exe` | 6,691,328 bytes | `63297AD4D96494732DF9A15489CD4EF825B8F7B504FF855F3F78D1CC6A944F73` | 미서명 |
| Server `hbbr.exe` | 2,697,728 bytes | `B602DD116003F59498AA3C14F6B1C62EE28086AFFEA1E97BB4FACFF09600A041` | 미서명 |

재현 명령은 다음과 같다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-rustdesk-poc-prerequisites.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-rustdesk-poc.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-rustdesk-server.ps1
```

2026-10-22 전체 실행에서 사전 점검, Client bridge 생성, Client Windows Release, Server Release, 산출물 검사까지 연속 통과했다. 빌드 스크립트는 Windows 긴 경로를 피하려고 작업 중에만 `R:`을 `work/`에 연결하며 종료 시 해제한다. 다른 드라이브 문자가 필요하면 `-ShortDrive S`처럼 지정한다. Client bridge 생성 시 공식 CI 절차에 맞춰 `extended_text`를 잠시 `13.0.0`으로 내리고 생성 후 원래 `14.0.0`으로 복원한다. Flutter CMake가 절대 드라이브 경로를 캐시하므로, 스크립트는 현재 빌드 전에 생성된 `flutter/build/windows`만 경로 검증 후 정리한다.

## Server 로컬 기동 검증

빌드한 Server를 외부에 노출하지 않는 로컬 PoC 설정으로 5초간 실행하고 프로세스·수신 포트·키 생성을 확인했다. 검사는 `scripts/smoke-rustdesk-server.ps1`로 재현하며 종료 경로에서 두 프로세스를 정리한다.

| 프로세스 | 확인 항목 | 결과 |
|---|---|---|
| `hbbs.exe -p 22116 -r 127.0.0.1:22117` | TCP `22115`, `22116`, `22118`; UDP `22116` | 통과 |
| `hbbr.exe -p 22117` | TCP `22117`, `22119` | 통과 |
| `hbbs.exe` | `id_ed25519`, `id_ed25519.pub` 생성 | 통과, 키 값은 비공개·Git 제외 |
| 두 프로세스 | 시작 탐색 중 실행 유지, stderr 비어 있음, 탐색 후 종료 | 통과 |

이 검증은 로컬 프로세스 기동 게이트다. 서로 다른 인터넷 회선의 직접 연결, 강제 중계와 실제 Client 연결 성공을 증명하지 않는다.

## HostOnly 포크 검증

공개 포크의 `ezbaseviewer-hostonly` 브랜치에 Cargo 기능 `ezbaseviewer-host`를 추가했다. 이 기능은 기존 incoming-only UI를 활성화하고 Rust 연결 코어가 외부 대상 연결을 시작하지 못하게 한다. Windows 제품 메타데이터와 런타임 앱 이름은 `EzbaseViewer Host`로 구분한다. 자체 rendezvous 서버가 명시되지 않았거나 `rustdesk.com` 계열 주소가 설정되면 등록 루프 진입 전에 대기하며 NAT·rendezvous 검사와 RustDesk 자동 업데이트 호출도 차단한다.

| 검증 | 결과 |
|---|---|
| `cargo +1.75.0 check --locked --features flutter,hwcodec,ezbaseviewer-host --lib` | 통과 |
| Host 프로필·rendezvous 정책 단위시험 | 통과, 2개 실행 |
| Windows Flutter Release 전체 빌드 | 통과, `ezbaseviewer-host`, `hwcodec`, `flutter` 기능 적용 |
| 런타임 패키지 | 통과, 92개 파일을 `EzbaseViewerHost-win-x64.zip`으로 묶고 압축 해제 후 실행 파일 해시 일치 확인 |
| 실행 파일 메타데이터 | `EzbaseViewer Host`, `EzbaseViewer Contributors`, `1.4.9+67` 확인 |
| 실행 파일 스모크 | 패키지 안의 `rustdesk.exe --version` 종료 코드 0 |
| 공개 브랜치 | `hinosisi/EzbaseViewer-rustdesk:ezbaseviewer-hostonly` |

시험 산출물은 Git에서 제외된 `artifacts/rustdesk-host-poc/`에 둔다.

| 산출물 | 크기 | SHA-256 | Authenticode |
|---|---:|---|---|
| Host 실행 파일 `rustdesk.exe` | 358,400 bytes | `3419FCBAB99BE06A84BBF3B0426D7079230D167EDB468616B3B01EC9A49A04DC` | 미서명 |
| `EzbaseViewerHost-win-x64.zip` | 31,631,440 bytes | `478B63009DDA69E887FC4A61A64EBA1C6DC1FB6E502DA673C1D21CB347A9831F` | 해당 없음 |

`f063ba2` 기준 이전 패키지는 Windows 11 VM에서 일반 사용자로 ZIP·실행 파일 해시, 92개 파일, 제품 메타데이터와 5초 후 프로세스 실행 유지를 확인해 PASS를 기록했다. 위 표의 `1348903` 보안 게이트 패키지는 같은 VM에 배포했으며 재실행 확인이 남아 있다. 실제 설치형 서비스, 수신 연결, UAC·로그온 화면과 재부팅 후 재접속은 장치 시험에서 판정한다. 미서명 패키지는 개발 시험에만 사용한다.

## 다음 실행

1. `scripts/check-rustdesk-poc-prerequisites.ps1`로 준비 상태를 재현한다.
2. 생성된 `hbbs`·`hbbr`의 로컬 기동 스모크 결과를 기준으로 격리 시험망의 서버 주소·방화벽·로그 보존 위치를 확정한다.
3. 원본 Client 두 대를 격리 시험망 서버에 연결해 직접 연결과 강제 중계 연결을 구분해 확인한다.
4. 압축을 해제한 Host를 격리된 Windows 시험 장치에 실행해 접속 시작 UI가 없고, 자체 rendezvous 설정 전에는 외부 서버에 등록하지 않는지 확인한다.
5. `poc-runbook.md`의 다중 모니터, 파일 무결성, 단절·재접속, UAC·로그온, 재부팅 게이트를 순서대로 수행한다.
6. 통과 증거와 미통과 항목을 ADR에 연결해 핵심 개발 착수 여부를 결정한다.

## 알려진 빌드 경고

- RustDesk 오버레이 `opus` 포트는 `x64-windows-static` 설치에서 정적 CRT 요청과 다른 `/MD`, `/MDd` 링크 경고를 냈다. upstream 포트 동작으로 기록하고 최종 배포 바이너리의 CRT 의존성을 별도로 검사한다.
- libyuv 포트는 MSVC 빌드 시 SIMD 가속이 느릴 수 있다는 경고를 출력했다. upstream 포트가 내부적으로 clang target을 사용했는지 빌드 로그와 성능시험에서 확인한다.
- Client·Server 링크에서 `libsodium.pdb` 부재 경고가 발생했다. Release 실행 파일 생성에는 성공했으나 충돌 분석용 심볼 확보 방안을 운영 빌드 전에 확정한다.
- Client 링크에서 Opus의 `/MD`와 Rust 정적 CRT의 혼용에 따른 `LNK4098` 경고가 발생했다. UAC·로그온 검증과 별개로 런타임 안정성·의존 DLL·재배포 조건을 검사한다.
- 최신 기본 Rust `1.99.1`에서도 빌드는 성공했지만 재현 스크립트는 공식 CI 기준 `1.75.0`을 사용한다.
- 기존 긴 작업 경로에서는 vcpkg 버전 checkout이 Windows 경로 제한을 초과했다. 재현 빌드는 임시 짧은 드라이브 경로를 사용한다.
- Release 결과 해시는 입력 소스와 잠금 파일 식별용 해시가 아니다. 컴파일러·링커·절대 경로 등 빌드 환경의 영향을 받을 수 있으므로 각 검증 실행에서 새로 기록하고, 배포 승인 시 그 실행의 바이너리와 SBOM을 함께 보존한다.

## 근거

- RustDesk Windows build: <https://rustdesk.com/docs/en/dev/build/windows/>
- RustDesk Client `1.4.9` source: <https://github.com/rustdesk/rustdesk/releases/tag/1.4.9>
- RustDesk Server OSS `1.1.16` source: <https://github.com/rustdesk/rustdesk-server/releases/tag/1.1.16>
