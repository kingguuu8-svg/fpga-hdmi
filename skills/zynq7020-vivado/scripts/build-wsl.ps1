[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BoardProfile,
    [string]$Distro = "Ubuntu-22.04",
    [string]$Vivado = "/opt/Xilinx/Vivado/2018.3/bin/vivado",
    [string]$Example = "led-chaser"
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
$profile = (Resolve-Path $BoardProfile).Path
$tcl = Join-Path $PSScriptRoot "build.tcl"
$buildRoot = Join-Path $repoRoot "build\$Example"

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

$wslRepoRoot = Convert-ToWslPath $repoRoot
$wslProfile = Convert-ToWslPath $profile
$wslTcl = Convert-ToWslPath $tcl
$wslBuildRoot = Convert-ToWslPath $buildRoot

& wsl.exe -d $Distro -- $Vivado -mode batch -nojournal -nolog `
    -source $wslTcl -tclargs $wslRepoRoot $wslProfile $Example $wslBuildRoot
if ($LASTEXITCODE -ne 0) {
    throw "WSL Vivado build failed with exit code $LASTEXITCODE."
}

$bitstream = Join-Path $buildRoot "$Example.bit"
if (-not (Test-Path -LiteralPath $bitstream -PathType Leaf)) {
    throw "Vivado completed without producing '$bitstream'."
}
Write-Output $bitstream
