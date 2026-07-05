[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [string]$OutDir = "build/jpegpl-dma-probe-kernel-client"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$repoWsl = "/mnt/" + $repoRoot.Substring(0, 1).ToLowerInvariant() + $repoRoot.Substring(2).Replace("\", "/")
$outWsl = if ([System.IO.Path]::IsPathRooted($OutDir)) {
    "/mnt/" + $OutDir.Substring(0, 1).ToLowerInvariant() + $OutDir.Substring(2).Replace("\", "/")
} else {
    "$repoWsl/" + $OutDir.Replace("\", "/")
}

& rtk wsl -d $Distro -- bash "$repoWsl/software/kernel/jpegpl_dma_probe/build.sh" "$outWsl"
if ($LASTEXITCODE -ne 0) {
    throw "jpegpl DMA probe client build failed with exit code $LASTEXITCODE"
}
