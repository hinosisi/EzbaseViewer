[CmdletBinding()]
param(
    [ValidatePattern('^[D-Zd-z]$')]
    [string]$ShortDrive = 'R',
    [switch]$SkipClient,
    [switch]$SkipServer
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$workRoot = Join-Path $projectRoot 'work'
$clientSource = Join-Path $workRoot 'rustdesk-client-1.4.9'
$serverSource = Join-Path $workRoot 'rustdesk-server-1.1.16'
$flutterRoot = Join-Path $workRoot 'toolchains\flutter-3.24.5'
$vcpkgRoot = Join-Path $workRoot 'toolchains\vcpkg-full'
$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
$python = Join-Path $vcpkgRoot 'downloads\tools\python\python-3.12.7-x64-1\python.exe'

function Invoke-External([string]$FilePath, [string[]]$Arguments) {
    Write-Output "> $FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

function Write-Artifact([string]$Name, [string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Expected artifact is missing: $Path"
    }

    $file = Get-Item -LiteralPath $Path
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    [pscustomobject]@{
        Name = $Name
        Path = $file.FullName
        Bytes = $file.Length
        SHA256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        SignatureStatus = $signature.Status
    }
}

& (Join-Path $PSScriptRoot 'check-rustdesk-poc-prerequisites.ps1') -ClientSource $clientSource -ServerSource $serverSource
if ($LASTEXITCODE -ne 0) {
    throw 'RustDesk PoC prerequisite check failed.'
}

$driveName = $ShortDrive.ToUpperInvariant()
if (Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue) {
    throw "$driveName`: is already in use. Pass another drive letter with -ShortDrive."
}

$mounted = $false
Invoke-External 'subst.exe' @("$driveName`:", $workRoot)
$mounted = $true
try {
    $shortRoot = "$driveName`:"
    $shortClient = "$shortRoot\rustdesk-client-1.4.9"
    $shortServer = "$shortRoot\rustdesk-server-1.1.16"
    $shortFlutter = "$shortRoot\toolchains\flutter-3.24.5"
    $shortVcpkg = "$shortRoot\toolchains\vcpkg-full"

    $env:VCPKG_ROOT = $shortVcpkg
    $env:VCPKG_DEFAULT_TRIPLET = 'x64-windows-static'
    $env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
    $env:LIBCLANG_PATH = 'C:\Program Files\LLVM\bin'
    $env:RUST_LOG = 'info'
    $env:Path = "$shortFlutter\bin;$cargoBin;C:\Program Files\LLVM\bin;$env:Path"

    $artifacts = @()

    if (-not $SkipClient) {
        $env:RUSTUP_TOOLCHAIN = '1.75.0'
        Push-Location $shortClient
        try {
            Invoke-External "$shortVcpkg\vcpkg.exe" @(
                'install',
                '--triplet', 'x64-windows-static',
                '--host-triplet', 'x64-windows-static',
                "--x-install-root=$shortVcpkg\installed"
            )

            $pubspec = Join-Path $shortClient 'flutter\pubspec.yaml'
            $originalPubspec = [System.IO.File]::ReadAllText($pubspec)
            $bridgePubspec = $originalPubspec.Replace('extended_text: 14.0.0', 'extended_text: 13.0.0')
            if ($bridgePubspec -eq $originalPubspec) {
                throw 'Expected extended_text 14.0.0 pin was not found in flutter/pubspec.yaml.'
            }

            try {
                [System.IO.File]::WriteAllText($pubspec, $bridgePubspec, [System.Text.UTF8Encoding]::new($false))
                Push-Location (Join-Path $shortClient 'flutter')
                try {
                    Invoke-External "$shortFlutter\bin\flutter.bat" @('pub', 'get')
                } finally {
                    Pop-Location
                }

                Invoke-External "$cargoBin\flutter_rust_bridge_codegen.exe" @(
                    '--rust-input', '.\src\flutter_ffi.rs',
                    '--dart-output', '.\flutter\lib\generated_bridge.dart',
                    '--c-output', '.\flutter\macos\Runner\bridge_generated.h'
                )
            } finally {
                [System.IO.File]::WriteAllText($pubspec, $originalPubspec, [System.Text.UTF8Encoding]::new($false))
                Push-Location (Join-Path $shortClient 'flutter')
                try {
                    Invoke-External "$shortFlutter\bin\flutter.bat" @('pub', 'get')
                } finally {
                    Pop-Location
                }
            }

            # Flutter stores the absolute source drive in CMakeCache.txt. Remove only
            # the generated Windows directory so a prior R:/S: subst build cannot
            # contaminate the current reproducible build.
            $flutterWindowsBuild = Join-Path $clientSource 'flutter\build\windows'
            $expectedBuildRoot = [System.IO.Path]::GetFullPath((Join-Path $clientSource 'flutter\build'))
            $resolvedWindowsBuild = [System.IO.Path]::GetFullPath($flutterWindowsBuild)
            if (-not $resolvedWindowsBuild.StartsWith($expectedBuildRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove unexpected Flutter build path: $resolvedWindowsBuild"
            }
            if (Test-Path -LiteralPath $resolvedWindowsBuild) {
                Write-Output "> Remove generated Flutter Windows build cache: $resolvedWindowsBuild"
                Remove-Item -LiteralPath $resolvedWindowsBuild -Recurse -Force
            }

            Invoke-External $python @('build.py', '--portable', '--flutter', '--skip-portable-pack', '--hwcodec')
            $clientExe = Join-Path $clientSource 'flutter\build\windows\x64\runner\Release\rustdesk.exe'
            $artifacts += Write-Artifact 'RustDesk Client' $clientExe
        } finally {
            Pop-Location
        }
    }

    if (-not $SkipServer) {
        Remove-Item Env:RUSTUP_TOOLCHAIN -ErrorAction SilentlyContinue
        Push-Location $shortServer
        try {
            Invoke-External 'git' @('submodule', 'update', '--init', '--recursive')
            Invoke-External "$cargoBin\cargo.exe" @('build', '--release', '--locked')
            $releaseRoot = Join-Path $serverSource 'target\release'
            $artifacts += Write-Artifact 'RustDesk ID/Rendezvous Server' (Join-Path $releaseRoot 'hbbs.exe')
            $artifacts += Write-Artifact 'RustDesk Relay Server' (Join-Path $releaseRoot 'hbbr.exe')
        } finally {
            Pop-Location
        }
    }

    $artifacts | Format-Table -AutoSize
} finally {
    Set-Location $projectRoot
    if ($mounted) {
        Invoke-External 'subst.exe' @("$driveName`:", '/D')
    }
}
