[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [string]$Chroot = "/opt/chroots/ubuntu18-petalinux2018",
    [string]$Project = "/home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic",
    [string]$Bitstream = "build\eth-ps-pl-hdmi-pass-through\vdma-board\eth_ps_vdma_hdmi_stage1_board.bit",
    [string]$OutDir = "build\jpegpl-dma-probe-boot",
    [string]$ExpectedBitstreamSha256 = "",
    [string]$ExpectedImageUbSha256 = "",
    [switch]$ReuseExistingImageUb
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

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
        } finally {
            $sha.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$bitPath = if ([System.IO.Path]::IsPathRooted($Bitstream)) {
    [System.IO.Path]::GetFullPath($Bitstream)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Bitstream))
}
$outputPath = if ([System.IO.Path]::IsPathRooted($OutDir)) {
    [System.IO.Path]::GetFullPath($OutDir)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutDir))
}

if (!(Test-Path $bitPath)) {
    throw "Bitstream is missing: $bitPath"
}
if (!$ReuseExistingImageUb) {
    throw "This boot-only path reuses image.ub. Pass -ReuseExistingImageUb after confirming the PL/DT topology is unchanged."
}
if ($ExpectedBitstreamSha256 -notmatch "^[0-9a-fA-F]{64}$" -or
    $ExpectedImageUbSha256 -notmatch "^[0-9a-fA-F]{64}$") {
    throw "ExpectedBitstreamSha256 and ExpectedImageUbSha256 must be full SHA-256 values."
}
$bitstreamSha256 = Get-Sha256 $bitPath
if ($bitstreamSha256 -ne $ExpectedBitstreamSha256.ToLowerInvariant()) {
    throw "Bitstream SHA-256 mismatch: actual=$bitstreamSha256 expected=$ExpectedBitstreamSha256"
}
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

$repoWsl = Convert-ToWslPath $repoRoot
$bitWsl = Convert-ToWslPath $bitPath
$outputWsl = Convert-ToWslPath $outputPath
$runner = "$repoWsl/software/petalinux/hdmi-linux-display-stack/run-command-in-chroot.sh"

& wsl.exe -d $Distro -u root -- bash $runner $Chroot $Project `
    petalinux-package --boot `
    --fsbl images/linux/zynq_fsbl.elf `
    --fpga $bitWsl `
    --u-boot images/linux/u-boot.elf `
    --force `
    -o "$outputWsl/BOOT.BIN"
if ($LASTEXITCODE -ne 0) {
    throw "PetaLinux BOOT.BIN package failed with exit code $LASTEXITCODE"
}

& wsl.exe -d $Distro -- cp "$Project/images/linux/image.ub" "$outputWsl/image.ub"
if ($LASTEXITCODE -ne 0) {
    throw "Existing image.ub copy failed with exit code $LASTEXITCODE"
}

$imageUbPath = Join-Path $outputPath "image.ub"
$imageUbSha256 = Get-Sha256 $imageUbPath
if ($imageUbSha256 -ne $ExpectedImageUbSha256.ToLowerInvariant()) {
    throw "image.ub SHA-256 mismatch: actual=$imageUbSha256 expected=$ExpectedImageUbSha256"
}
$bootSha256 = Get-Sha256 (Join-Path $outputPath "BOOT.BIN")

Write-Output "JPEGPL_BOOT_ONLY_PACKAGE_OK out=$outputPath boot_sha256=$bootSha256 bitstream_sha256=$bitstreamSha256 image_ub_sha256=$imageUbSha256"
