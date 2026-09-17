Set-StrictMode -Version Latest

function Get-VivadoInstallDirs {
    $dirs = @()

    if ($env:VIVADO_HOME -and (Test-Path $env:VIVADO_HOME)) {
        $dirs += (Resolve-Path $env:VIVADO_HOME).Path
    }

    $defaultRoot = "C:\Xilinx\Vivado"
    if (Test-Path $defaultRoot) {
        $versionDirs = Get-ChildItem -Path $defaultRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Property @{ Expression = {
                try { [version]$_.Name } catch { [version]"0.0" }
            }} -Descending
        foreach ($dir in $versionDirs) {
            if ($dirs -notcontains $dir.FullName) { $dirs += $dir.FullName }
        }
    }
    return $dirs
}

function Resolve-VivadoTool {
    param([Parameter(Mandatory=$true)][string]$Name)

    $fromPath = Get-Command $Name -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }

    foreach ($vivadoHome in (Get-VivadoInstallDirs)) {
        $candidates = @(
            (Join-Path $vivadoHome "bin\$Name.bat"),
            (Join-Path $vivadoHome "bin\$Name.cmd"),
            (Join-Path $vivadoHome "bin\$Name.exe"),
            (Join-Path $vivadoHome "bin\unwrapped\win64.o\$Name.exe")
        )
        foreach ($candidate in $candidates) {
            if (Test-Path $candidate) { return $candidate }
        }
    }

    $searched = (Get-VivadoInstallDirs) -join ", "
    if (-not $searched) { $searched = "C:\Xilinx\Vivado\<version>" }
    throw "$Name not found. Searched PATH and Vivado installs under: $searched. Set VIVADO_HOME if needed."
}

function Show-VivadoTool {
    param([Parameter(Mandatory=$true)][string]$Name,
          [Parameter(Mandatory=$true)][string]$Path)
    Write-Host "[HFT_RMIC] $Name = $Path"
}
