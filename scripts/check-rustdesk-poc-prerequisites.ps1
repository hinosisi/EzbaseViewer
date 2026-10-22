[CmdletBinding()]
param(
    [string]$ClientSource,
    [string]$ServerSource
)

$ErrorActionPreference = 'Stop'
$failed = $false
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ClientSource)) {
    $ClientSource = Join-Path $projectRoot 'work\rustdesk-client-1.4.9'
}
if ([string]::IsNullOrWhiteSpace($ServerSource)) {
    $ServerSource = Join-Path $projectRoot 'work\rustdesk-server-1.1.16'
}

function Write-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $status = if ($Passed) { 'PASS' } else { 'MISSING' }
    Write-Output "$status $Name - $Detail"
    if (-not $Passed) {
        $script:failed = $true
    }
}

function Find-Command([string]$Name) {
    return Get-Command $Name -ErrorAction SilentlyContinue
}

function Get-ExecutablePath($Command) {
    if ($null -eq $Command) { return $null }
    if ($Command.PSObject.Properties.Name -contains 'Path' -and $Command.Path) {
        return $Command.Path
    }
    if ($Command.PSObject.Properties.Name -contains 'FullName' -and $Command.FullName) {
        return $Command.FullName
    }
    return $Command.Source
}

$git = Find-Command 'git'
Write-Check 'Git' ($null -ne $git) $(if ($git) { $git.Source } else { 'Install Git for Windows.' })

$gitBash = 'C:\Program Files\Git\bin\bash.exe'
Write-Check 'Git Bash' (Test-Path -LiteralPath $gitBash) $gitBash

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$visualStudio = if (Test-Path -LiteralPath $vswhere) {
    & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
} else {
    $null
}
Write-Check 'Visual Studio C++ workload' (-not [string]::IsNullOrWhiteSpace($visualStudio)) $(if ($visualStudio) { $visualStudio } else { 'Install the Desktop development with C++ workload.' })

