# RustDesk PoC 준비 현황

> 점검일: 2026-10-22
> 대상: RustDesk Client `1.4.9`, RustDesk Server OSS `1.1.16`

## 소스 기준선

| 대상 | 태그·커밋 | 잠금 파일 SHA-256 | 상태 |
|---|---|---|---|
| RustDesk Client | `1.4.9`, `6c578292e8ebbbec708b76986ba8c4bc7c509747` | `48F8A82E8C6FC0CCA8F5278BE948A91FC85107AED3238363C6095A9B8C74539C` | 공식 저장소 얕은 복제 완료 |
| `hbb_common` submodule | `7e1c392c62d39c364127307cd408421dd5f8cfb0` | 해당 없음 | Client가 지정한 커밋 복제 완료 |
| RustDesk Server OSS | `1.1.16`, `73523b31cfd25d77dee862e6fc9f5e1fb5e485ef` | `F5E17E33F48875A3A63C14002A6D94278AC6A02381C2E4C1934900823BC31528` | 공식 저장소 얕은 복제 완료 |
| Server `hbb_common` submodule | `83419b6549636ee39dacef7776c473f5802e08d6` | 해당 없음 | Server가 지정한 커밋 복제 완료 |
| Client·Server 라이선스 본문 | AGPL-3.0 | `6F1E622C82A380075843BB084A7EC3B1F1D12A4A02526D75E78B0924A860AA75` | 동일 본문 해시 확인 |

복제 소스는 공개 저장소의 `work/`에 두고 Git 추적에서 제외했다. 분석 기록과 패치만 검토 후 공개 저장소 또는 향후 공개 AGPL 포크에 반영한다.

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
pwsh -NoProfile -File .\scripts\check-rustdesk-poc-prerequisites.ps1
pwsh -NoProfile -File .\scripts\build-rustdesk-poc.ps1
```

2026-10-22 전체 실행에서 사전 점검, Client bridge 생성, Client Windows Release, Server Release, 산출물 검사까지 연속 통과했다. 빌드 스크립트는 Windows 긴 경로를 피하려고 작업 중에만 `R:`을 `work/`에 연결하며 종료 시 해제한다. 다른 드라이브 문자가 필요하면 `-ShortDrive S`처럼 지정한다. Client bridge 생성 시 공식 CI 절차에 맞춰 `extended_text`를 잠시 `13.0.0`으로 내리고 생성 후 원래 `14.0.0`으로 복원한다. Flutter CMake가 절대 드라이브 경로를 캐시하므로, 스크립트는 현재 빌드 전에 생성된 `flutter/build/windows`만 경로 검증 후 정리한다.

## 다음 실행

1. `scripts/check-rustdesk-poc-prerequisites.ps1`로 준비 상태를 재현한다.
2. 생성된 `hbbs`·`hbbr`를 격리 시험망에서 기동하고 임시 키·포트·로그 보존 위치를 기록한다.
3. 원본 Client 두 대를 자체 서버에 연결해 직접 연결과 강제 중계 연결을 구분해 확인한다.
4. 공개 AGPL 포크를 만들고 `ezbaseviewer-hostonly` 브랜치에서 HostOnly 변경을 시작한다.
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
