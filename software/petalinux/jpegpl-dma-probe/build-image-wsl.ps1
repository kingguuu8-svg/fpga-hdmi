[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [string]$Chroot = "/opt/chroots/ubuntu18-petalinux2018",
    [string]$Project = "/home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic",
    [string]$HwDescription = "build/eth-ps-pl-hdmi-pass-through/vdma-board/reports",
    [string]$OutDir = "build/jpegpl-dma-probe-runtime-image"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$repoWsl = "/mnt/" + $repoRoot.Substring(0, 1).ToLowerInvariant() + $repoRoot.Substring(2).Replace("\", "/")
$hwPath = if ([System.IO.Path]::IsPathRooted($HwDescription)) {
    "/mnt/" + $HwDescription.Substring(0, 1).ToLowerInvariant() + $HwDescription.Substring(2).Replace("\", "/")
} else {
    "$repoWsl/" + $HwDescription.Replace("\", "/")
}
$outWsl = if ([System.IO.Path]::IsPathRooted($OutDir)) {
    "/mnt/" + $OutDir.Substring(0, 1).ToLowerInvariant() + $OutDir.Substring(2).Replace("\", "/")
} else {
    "$repoWsl/" + $OutDir.Replace("\", "/")
}

& rtk wsl -d $Distro -u root -- bash "$repoWsl/software/petalinux/hdmi-linux-display-stack/run-command-in-chroot.sh" `
    $Chroot $Project petalinux-config --get-hw-description $hwPath --oldconfig
if ($LASTEXITCODE -ne 0) {
    throw "petalinux-config HDF import failed with exit code $LASTEXITCODE"
}

& rtk wsl -d $Distro -- bash "$repoWsl/software/petalinux/hdmi-linux-display-stack/apply-overlay.sh" $Project
if ($LASTEXITCODE -ne 0) {
    throw "HDMI display stack overlay failed with exit code $LASTEXITCODE"
}

& rtk wsl -d $Distro -- bash "$repoWsl/software/petalinux/jpegpl-dma-probe/apply-overlay.sh" $Project
if ($LASTEXITCODE -ne 0) {
    throw "jpegpl DMA probe overlay failed with exit code $LASTEXITCODE"
}

& rtk wsl -d $Distro -u root -- bash "$repoWsl/software/petalinux/hdmi-linux-display-stack/build-in-chroot.sh" `
    $Chroot $Project $outWsl
if ($LASTEXITCODE -ne 0) {
    throw "PetaLinux build failed with exit code $LASTEXITCODE"
}

& rtk wsl -d $Distro -- bash -lc "mkdir -p '$outWsl' && cp '$Project/images/linux/image.ub' '$outWsl/image.ub' && sha256sum '$outWsl/image.ub' | tee '$outWsl/image.ub.sha256.txt'"
if ($LASTEXITCODE -ne 0) {
    throw "image.ub copy/hash failed with exit code $LASTEXITCODE"
}

Write-Output "JPEGPL_DMA_PROBE_IMAGE_BUILD_OK out=$OutDir"
