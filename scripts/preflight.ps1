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

    Write-Host '[HFT_RMIC] Verifying Vivado 2022.1 Tcl compatibility...'
    python -B scripts/check_vivado_2022_tcl.py
    if ($LASTEXITCODE -ne 0) { throw 'Vivado 2022.1 Tcl compatibility check failed' }

    if (-not $SkipFunctional) {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if ($null -eq $bash) {
            Write-Warning 'bash not found; skipping local Icarus regressions. Exact-head GitHub CI remains the required functional gate on hosts without Git Bash/WSL.'
        } else {
            Write-Host '[HFT_RMIC] Running adapter/policy/execution-meta regression...'
            & $bash.Source scripts/run_adapter_iverilog.sh
            if ($LASTEXITCODE -ne 0) { throw 'adapter regression failed' }

            Write-Host '[HFT_RMIC] Running futures accounting regression...'
            & $bash.Source scripts/run_accounting_iverilog.sh
            if ($LASTEXITCODE -ne 0) { throw 'accounting regression failed' }

            Write-Host '[HFT_RMIC] Running multi-account futures state-manager regression...'
            & $bash.Source scripts/run_state_manager_iverilog.sh
            if ($LASTEXITCODE -ne 0) { throw 'state-manager regression failed' }

            Write-Host '[HFT_RMIC] Running futures order-context regression...'
            & $bash.Source scripts/run_order_context_iverilog.sh
            if ($LASTEXITCODE -ne 0) { throw 'order-context regression failed' }

            Write-Host '[HFT_RMIC] Running committed execution reconciliation regression...'
            & $bash.Source scripts/run_execution_bridge_iverilog.sh
            if ($LASTEXITCODE -ne 0) { throw 'execution reconciliation regression failed' }

            Write-Host '[HFT_RMIC] Running I3 atomic CL2EX admission regression...'
            & $bash.Source scripts/run_cl2ex_admission_iverilog.sh
            if ($LASTEXITCODE -ne 0) { throw 'I3 atomic CL2EX admission regression failed' }

            Write-Host '[HFT_RMIC] Running I3 frozen-HFT order-gate regression...'
            & $bash.Source scripts/run_order_gate_iverilog.sh
            if ($LASTEXITCODE -ne 0) { throw 'I3 order-gate regression failed' }

            Write-Host '[HFT_RMIC] Compiling I2 OOC composition harness...'
            & $bash.Source scripts/run_i2_ooc_compile_iverilog.sh
            if ($LASTEXITCODE -ne 0) { throw 'I2 OOC composition compile failed' }

            Write-Host '[HFT_RMIC] Compiling I3 atomic CL2EX OOC composition harness...'
            & $bash.Source scripts/run_i3_cl2ex_ooc_compile_iverilog.sh
            if ($LASTEXITCODE -ne 0) { throw 'I3 CL2EX OOC composition compile failed' }
        }
    }

    git diff --check
    if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed' }

    Write-Host 'HFT_RMIC_PREFLIGHT_PASS'
}
finally {
    Pop-Location
}
