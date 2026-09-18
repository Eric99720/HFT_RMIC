$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "vivado_common.ps1")

Push-Location $Root
try {
    Write-Host "[HFT_RMIC] Verifying pinned dependencies before I5 U50 OOC..."
    python -B scripts/check_dependency_contracts.py
    if ($LASTEXITCODE -ne 0) { throw "dependency contract check failed" }
    python -B scripts/check_i5_derived_contracts.py
    if ($LASTEXITCODE -ne 0) { throw "I5 derived hierarchy check failed" }
    python -B scripts/check_vivado_2022_tcl.py
    if ($LASTEXITCODE -ne 0) { throw "Vivado/Tcl compatibility check failed" }

    $vivado = Resolve-VivadoTool "vivado"
    Show-VivadoTool "vivado" $vivado
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $RunDir = Join-Path $Root ("build\runs\i5-dual-xgmii-ooc-{0}" -f $stamp)
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $oldOutDir = $env:HFT_RMIC_OUT_DIR
    $env:HFT_RMIC_OUT_DIR = $RunDir
    $log = Join-Path $RunDir "vivado_i5_dual_xgmii_ooc.log"
    $jou = Join-Path $RunDir "vivado_i5_dual_xgmii_ooc.jou"
    try {
        Write-Host "[HFT_RMIC] I5 real-XPM dual-XGMII U50 OOC implementation"
        Write-Host "[HFT_RMIC] run_dir = $RunDir"
        & $vivado -mode batch -log $log -journal $jou -source (Join-Path $Root "vivado\i5_dual_xgmii_full_system_ooc.tcl")
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $oldOutDir) { Remove-Item Env:HFT_RMIC_OUT_DIR -ErrorAction SilentlyContinue }
        else { $env:HFT_RMIC_OUT_DIR = $oldOutDir }
    }

    try { & (Join-Path $PSScriptRoot "package_results.ps1") -RunDir $RunDir -Kind "i5_dual_xgmii_full_system_ooc" }
    catch { Write-Warning "Could not package I5 OOC results: $($_.Exception.Message)" }

    if ($exitCode -ne 0) {
        throw "I5 dual-XGMII OOC failed with exit code $exitCode. Upload the newest build\packages\HFT_RMIC_i5_dual_xgmii_full_system_ooc_*.zip."
    }
    Write-Host "[HFT_RMIC] I5 full-system OOC completed successfully."
    Write-Host "[HFT_RMIC] Upload the newest build\packages\HFT_RMIC_i5_dual_xgmii_full_system_ooc_*.zip"
}
finally { Pop-Location }
