[CmdletBinding()]
param(
    [string]$ServerSource = (Join-Path (Split-Path -Parent $PSScriptRoot) 'work\rustdesk-server-1.1.16'),
    [ValidateRange(1025, 65530)]
    [int]$RendezvousPort = 22116,
    [string]$RuntimeDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'work\poc-runtime\server-local')
)

$ErrorActionPreference = 'Stop'
$hbbs = Join-Path $ServerSource 'target\release\hbbs.exe'
$hbbr = Join-Path $ServerSource 'target\release\hbbr.exe'
$relayPort = $RendezvousPort + 1
$expectedTcpPorts = @(
    ($RendezvousPort - 1),
    $RendezvousPort,
    $relayPort,
    ($RendezvousPort + 2),
    ($relayPort + 2)
)

foreach ($binary in @($hbbs, $hbbr)) {
    if (-not (Test-Path -LiteralPath $binary)) {
        throw "RustDesk Server Release binary is missing: $binary"
    }
}

$occupiedTcp = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in $expectedTcpPorts })
$occupiedUdp = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -eq $RendezvousPort })
if ($occupiedTcp.Count -gt 0 -or $occupiedUdp.Count -gt 0) {
    throw "A required local PoC port is already in use: $($expectedTcpPorts -join ', ') (TCP), $RendezvousPort (UDP)."
}

New-Item -ItemType Directory -Force -Path $RuntimeDirectory | Out-Null
$runtime = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
$hbbsOut = Join-Path $runtime 'hbbs.stdout.log'
$hbbsErr = Join-Path $runtime 'hbbs.stderr.log'
$hbbrOut = Join-Path $runtime 'hbbr.stdout.log'
$hbbrErr = Join-Path $runtime 'hbbr.stderr.log'
$hbbsProcess = $null
$hbbrProcess = $null

try {
    $hbbrProcess = Start-Process `
        -FilePath $hbbr `
        -ArgumentList @('-p', $relayPort) `
        -WorkingDirectory $runtime `
        -WindowStyle Hidden `
        -RedirectStandardOutput $hbbrOut `
        -RedirectStandardError $hbbrErr `
        -PassThru

    $hbbsProcess = Start-Process `
        -FilePath $hbbs `
        -ArgumentList @('-p', $RendezvousPort, '-r', "127.0.0.1:$relayPort") `
        -WorkingDirectory $runtime `
        -WindowStyle Hidden `
        -RedirectStandardOutput $hbbsOut `
        -RedirectStandardError $hbbsErr `
        -PassThru

    Start-Sleep -Seconds 5
    $hbbsProcess.Refresh()
    $hbbrProcess.Refresh()
    if ($hbbsProcess.HasExited -or $hbbrProcess.HasExited) {
        $hbbsError = if (Test-Path -LiteralPath $hbbsErr) { Get-Content -LiteralPath $hbbsErr -Raw } else { '' }
        $hbbrError = if (Test-Path -LiteralPath $hbbrErr) { Get-Content -LiteralPath $hbbrErr -Raw } else { '' }
        throw "RustDesk Server stopped during startup. hbbs=[$hbbsError] hbbr=[$hbbrError]"
    }

    $processIds = @($hbbsProcess.Id, $hbbrProcess.Id)
    $tcpPorts = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.OwningProcess -in $processIds } |
        Select-Object -ExpandProperty LocalPort -Unique)
    $udpPorts = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
        Where-Object { $_.OwningProcess -in $processIds } |
        Select-Object -ExpandProperty LocalPort -Unique)
    $missingTcp = @($expectedTcpPorts | Where-Object { $_ -notin $tcpPorts })
    if ($missingTcp.Count -gt 0) {
        throw "RustDesk Server did not open expected TCP ports: $($missingTcp -join ', ')"
    }
    if ($RendezvousPort -notin $udpPorts) {
        throw "hbbs did not open expected UDP port: $RendezvousPort"
    }

    $privateKey = Join-Path $runtime 'id_ed25519'
    $publicKey = Join-Path $runtime 'id_ed25519.pub'
    if (-not (Test-Path -LiteralPath $privateKey) -or -not (Test-Path -LiteralPath $publicKey)) {
        throw 'hbbs did not create the Ed25519 key pair.'
    }

    Write-Output 'PASS hbbs and hbbr stayed running during the startup probe.'
    Write-Output "PASS TCP listeners: $($expectedTcpPorts -join ', ')"
    Write-Output "PASS UDP rendezvous endpoint: $RendezvousPort"
    Write-Output 'PASS Ed25519 key pair created in the ignored work directory.'
}
finally {
    foreach ($process in @($hbbsProcess, $hbbrProcess)) {
        if ($process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit()
        }
    }
}
