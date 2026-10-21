[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:5080',
    [string]$InternalKey,
    [switch]$UseRunningServer
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverDll = Join-Path $projectRoot 'src\EzbaseViewer.Server\bin\Release\net8.0\EzbaseViewer.Server.dll'
$logDirectory = Join-Path $projectRoot 'artifacts\smoke-api'
$stdoutLog = Join-Path $logDirectory 'server.stdout.log'
$stderrLog = Join-Path $logDirectory 'server.stderr.log'

if (-not (Test-Path -LiteralPath $serverDll)) {
    throw "서버 빌드 결과가 없습니다. 먼저 Release 빌드를 실행하세요: $serverDll"
}

$testKey = if ($InternalKey) { $InternalKey } else { 'smoke-test-key-' + [guid]::NewGuid().ToString('N') }
$previousKey = $env:EZBASEVIEWER_INTERNAL_KEY
$env:EZBASEVIEWER_INTERNAL_KEY = $testKey
$serverProcess = $null

try {
    if (-not $UseRunningServer) {
        New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
        $serverProcess = Start-Process `
            -FilePath 'dotnet' `
            -ArgumentList @($serverDll, '--urls', $BaseUrl) `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutLog `
            -RedirectStandardError $stderrLog `
            -PassThru
    }

    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $health = Invoke-RestMethod -Method Get -Uri "$BaseUrl/health" -TimeoutSec 1
            if ($health.status -eq 'ok') {
                $ready = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 200
        }
    }

    if (-not $ready) {
        $exitDetail = if ($serverProcess -and $serverProcess.HasExited) { " exit=$($serverProcess.ExitCode)" } else { '' }
        $errorDetail = if (Test-Path -LiteralPath $stderrLog) { Get-Content -LiteralPath $stderrLog -Raw } else { '' }
        throw "Control server did not start in time.$exitDetail $errorDetail"
    }

    $internalHeaders = @{ 'X-Ezbase-Internal-Key' = $testKey }
    $company = @{
        companyId = 'smoke-company-a'
        displayName = 'Smoke Test Company'
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/v1/companies" `
        -Headers $internalHeaders `
        -ContentType 'application/json' `
        -Body $company | Out-Null

    $device = @{
        deviceId = 'smoke-device-a'
        companyId = 'smoke-company-a'
        displayName = 'Smoke Test PC'
        publicKey = 'smoke-public-key'
        allowUnattendedAccess = $false
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/v1/clients/enrollments" `
        -Headers $internalHeaders `
        -ContentType 'application/json' `
        -Body $device | Out-Null

    $clients = Invoke-RestMethod `
        -Method Get `
        -Uri "$BaseUrl/v1/companies/smoke-company-a/clients" `
        -Headers $internalHeaders

    if ($clients.Count -ne 1 -or $clients[0].installationMode -ne 'HostOnly') {
        throw 'Company client list did not return one HostOnly installation.'
    }

    $launchRequest = @{
        userId = 'smoke-user-a'
        organizationId = 'smoke-org-a'
        companyId = 'smoke-company-a'
        deviceId = 'smoke-device-a'
        requestedCapabilities = @('ViewScreen', 'ControlKeyboard', 'ControlMouse')
        nonce = [guid]::NewGuid().ToString('N')
    } | ConvertTo-Json

    $launch = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/v1/launch-codes" `
        -Headers $internalHeaders `
        -ContentType 'application/json' `
        -Body $launchRequest

    $exchangeRequest = @{
        code = $launch.code
        appInstanceId = [guid]::NewGuid().ToString('N')
        appVersion = '0.1.0-smoke'
    } | ConvertTo-Json

    $exchange = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/v1/launch-codes/exchange" `
        -ContentType 'application/json' `
        -Body $exchangeRequest

    $sessionRequest = @{
        deviceId = 'smoke-device-a'
        unattended = $false
        requestedCapabilities = @('ViewScreen', 'ControlKeyboard')
    } | ConvertTo-Json

    $session = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/v1/sessions" `
        -Headers @{ Authorization = 'Bearer ' + $exchange.appToken } `
        -ContentType 'application/json' `
        -Body $sessionRequest

    if ($session.state -ne 'PendingApproval') {
        throw "승인형 세션의 상태가 잘못되었습니다: $($session.state)"
    }

    $reuseRejected = $false
    try {
        Invoke-RestMethod `
            -Method Post `
            -Uri "$BaseUrl/v1/launch-codes/exchange" `
            -ContentType 'application/json' `
            -Body $exchangeRequest | Out-Null
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 400) {
            $reuseRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $reuseRejected) {
        throw '사용한 실행 코드가 다시 허용되었습니다.'
    }

    $auditEvents = Invoke-RestMethod `
        -Method Get `
        -Uri "$BaseUrl/v1/audit-events" `
        -Headers $internalHeaders

    if ($auditEvents.Count -lt 4) {
        throw "감사 이벤트 수가 부족합니다: $($auditEvents.Count)"
    }

    Write-Output 'PASS health'
    Write-Output 'PASS company creation'
    Write-Output 'PASS HostOnly client enrollment and company list'
    Write-Output 'PASS one-time launch code exchange'
    Write-Output 'PASS approved-capability session request'
    Write-Output 'PASS launch code reuse rejection'
    Write-Output 'PASS audit event collection'
}
finally {
    if ($serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -Force
        $serverProcess.WaitForExit()
    }

    $env:EZBASEVIEWER_INTERNAL_KEY = $previousKey
}
