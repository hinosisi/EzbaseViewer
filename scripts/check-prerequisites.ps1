[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$requirements = @(
    @{ Name = 'git'; Required = $true },
    @{ Name = 'dotnet'; Required = $true },
    @{ Name = 'node'; Required = $true },
    @{ Name = 'npm'; Required = $true },
    @{ Name = 'rea'; Required = $false },
    @{ Name = 'docker'; Required = $false }
)

$failed = $false
foreach ($requirement in $requirements) {
    $command = Get-Command $requirement.Name -ErrorAction SilentlyContinue
    $state = if ($command) { 'FOUND' } elseif ($requirement.Required) { 'MISSING_REQUIRED' } else { 'MISSING_OPTIONAL' }
    [pscustomobject]@{
        Name = $requirement.Name
        State = $state
        Path = if ($command) { $command.Source } else { $null }
    }

    if (-not $command -and $requirement.Required) {
        $failed = $true
    }
}

if ($failed) {
    exit 1
}
