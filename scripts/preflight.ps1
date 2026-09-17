param(
    [switch]$SkipFunctional
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root
try {
    Write-Host '[HFT_RMIC] Verifying pinned dependencies...'
    python -B scripts/check_dependency_contracts.py
    if ($LASTEXITCODE -ne 0) { throw 'dependency contract check failed' }

    Write-Host '[HFT_RMIC] Verifying project records...'
    python -B scripts/sync_project_records.py --check
    if ($LASTEXITCODE -ne 0) { throw 'project record sync check failed' }

    Write-Host '[HFT_RMIC] Verifying repository layout...'
    python -B scripts/check_repository_layout.py
    if ($LASTEXITCODE -ne 0) { throw 'repository layout check failed' }

    if (-not $SkipFunctional) {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if ($null -eq $bash) {
            Write-Warning 'bash not found; skipping Icarus regression. Use GitHub CI or Git Bash/WSL.'
        } else {
            Write-Host '[HFT_RMIC] Running adapter/policy/execution-tap regression...'
            & $bash.Source scripts/run_adapter_iverilog.sh
            if ($LASTEXITCODE -ne 0) { throw 'adapter regression failed' }

            Write-Host '[HFT_RMIC] Running futures accounting regression...'
            & $bash.Source scripts/run_accounting_iverilog.sh
            if ($LASTEXITCODE -ne 0) { throw 'accounting regression failed' }
        }
    }

    git diff --check
    if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed' }

    Write-Host 'HFT_RMIC_PREFLIGHT_PASS'
}
finally {
    Pop-Location
}
