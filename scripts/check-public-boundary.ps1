[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot

try {
    $files = @(git -c core.quotepath=false ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read the Git file list.'
    }

    $violations = [System.Collections.Generic.List[string]]::new()
    $forbiddenPath = '(^|/)(private|secrets|customer-data)(/|$)|(^|/)deploy/production(/|$)'
    $forbiddenFile = '(^|/)\.env($|\.)|\.(pfx|p12|key|kdbx)$'

    foreach ($file in $files) {
        $normalized = $file.Replace('\', '/')
        if ($normalized -match $forbiddenPath -or
            ($normalized -match $forbiddenFile -and $normalized -notmatch '\.env\.example$')) {
            $violations.Add("Forbidden public path or file: $normalized")
        }
    }

    $privateKeyPattern = '-----BEGIN ' + '(?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    $secretPatterns = @(
        $privateKeyPattern,
        'gh[pousr]_[A-Za-z0-9_]{20,}',
        'AKIA[0-9A-Z]{16}',
        'AIza[0-9A-Za-z_-]{35}'
    )
    $self = 'scripts/check-public-boundary.ps1'

    foreach ($file in $files) {
        $normalized = $file.Replace('\', '/')
        if ($normalized -eq $self -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
            continue
        }

        try {
            $content = Get-Content -LiteralPath $file -Raw -ErrorAction Stop
        }
        catch {
            continue
        }

        foreach ($pattern in $secretPatterns) {
            if ($content -match $pattern) {
                $violations.Add("Potential secret pattern: $normalized")
                break
            }
        }
    }

    if ($violations.Count -gt 0) {
        $violations | ForEach-Object { Write-Error $_ }
        throw "Public boundary check failed: $($violations.Count) violation(s)"
    }

    Write-Output "PASS public boundary check ($($files.Count) files)"
}
finally {
    Pop-Location
}
