param(
    [Parameter(Mandatory=$true)][string]$RunDir,
    [string]$Kind = "run"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$RunDir = (Resolve-Path $RunDir).Path
$PackageDir = Join-Path $Root "build\packages"
New-Item -ItemType Directory -Force -Path $PackageDir | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$manifest = Join-Path $RunDir "run_manifest.txt"
$gitCommit = (& git -C $Root rev-parse HEAD 2>$null)
$gitBranch = (& git -C $Root rev-parse --abbrev-ref HEAD 2>$null)
$gitStatus = (& git -C $Root status --short 2>$null)
$hftSha = (& git -C (Join-Path $Root "deps\hft-full-system-fpga") rev-parse HEAD 2>$null)
$rmicSha = (& git -C (Join-Path $Root "deps\RMIC") rev-parse HEAD 2>$null)

@(
    "kind=$Kind"
    "timestamp=$timestamp"
    "host=$env:COMPUTERNAME"
    "git_branch=$gitBranch"
    "git_commit=$gitCommit"
    "hft_dependency=$hftSha"
    "rmic_dependency=$rmicSha"
    "run_dir=$RunDir"
    ""
    "git_status:"
    $gitStatus
) | Set-Content -Encoding UTF8 $manifest

$includeExtensions = @('.rpt','.log','.jou','.txt','.csv','.json')
$files = Get-ChildItem -Path $RunDir -File -Recurse | Where-Object {
    $includeExtensions -contains $_.Extension.ToLowerInvariant()
}
if (-not $files) { throw "No report/log/result files found in $RunDir" }

$stage = Join-Path $RunDir "_package_stage"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($file in $files) {
    if ($file.FullName -like "$stage*") { continue }
    $rel = $file.FullName.Substring($RunDir.Length).TrimStart('\','/')
    $dest = Join-Path $stage $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
}

$zip = Join-Path $PackageDir ("HFT_RMIC_{0}_{1}.zip" -f $Kind,$timestamp)
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
Remove-Item -Recurse -Force $stage

Write-Host "[HFT_RMIC] Result package created: $zip"
Write-Host "[HFT_RMIC] Upload this single ZIP for analysis."
