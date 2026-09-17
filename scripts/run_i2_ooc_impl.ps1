$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "vivado_common.ps1")

Push-Location $Root
try {
    Write-Host "[HFT_RMIC] Verifying pinned dependency contracts before Vivado..."
    python -B scripts/check_dependency_contracts.py
    if ($LASTEXITCODE -ne 0) { throw "dependency contract check failed" }

    $vivado = Resolve-VivadoTool "vivado"
    Show-VivadoTool "vivado" $vivado

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $RunDir = Join-Path $Root ("build\runs\i2-ooc-impl-{0}" -f $stamp)
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

    $oldOutDir = $env:HFT_RMIC_OUT_DIR
    $env:HFT_RMIC_OUT_DIR = $RunDir
    $vivadoLog = Join-Path $RunDir "vivado_i2_ooc_impl.log"
    $vivadoJou = Join-Path $RunDir "vivado_i2_ooc_impl.jou"

    try {
        Write-Host "[HFT_RMIC] I2 futures-state + committed-execution OOC implementation"
        Write-Host "[HFT_RMIC] run_dir = $RunDir"
        & $vivado -mode batch -log $vivadoLog -journal $vivadoJou -source (Join-Path $Root "vivado\i2_ooc_impl.tcl")
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $oldOutDir) { Remove-Item Env:HFT_RMIC_OUT_DIR -ErrorAction SilentlyContinue }
        else { $env:HFT_RMIC_OUT_DIR = $oldOutDir }
    }

    try {
        & (Join-Path $PSScriptRoot "package_results.ps1") -RunDir $RunDir -Kind "i2_ooc_impl"
    }
    catch {
        Write-Warning "Could not package I2 OOC results: $($_.Exception.Message)"
    }

    if ($exitCode -ne 0) {
        throw "I2 OOC Vivado implementation failed with exit code $exitCode. Upload the newest build\packages\HFT_RMIC_i2_ooc_impl_*.zip for diagnosis."
    }

    Write-Host "[HFT_RMIC] I2 OOC implementation completed successfully."
    Write-Host "[HFT_RMIC] Upload the newest build\packages\HFT_RMIC_i2_ooc_impl_*.zip"
}
finally {
    Pop-Location
}
