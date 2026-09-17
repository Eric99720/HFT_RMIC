$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "vivado_common.ps1")

Push-Location $Root
try {
    Write-Host "[HFT_RMIC] Verifying pinned dependencies before I4 R01 parity simulation..."
    python -B scripts/check_dependency_contracts.py
    if ($LASTEXITCODE -ne 0) { throw "dependency contract check failed" }

    $xvlog = Resolve-VivadoTool "xvlog"
    $xelab = Resolve-VivadoTool "xelab"
    $xsim  = Resolve-VivadoTool "xsim"
    Show-VivadoTool "xvlog" $xvlog
    Show-VivadoTool "xelab" $xelab
    Show-VivadoTool "xsim"  $xsim

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $RunDir = Join-Path $Root ("build\runs\i4-r01-parity-xsim-{0}" -f $stamp)
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

    $inc = @(
        (Join-Path $Root "rtl\include"),
        (Join-Path $Root "deps\RMIC\rtl"),
        (Join-Path $Root "deps\hft-full-system-fpga\rtl\common\include")
    )

    $sources = @(
        (Join-Path $Root "deps\RMIC\rtl\amu_bank_ram.sv"),
        (Join-Path $Root "deps\RMIC\rtl\amu_banked_double_hash_v2.sv"),
        (Join-Path $Root "rtl\adapters\configurable_exact_map.sv"),
        (Join-Path $Root "rtl\adapters\hft_order_to_rmic.sv"),
        (Join-Path $Root "rtl\policy\hft_rmic_policy_gate.sv"),
        (Join-Path $Root "rtl\accounting\hft_rmic_futures_transition_v1.sv"),
        (Join-Path $Root "rtl\accounting\hft_rmic_state_ram.sv"),
        (Join-Path $Root "rtl\accounting\hft_rmic_futures_state_manager_v1.sv"),
        (Join-Path $Root "rtl\integration\hft_rmic_futures_order_store_v1.sv"),
        (Join-Path $Root "rtl\integration\hft_rmic_cl2ex_admission_v1.sv"),
        (Join-Path $Root "rtl\integration\hft_rmic_order_gate_v1.sv"),
        (Join-Path $Root "rtl\integration\hft_rmic_committed_execution_bridge_v1.sv"),
        (Join-Path $Root "rtl\integration\hft_rmic_shared_core_v1.sv"),
        (Join-Path $Root "rtl\integration\hft_rmic_dual_order_source_v1.sv"),
        (Join-Path $Root "deps\hft-full-system-fpga\rtl\encoder\payload\order_arbiter.v"),
        (Join-Path $Root "deps\hft-full-system-fpga\rtl\encoder\payload\order_request_fifo.v"),
        (Join-Path $Root "deps\hft-full-system-fpga\rtl\encoder\tmp\tmp_r01_fast_stream_encoder.v"),
        (Join-Path $Root "deps\hft-full-system-fpga\rtl\encoder\tmp\tmp_r05_fast_stream_encoder.v"),
        (Join-Path $Root "deps\hft-full-system-fpga\rtl\encoder\session\financial_protocol_encoder.v"),
        (Join-Path $Root "rtl\integration\hft_rmic_r01_path_v1.sv"),
        (Join-Path $Root "tb\tb_hft_rmic_i4_r01_byte_parity.sv")
    )

    foreach ($f in $sources) {
        if (-not (Test-Path $f)) { throw "required I4 parity source missing: $f" }
    }

    $includeArgs = @()
    foreach ($d in $inc) { $includeArgs += @("-i", $d) }

    $failureMessage = $null
    Push-Location $RunDir
    try {
        try {
            Write-Host "[HFT_RMIC] Compiling I4 frozen R01 parity simulation..."
            & $xvlog -sv -d AMU_BEHAVIORAL_RAM @includeArgs @sources 2>&1 | Tee-Object -FilePath "xvlog.log"
            if ($LASTEXITCODE -ne 0) { throw "xvlog failed with exit code $LASTEXITCODE" }

            & $xelab tb_hft_rmic_i4_r01_byte_parity -s hft_rmic_i4_r01_parity_sim --debug typical 2>&1 | Tee-Object -FilePath "xelab.log"
            if ($LASTEXITCODE -ne 0) { throw "xelab failed with exit code $LASTEXITCODE" }

            & $xsim hft_rmic_i4_r01_parity_sim -runall 2>&1 | Tee-Object -FilePath "xsim.log"
            if ($LASTEXITCODE -ne 0) { throw "xsim failed with exit code $LASTEXITCODE" }

            $simLog = Get-Content "xsim.log" -Raw
            if ($simLog -notmatch "I4_R01_BYTE_PARITY_PASS label=legacy bytes=80") {
                throw "legacy frozen-R01 80-byte parity marker missing"
            }
            if ($simLog -notmatch "I4_R01_BYTE_PARITY_PASS label=prebuild bytes=80") {
                throw "prebuild frozen-R01 80-byte parity marker missing"
            }
            if ($simLog -notmatch "I4_R01_REJECT_NO_PACKET_PASS") {
                throw "risk-reject no-packet marker missing"
            }
            if ($simLog -notmatch "HFT_RMIC_I4_R01_BYTE_PARITY_TB_PASS") {
                throw "I4 R01 parity final PASS marker missing"
            }
            Write-Host "[HFT_RMIC] HFT_RMIC_I4_R01_BYTE_PARITY_TB_PASS"
        }
        catch {
            $failureMessage = $_.Exception.Message
        }
    }
    finally {
        Pop-Location
    }

    try {
        & (Join-Path $PSScriptRoot "package_results.ps1") -RunDir $RunDir -Kind "i4_r01_parity_xsim"
    }
    catch {
        Write-Warning "Could not package I4 R01 parity results: $($_.Exception.Message)"
    }

    if ($failureMessage) {
        throw "I4 R01 parity simulation failed: $failureMessage. Upload the newest build\packages\HFT_RMIC_i4_r01_parity_xsim_*.zip for diagnosis."
    }

    Write-Host "[HFT_RMIC] I4 frozen R01 byte parity completed successfully."
    Write-Host "[HFT_RMIC] Upload the newest build\packages\HFT_RMIC_i4_r01_parity_xsim_*.zip"
}
finally {
    Pop-Location
}
