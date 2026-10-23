[CmdletBinding()]
param(
    [string]$ViewerSource,
    [ValidatePattern('^[D-Zd-z]$')]
    [string]$ShortDrive = 'R'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputsRoot = Split-Path -Parent $projectRoot
if ([string]::IsNullOrWhiteSpace($ViewerSource)) {
    $ViewerSource = Join-Path $outputsRoot 'EzbaseViewer-rustdesk'
}
$ViewerSource = [System.IO.Path]::GetFullPath($ViewerSource)
$workRoot = Join-Path $projectRoot 'work'
$baselineClient = Join-Path $workRoot 'rustdesk-client-1.4.9'
$baselineServer = Join-Path $workRoot 'rustdesk-server-1.1.16'
$flutterRoot = Join-Path $workRoot 'toolchains\flutter-3.24.5'
$vcpkgRoot = Join-Path $workRoot 'toolchains\vcpkg-full'
$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
$python = Join-Path $vcpkgRoot 'downloads\tools\python\python-3.12.7-x64-1\python.exe'
$artifactRoot = Join-Path $projectRoot 'artifacts\rustdesk-viewer-poc'

function Invoke-External([string]$FilePath, [string[]]$Arguments) {
    Write-Output "> $FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $ViewerSource '.git'))) {
    throw "EzbaseViewer RustDesk fork checkout is missing: $ViewerSource"
}

$branch = (& git -C $ViewerSource branch --show-current).Trim()
if ($branch -ne 'ezbaseviewer-hostonly') {
    throw "Expected ezbaseviewer-hostonly branch, found '$branch'."
}

$cargoManifest = Get-Content -LiteralPath (Join-Path $ViewerSource 'Cargo.toml') -Raw
if ($cargoManifest -notmatch '(?m)^ezbaseviewer-viewer\s*=') {
    throw 'The EzbaseViewer Viewer Cargo feature is missing.'
}

$developerMode = (Get-ItemProperty `
    -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
    -Name AllowDevelopmentWithoutDevLicense `
    -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
if ($developerMode -ne 1) {
    throw 'Windows Developer Mode is required so Flutter can create plugin symlinks.'
}

& (Join-Path $PSScriptRoot 'check-rustdesk-poc-prerequisites.ps1') `
    -ClientSource $baselineClient `
    -ServerSource $baselineServer
if ($LASTEXITCODE -ne 0) {
    throw 'RustDesk PoC prerequisite check failed.'
}

$driveName = $ShortDrive.ToUpperInvariant()
if (Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue) {
    throw "$driveName`: is already in use. Pass another drive letter with -ShortDrive."
}

$mounted = $false
Invoke-External 'subst.exe' @("$driveName`:", $outputsRoot)
$mounted = $true
try {
    $shortHost = "$driveName`:\EzbaseViewer-rustdesk"
    $shortFlutter = "$driveName`:\EzbaseViewer\work\toolchains\flutter-3.24.5"
    $shortVcpkg = "$driveName`:\EzbaseViewer\work\toolchains\vcpkg-full"

    $env:VCPKG_ROOT = $shortVcpkg
    $env:VCPKG_DEFAULT_TRIPLET = 'x64-windows-static'
    $env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
    $env:LIBCLANG_PATH = 'C:\Program Files\LLVM\bin'
    $env:RUSTUP_TOOLCHAIN = '1.75.0'
    $env:RUST_LOG = 'info'
    $env:Path = "$shortFlutter\bin;$cargoBin;C:\Program Files\LLVM\bin;$env:Path"

    Push-Location $shortHost
    try {
        Invoke-External "$shortVcpkg\vcpkg.exe" @(
            'install',
            '--triplet', 'x64-windows-static',
            '--host-triplet', 'x64-windows-static',
            "--x-install-root=$shortVcpkg\installed"
        )

        $pubspec = Join-Path $shortHost 'flutter\pubspec.yaml'
        $pubspecLock = Join-Path $shortHost 'flutter\pubspec.lock'
        $runnerResource = Join-Path $shortHost 'flutter\windows\runner\Runner.rc'
        $cargoToml = Join-Path $shortHost 'Cargo.toml'
        $originalPubspec = [System.IO.File]::ReadAllBytes($pubspec)
        $originalPubspecLock = if (Test-Path -LiteralPath $pubspecLock) {
            [System.IO.File]::ReadAllBytes($pubspecLock)
        } else {
            $null
        }
        $originalRunnerResource = [System.IO.File]::ReadAllBytes($runnerResource)
        $originalCargoToml = [System.IO.File]::ReadAllBytes($cargoToml)

        try {
            $runnerResourceText = [System.Text.Encoding]::UTF8.GetString($originalRunnerResource)
            $runnerResourceText = $runnerResourceText.Replace(
                'EzbaseViewer Host Remote Support Agent',
                'EzbaseViewer Viewer Remote Support Console'
            ).Replace(
                'EzbaseViewerHost',
                'EzbaseViewerViewer'
            ).Replace(
                'ezbaseviewer-host.exe',
                'ezbaseviewer-viewer.exe'
            ).Replace(
                'EzbaseViewer Host',
                'EzbaseViewer Viewer'
            )
            [System.IO.File]::WriteAllText(
                $runnerResource,
                $runnerResourceText,
                [System.Text.UTF8Encoding]::new($false)
            )

            $cargoTomlText = [System.Text.Encoding]::UTF8.GetString($originalCargoToml)
            $cargoTomlText = $cargoTomlText.Replace(
                'ProductName = "EzbaseViewer Host"',
                'ProductName = "EzbaseViewer Viewer"'
            ).Replace(
                'FileDescription = "EzbaseViewer Host Remote Support Agent"',
                'FileDescription = "EzbaseViewer Viewer Remote Support Console"'
            ).Replace(
                'OriginalFilename = "ezbaseviewer-host.exe"',
                'OriginalFilename = "ezbaseviewer-viewer.exe"'
            )
            [System.IO.File]::WriteAllText(
                $cargoToml,
                $cargoTomlText,
                [System.Text.UTF8Encoding]::new($false)
            )

            $pubspecText = [System.Text.Encoding]::UTF8.GetString($originalPubspec)
            $bridgePubspec = $pubspecText.Replace('extended_text: 14.0.0', 'extended_text: 13.0.0')
            if ($bridgePubspec -eq $pubspecText) {
                throw 'Expected extended_text 14.0.0 pin was not found in flutter/pubspec.yaml.'
            }

            [System.IO.File]::WriteAllText(
                $pubspec,
                $bridgePubspec,
                [System.Text.UTF8Encoding]::new($false)
            )
            Push-Location (Join-Path $shortHost 'flutter')
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

            [System.IO.File]::WriteAllBytes($pubspec, $originalPubspec)
            Push-Location (Join-Path $shortHost 'flutter')
            try {
                Invoke-External "$shortFlutter\bin\flutter.bat" @('pub', 'get')
            } finally {
                Pop-Location
            }

            $flutterWindowsBuild = Join-Path $ViewerSource 'flutter\build\windows'
            $expectedBuildRoot = [System.IO.Path]::GetFullPath((Join-Path $ViewerSource 'flutter\build'))
            $resolvedWindowsBuild = [System.IO.Path]::GetFullPath($flutterWindowsBuild)
            if (-not $resolvedWindowsBuild.StartsWith(
                    $expectedBuildRoot,
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove unexpected Flutter build path: $resolvedWindowsBuild"
            }
            if (Test-Path -LiteralPath $resolvedWindowsBuild) {
                Write-Output "> Remove generated Flutter Windows build cache: $resolvedWindowsBuild"
                Remove-Item -LiteralPath $resolvedWindowsBuild -Recurse -Force
            }

            Invoke-External $python @(
                'build.py',
                '--portable',
                '--flutter',
                '--skip-portable-pack',
                '--hwcodec',
                '--ezbaseviewer-viewer'
            )
        } finally {
            [System.IO.File]::WriteAllBytes($pubspec, $originalPubspec)
            [System.IO.File]::WriteAllBytes($runnerResource, $originalRunnerResource)
            [System.IO.File]::WriteAllBytes($cargoToml, $originalCargoToml)
            if ($null -ne $originalPubspecLock) {
                [System.IO.File]::WriteAllBytes($pubspecLock, $originalPubspecLock)
            }
        }

        $builtExe = Join-Path $ViewerSource 'flutter\build\windows\x64\runner\Release\rustdesk.exe'
        if (-not (Test-Path -LiteralPath $builtExe)) {
            throw "Expected Viewer artifact is missing: $builtExe"
        }

        $packageRoot = Join-Path $artifactRoot 'EzbaseViewerViewer'
        $packageZip = Join-Path $artifactRoot 'EzbaseViewerViewer-win-x64.zip'
        $resolvedArtifactRoot = [System.IO.Path]::GetFullPath($artifactRoot)
        $resolvedPackageRoot = [System.IO.Path]::GetFullPath($packageRoot)
        if (-not $resolvedPackageRoot.StartsWith(
                $resolvedArtifactRoot,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to replace unexpected package path: $resolvedPackageRoot"
        }

        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
        if (Test-Path -LiteralPath $packageRoot) {
            Remove-Item -LiteralPath $packageRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $packageZip) {
            Remove-Item -LiteralPath $packageZip -Force
        }
        New-Item -ItemType Directory -Path $packageRoot | Out-Null
        Copy-Item -Path (Join-Path (Split-Path -Parent $builtExe) '*') `
            -Destination $packageRoot -Recurse -Force

        $viewerExe = Join-Path $packageRoot 'rustdesk.exe'
        $file = Get-Item -LiteralPath $viewerExe
        $signature = Get-AuthenticodeSignature -LiteralPath $viewerExe
        $version = $file.VersionInfo
        $manifest = [ordered]@{
            Name = 'EzbaseViewer Viewer'
            SourceCommit = (& git -C $ViewerSource rev-parse HEAD).Trim()
            BuiltAtUtc = [DateTime]::UtcNow.ToString('o')
            Executable = 'rustdesk.exe'
            ExecutableBytes = $file.Length
            ExecutableSHA256 = (Get-FileHash -LiteralPath $viewerExe -Algorithm SHA256).Hash
            SignatureStatus = $signature.Status.ToString()
            ProductName = $version.ProductName
            FileDescription = $version.FileDescription
            CompanyName = $version.CompanyName
            ProductVersion = $version.ProductVersion
        }
        $manifest | ConvertTo-Json | Set-Content `
            -LiteralPath (Join-Path $packageRoot 'build-manifest.json') `
            -Encoding UTF8
        Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $packageZip
        $zip = Get-Item -LiteralPath $packageZip
        [pscustomobject]@{
            Name = $manifest.Name
            SourceCommit = $manifest.SourceCommit
            PackagePath = $packageRoot
            PackageFileCount = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File).Count
            ArchivePath = $zip.FullName
            ArchiveBytes = $zip.Length
            ArchiveSHA256 = (Get-FileHash -LiteralPath $packageZip -Algorithm SHA256).Hash
            ExecutableSHA256 = $manifest.ExecutableSHA256
            SignatureStatus = $manifest.SignatureStatus
            ProductName = $manifest.ProductName
            CompanyName = $manifest.CompanyName
        } | Format-List
    } finally {
        Pop-Location
    }
} finally {
    Set-Location $projectRoot
    Remove-Item Env:RUSTUP_TOOLCHAIN -ErrorAction SilentlyContinue
    if ($mounted) {
        Invoke-External 'subst.exe' @("$driveName`:", '/D')
    }
}
