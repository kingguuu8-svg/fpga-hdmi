[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [string]$Vivado = "/opt/Xilinx/Vivado/2018.3/bin/vivado",
    [string]$Example = "video-pip"
)

$ErrorActionPreference = "Stop"

function Convert-ToWslPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full -notmatch "^([A-Za-z]):\\(.*)$") {
        throw "Cannot convert non-drive path to WSL path: $full"
    }
    $drive = $matches[1].ToLowerInvariant()
    $rest = $matches[2] -replace "\\", "/"
    return "/mnt/$drive/$rest"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$tcl = Join-Path $PSScriptRoot "sim.tcl"
$simRoot = Join-Path $repoRoot "build\$Example\sim"
New-Item -ItemType Directory -Force -Path $simRoot | Out-Null

$wslRepoRoot = Convert-ToWslPath $repoRoot
$wslTcl = Convert-ToWslPath $tcl
$wslSimRoot = Convert-ToWslPath $simRoot

& wsl.exe -d $Distro -- $Vivado -mode batch -nojournal -nolog `
    -source $wslTcl -tclargs $wslRepoRoot $Example $wslSimRoot
if ($LASTEXITCODE -ne 0) {
    throw "WSL Vivado simulation failed with exit code $LASTEXITCODE."
}

Write-Output "SIM_OK example=$Example sim_root=$simRoot"
