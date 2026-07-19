[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [string]$OutDir = "build\native-720p30-dmabuf-display-v1\drm-prime-probe"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repoWsl = "/mnt/" + $repoRoot.Substring(0, 1).ToLowerInvariant() + $repoRoot.Substring(2).Replace("\", "/")
$outWsl = if ([System.IO.Path]::IsPathRooted($OutDir)) {
    "/mnt/" + $OutDir.Substring(0, 1).ToLowerInvariant() + $OutDir.Substring(2).Replace("\", "/")
} else {
    "$repoWsl/$($OutDir.Replace("\", "/"))"
}

& rtk wsl -d $Distro -- bash "$repoWsl/tools/build_drm_prime_probe.sh" "$outWsl"
if ($LASTEXITCODE -ne 0) {
    throw "DRM PRIME probe build failed with exit code $LASTEXITCODE"
}
