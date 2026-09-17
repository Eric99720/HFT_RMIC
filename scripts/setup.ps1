$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

Set-Location $Root

Write-Host "[HFT_RMIC] Initializing pinned submodules..."
git submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw "git submodule update failed" }

Write-Host "[HFT_RMIC] Verifying dependency SHAs and interface contracts..."
python (Join-Path $PSScriptRoot "check_dependency_contracts.py")
if ($LASTEXITCODE -ne 0) { throw "dependency contract validation failed" }

Write-Host "[HFT_RMIC] SETUP_PASS"
