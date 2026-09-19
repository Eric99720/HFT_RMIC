param(
    [int[]]$PhasePs = @(0, 1280, 2560, 3840, 5120)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "vivado_common.ps1")

Push-Location $Root
try {
    Write-Host "[HFT_RMIC] Verifying contracts before I5 latency phase sweep..."
    python -B scripts/check_dependency_contracts.py
    if ($LASTEXITCODE -ne 0) { throw "dependency contract check failed" }
    python -B scripts/check_i5_derived_contracts.py
    if ($LASTEXITCODE -ne 0) { throw "I5 derived hierarchy check failed" }
    python -B scripts/check_vivado_2022_tcl.py
    if ($LASTEXITCODE -ne 0) { throw "Vivado/Tcl compatibility check failed" }

    $vivado = Resolve-VivadoTool "vivado"
    Show-VivadoTool "vivado" $vivado

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $RunRoot = Join-Path $Root ("build\runs\i5-latency-sweep-{0}" -f $stamp)
    New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

    $samples = @()
    foreach ($phase in $PhasePs) {
        if ($phase -lt 0 -or $phase -ge 6400) {
            throw "Phase must be in [0, 6399] ps: $phase"
        }

        $PhaseDir = Join-Path $RunRoot ("phase-{0}" -f $phase)
        New-Item -ItemType Directory -Force -Path $PhaseDir | Out-Null
        $log = Join-Path $PhaseDir ("vivado_i5_latency_{0}.log" -f $phase)
        $jou = Join-Path $PhaseDir ("vivado_i5_latency_{0}.jou" -f $phase)

        $oldOutDir = $env:HFT_RMIC_OUT_DIR
        $env:HFT_RMIC_OUT_DIR = $PhaseDir
        try {
            Write-Host ("[HFT_RMIC] I5 latency phase {0} ps" -f $phase)
            & $vivado -mode batch -log $log -journal $jou -source (Join-Path $Root "vivado\i5_dual_xgmii_latency_xsim.tcl") -tclargs $phase
            $exitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $oldOutDir) {
                Remove-Item Env:HFT_RMIC_OUT_DIR -ErrorAction SilentlyContinue
            } else {
                $env:HFT_RMIC_OUT_DIR = $oldOutDir
            }
        }

        if ($exitCode -ne 0) {
            throw "I5 latency phase failed: $phase ps"
        }

        $simLog = Get-ChildItem -Path $PhaseDir -Filter "simulate.log" -File -Recurse |
                  Sort-Object LastWriteTime |
                  Select-Object -Last 1
        if ($null -eq $simLog) {
            throw "Missing simulate.log for phase $phase ps"
        }

        $line = Select-String -LiteralPath $simLog.FullName -Pattern '^SC5_DUAL_LATENCY_SAMPLE ' |
                Select-Object -Last 1
        if ($null -eq $line) {
            throw "Missing SC5_DUAL_LATENCY_SAMPLE for phase $phase ps"
        }

        $pattern = 'phase_ps=([0-9]+).*market_start_ns=([0-9.]+).*market_commit_ns=([0-9.]+).*cdc_final_data_ns=([0-9.]+).*cdc_commit_ns=([0-9.]+).*shadow_decision_ns=([0-9.]+).*prebuild_accept_ns=([0-9.]+).*app_first_ns=([0-9.]+).*trading_start_ns=([0-9.]+).*internal_ns=([0-9.]+).*internal_cycles=([0-9]+).*cdc_commit_delta_ns=([0-9.]+).*app_to_start_ns=([0-9.]+)'
        $m = [regex]::Match($line.Line, $pattern)
        if (-not $m.Success) {
            throw "Malformed latency sample: $($line.Line)"
        }

        $riskLine = Select-String -LiteralPath $simLog.FullName -Pattern '^I5_RISK_LATENCY_SAMPLE ' |
                    Select-Object -Last 1
        if ($null -eq $riskLine) {
            throw "Missing I5_RISK_LATENCY_SAMPLE for phase $phase ps"
        }
        $riskPattern = 'phase_ps=([0-9]+).*risk_order_fire_ns=([0-9.]+).*acct_req_ns=([0-9.]+).*store_req_ns=([0-9.]+).*acct_rsp_ns=([0-9.]+).*store_rsp_ns=([0-9.]+).*risk_accept_ns=([0-9.]+).*encoder_accept_ns=([0-9.]+).*app_first_ns=([0-9.]+).*xgmii_start_ns=([0-9.]+)'
        $rm = [regex]::Match($riskLine.Line, $riskPattern)
        if (-not $rm.Success) {
            throw "Malformed risk latency sample: $($riskLine.Line)"
        }

        $sample = [pscustomobject]@{
            PhasePs = [int]$m.Groups[1].Value
            MarketStartNs = [double]$m.Groups[2].Value
            MarketCommitNs = [double]$m.Groups[3].Value
            CdcFinalDataNs = [double]$m.Groups[4].Value
            CdcCommitNs = [double]$m.Groups[5].Value
            ShadowDecisionNs = [double]$m.Groups[6].Value
            PrebuildAcceptNs = [double]$m.Groups[7].Value
            AppFirstNs = [double]$m.Groups[8].Value
            TradingStartNs = [double]$m.Groups[9].Value
            InternalNs = [double]$m.Groups[10].Value
            InternalCycles = [int]$m.Groups[11].Value
            CdcCommitDeltaNs = [double]$m.Groups[12].Value
            AppToStartNs = [double]$m.Groups[13].Value

            MarketToShadowDecisionNs = ([double]$m.Groups[6].Value - [double]$m.Groups[2].Value)
            ShadowToAppNs = ([double]$m.Groups[8].Value - [double]$m.Groups[6].Value)
            ShadowToStartNs = ([double]$m.Groups[9].Value - [double]$m.Groups[6].Value)
            AcceptToAppNs = ([double]$m.Groups[8].Value - [double]$m.Groups[7].Value)
            AcceptToStartNs = ([double]$m.Groups[9].Value - [double]$m.Groups[7].Value)

            RiskOrderFireNs = [double]$rm.Groups[2].Value
            AcctReqNs = [double]$rm.Groups[3].Value
            StoreReqNs = [double]$rm.Groups[4].Value
            AcctRspNs = [double]$rm.Groups[5].Value
            StoreRspNs = [double]$rm.Groups[6].Value
            RiskAcceptNs = [double]$rm.Groups[7].Value
            EncoderAcceptNs = [double]$rm.Groups[8].Value
            RiskOrderToAcctReqNs = ([double]$rm.Groups[3].Value - [double]$rm.Groups[2].Value)
            RiskOrderToStoreReqNs = ([double]$rm.Groups[4].Value - [double]$rm.Groups[2].Value)
            AcctRoundTripNs = ([double]$rm.Groups[5].Value - [double]$rm.Groups[3].Value)
            StoreRoundTripNs = ([double]$rm.Groups[6].Value - [double]$rm.Groups[4].Value)
            RiskOrderToAcceptNs = ([double]$rm.Groups[7].Value - [double]$rm.Groups[2].Value)
            RiskAcceptToAppNs = ([double]$rm.Groups[9].Value - [double]$rm.Groups[7].Value)
        }
        $samples += $sample
        Write-Output $line.Line
    }

    $samples | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $RunRoot "latency_samples.csv")

    $minCycles = ($samples.InternalCycles | Measure-Object -Minimum).Minimum
    $maxCycles = ($samples.InternalCycles | Measure-Object -Maximum).Maximum
    $minNs = ($samples.InternalNs | Measure-Object -Minimum).Minimum
    $maxNs = ($samples.InternalNs | Measure-Object -Maximum).Maximum
    $jitterNs = $maxNs - $minNs
    $minShadowToApp = ($samples.ShadowToAppNs | Measure-Object -Minimum).Minimum
    $maxShadowToApp = ($samples.ShadowToAppNs | Measure-Object -Maximum).Maximum
    $minShadowToStart = ($samples.ShadowToStartNs | Measure-Object -Minimum).Minimum
    $maxShadowToStart = ($samples.ShadowToStartNs | Measure-Object -Maximum).Maximum
    $minRiskToAccept = ($samples.RiskOrderToAcceptNs | Measure-Object -Minimum).Minimum
    $maxRiskToAccept = ($samples.RiskOrderToAcceptNs | Measure-Object -Maximum).Maximum
    $acctRoundTrip = ($samples.AcctRoundTripNs | Measure-Object -Maximum).Maximum
    $storeRoundTrip = ($samples.StoreRoundTripNs | Measure-Object -Maximum).Maximum
    $maxAppStartNs = ($samples.AppToStartNs | Measure-Object -Maximum).Maximum

    $summary = "I5_LATENCY_SWEEP_SUMMARY samples={0} min_cycles={1} max_cycles={2} min_ns={3:F3} max_ns={4:F3} jitter_ns={5:F3} min_shadow_to_app_ns={6:F3} max_shadow_to_app_ns={7:F3} min_shadow_to_start_ns={8:F3} max_shadow_to_start_ns={9:F3} min_risk_order_to_accept_ns={10:F3} max_risk_order_to_accept_ns={11:F3} max_acct_roundtrip_ns={12:F3} max_store_roundtrip_ns={13:F3} max_app_to_start_ns={14:F3}" -f $samples.Count,$minCycles,$maxCycles,$minNs,$maxNs,$jitterNs,$minShadowToApp,$maxShadowToApp,$minShadowToStart,$maxShadowToStart,$minRiskToAccept,$maxRiskToAccept,$acctRoundTrip,$storeRoundTrip,$maxAppStartNs

    $summary | Tee-Object -FilePath (Join-Path $RunRoot "latency_summary.txt")
    "I5_LATENCY_PHASE_SWEEP PASS" | Tee-Object -FilePath (Join-Path $RunRoot "latency_summary.txt") -Append

    try {
        & (Join-Path $PSScriptRoot "package_results.ps1") -RunDir $RunRoot -Kind "i5_latency_phase_sweep"
    }
    catch {
        Write-Warning "Could not package I5 latency sweep results: $($_.Exception.Message)"
    }

    Write-Host "[HFT_RMIC] I5 latency phase sweep completed successfully."
    Write-Host "[HFT_RMIC] Upload the newest build\packages\HFT_RMIC_i5_latency_phase_sweep_*.zip"
}
finally {
    Pop-Location
}