$cmake = if ($visualStudio) { Join-Path $visualStudio 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' } else { '' }
$ninja = if ($visualStudio) { Join-Path $visualStudio 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe' } else { '' }
Write-Check 'CMake' ($cmake -and (Test-Path -LiteralPath $cmake)) $cmake
Write-Check 'Ninja' ($ninja -and (Test-Path -LiteralPath $ninja)) $ninja

$rustc = Find-Command 'rustc'
$cargo = Find-Command 'cargo'
$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
if (-not $rustc -and (Test-Path -LiteralPath (Join-Path $cargoBin 'rustc.exe'))) {
    $rustc = Get-Item -LiteralPath (Join-Path $cargoBin 'rustc.exe')
}
if (-not $cargo -and (Test-Path -LiteralPath (Join-Path $cargoBin 'cargo.exe'))) {
    $cargo = Get-Item -LiteralPath (Join-Path $cargoBin 'cargo.exe')
}
$rustup = Find-Command 'rustup'
if (-not $rustup -and (Test-Path -LiteralPath (Join-Path $cargoBin 'rustup.exe'))) {
    $rustup = Get-Item -LiteralPath (Join-Path $cargoBin 'rustup.exe')
}
$rustupPath = Get-ExecutablePath $rustup
$cargoPath = Get-ExecutablePath $cargo
$rustcOutput = if ($rustupPath) { & $rustupPath run 1.75.0 rustc --version 2>$null } else { $null }
$rustfmtOutput = if ($rustupPath) { & $rustupPath run 1.75.0 rustfmt --version 2>$null } else { $null }
Write-Check 'Rust compiler 1.75.0' ($rustcOutput -match '^rustc 1\.75\.0 ') $(if ($rustcOutput) { $rustcOutput } else { 'Install with rustup toolchain install 1.75.0 --profile minimal.' })
Write-Check 'rustfmt for Rust 1.75.0' ($rustfmtOutput -match '^rustfmt 1\.7\.0-stable') $(if ($rustfmtOutput) { $rustfmtOutput } else { 'Install with rustup component add rustfmt --toolchain 1.75.0.' })
Write-Check 'Cargo' ($null -ne $cargo) $(if ($cargoPath) { (& $cargoPath --version) } else { 'Installed with rustup.' })

$cargoExpand = Join-Path $cargoBin 'cargo-expand.exe'
$bridgeCodegen = Join-Path $cargoBin 'flutter_rust_bridge_codegen.exe'
$cargoExpandVersion = if (Test-Path -LiteralPath $cargoExpand) { & $cargoExpand --version } else { $null }
$bridgeVersion = if (Test-Path -LiteralPath $bridgeCodegen) { & $bridgeCodegen --version } else { $null }
Write-Check 'cargo-expand 1.0.95' ($cargoExpandVersion -match '1\.0\.95') $(if ($cargoExpandVersion) { $cargoExpandVersion } else { 'Install cargo-expand 1.0.95.' })
Write-Check 'flutter_rust_bridge_codegen 1.80.1' ($bridgeVersion -match '1\.80\.1') $(if ($bridgeVersion) { $bridgeVersion } else { 'Install flutter_rust_bridge_codegen 1.80.1 with uuid.' })

$llvmCandidates = @(
    $env:LIBCLANG_PATH,
    'C:\Program Files\LLVM\bin'
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$llvmPath = $llvmCandidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'libclang.dll') } | Select-Object -First 1
Write-Check 'LLVM/libclang 15.0.6' ($null -ne $llvmPath) $(if ($llvmPath) { $llvmPath } else { 'Install LLVM 15.0.6 and set LIBCLANG_PATH.' })

$flutterVersion = $null
$sideBySideFlutter = Join-Path $projectRoot 'work\toolchains\flutter-3.24.5'
$flutterVersionFile = 'C:\Users\admin\dev\flutter\bin\cache\flutter.version.json'
if (Test-Path -LiteralPath (Join-Path $sideBySideFlutter '.git')) {
    $flutterVersion = git -C $sideBySideFlutter describe --tags --exact-match
} elseif (Test-Path -LiteralPath $flutterVersionFile) {
    $flutterVersion = (Get-Content -LiteralPath $flutterVersionFile -Raw | ConvertFrom-Json).frameworkVersion
}
Write-Check 'Flutter 3.24.5' ($flutterVersion -eq '3.24.5') $(if ($flutterVersion) { "Found $flutterVersion at $sideBySideFlutter." } else { 'Install Flutter 3.24.5.' })

$vcpkgRoot = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { Join-Path $projectRoot 'work\toolchains\vcpkg-full' }
$vcpkgCommit = $null
if (Test-Path -LiteralPath (Join-Path $vcpkgRoot '.git')) {
    $vcpkgCommit = git -C $vcpkgRoot rev-parse HEAD
}
$expectedVcpkg = '120deac3062162151622ca4860575a33844ba10b'
Write-Check 'vcpkg pinned commit' ($vcpkgCommit -eq $expectedVcpkg) $(if ($vcpkgCommit) { "Found $vcpkgCommit; expected $expectedVcpkg." } else { "Clone commit $expectedVcpkg into $vcpkgRoot." })

$vcpkgStatus = Join-Path $vcpkgRoot 'installed\vcpkg\status'
$requiredPorts = @('aom', 'ffmpeg', 'libjpeg-turbo', 'libvpx', 'libyuv', 'mfx-dispatch', 'opus')
$installedPorts = if (Test-Path -LiteralPath $vcpkgStatus) { Get-Content -LiteralPath $vcpkgStatus -Raw } else { '' }
$installedStanzas = @($installedPorts -split "\r?\n\r?\n")
$missingPorts = @($requiredPorts | Where-Object {
    $packageName = $_
    -not ($installedStanzas | Where-Object {
        $_ -match "(?m)^Package: $([regex]::Escape($packageName))$" -and
        $_ -match '(?m)^Architecture: x64-windows-static$' -and
        $_ -match '(?m)^Status: install ok installed$'
    })
})
Write-Check 'vcpkg RustDesk static native packages' ($missingPorts.Count -eq 0) $(if ($missingPorts.Count -eq 0) { 'Required x64-windows-static codec and media packages are installed.' } else { "Missing static packages: $($missingPorts -join ', ')" })
$ffmpegHeader = Join-Path $vcpkgRoot 'installed\x64-windows-static\include\libavcodec\avcodec.h'
Write-Check 'Static FFmpeg headers' (Test-Path -LiteralPath $ffmpegHeader) $ffmpegHeader

$expectedClient = '6c578292e8ebbbec708b76986ba8c4bc7c509747'
$clientCommit = if (Test-Path -LiteralPath (Join-Path $ClientSource '.git')) { git -C $ClientSource rev-parse HEAD } else { $null }
Write-Check 'RustDesk Client source' ($clientCommit -eq $expectedClient) $(if ($clientCommit) { $clientCommit } else { "Clone tag 1.4.9 into $ClientSource." })
$expectedClientCommon = '7e1c392c62d39c364127307cd408421dd5f8cfb0'
$clientCommon = Join-Path $ClientSource 'libs\hbb_common'
$clientCommonCommit = if (Test-Path -LiteralPath (Join-Path $clientCommon '.git')) { git -C $clientCommon rev-parse HEAD } else { $null }
Write-Check 'RustDesk Client hbb_common' ($clientCommonCommit -eq $expectedClientCommon) $(if ($clientCommonCommit) { $clientCommonCommit } else { 'Run git submodule update --init --recursive in the Client source.' })

$expectedServer = '73523b31cfd25d77dee862e6fc9f5e1fb5e485ef'
$serverCommit = if (Test-Path -LiteralPath (Join-Path $ServerSource '.git')) { git -C $ServerSource rev-parse HEAD } else { $null }
Write-Check 'RustDesk Server source' ($serverCommit -eq $expectedServer) $(if ($serverCommit) { $serverCommit } else { "Clone tag 1.1.16 into $ServerSource." })
$expectedServerCommon = '83419b6549636ee39dacef7776c473f5802e08d6'
$serverCommon = Join-Path $ServerSource 'libs\hbb_common'
$serverCommonCommit = if (Test-Path -LiteralPath (Join-Path $serverCommon '.git')) { git -C $serverCommon rev-parse HEAD } else { $null }
Write-Check 'RustDesk Server hbb_common' ($serverCommonCommit -eq $expectedServerCommon) $(if ($serverCommonCommit) { $serverCommonCommit } else { 'Run git submodule update --init --recursive in the Server source.' })

if ($failed) {
    Write-Error 'RustDesk PoC prerequisites are incomplete.'
    exit 1
}

Write-Output 'PASS RustDesk PoC prerequisites are ready.'
