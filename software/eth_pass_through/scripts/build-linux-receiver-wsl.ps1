[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [string]$OutDir = "build/ethernet-video-userspace-receiver"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$repoWsl = "/mnt/" + $repoRoot.Substring(0, 1).ToLowerInvariant() + $repoRoot.Substring(2).Replace("\", "/")
$outWsl = if ([System.IO.Path]::IsPathRooted($OutDir)) {
    "/mnt/" + $OutDir.Substring(0, 1).ToLowerInvariant() + $OutDir.Substring(2).Replace("\", "/")
} else {
    "$repoWsl/" + $OutDir.Replace("\", "/")
}

& rtk wsl -d $Distro -- bash "$repoWsl/software/eth_pass_through/linux_app/build.sh" "$outWsl"
if ($LASTEXITCODE -ne 0) {
    throw "Linux receiver build failed with exit code $LASTEXITCODE"
}
