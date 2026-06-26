[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [string]$Xsct = "/opt/Xilinx/SDK/2018.3/bin/xsct",
    [string]$Hdf = "build\eth-ps-pl-hdmi-pass-through\vdma-board\reports\eth_ps_vdma_hdmi_stage1_board.hdf"
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
$buildRoot = Join-Path $repoRoot "build\eth-ps-pl-hdmi-pass-through\software"
$reportRoot = Join-Path $buildRoot "reports"
$tcl = Join-Path $PSScriptRoot "build_sdk_app.tcl"

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$wslRepoRoot = Convert-ToWslPath $repoRoot
$wslBuildRoot = Convert-ToWslPath $buildRoot
$wslTcl = Convert-ToWslPath $tcl
$hdfPath = if ([System.IO.Path]::IsPathRooted($Hdf)) {
    $Hdf
} else {
    Join-Path $repoRoot $Hdf
}
if (!(Test-Path $hdfPath)) {
    throw "Stage1 HDF not found: $hdfPath"
}
$wslHdf = Convert-ToWslPath $hdfPath
$consoleLog = Join-Path $reportRoot "sdk_app_console.log"
$stdoutLog = Join-Path $reportRoot "sdk_app_stdout.log"
$stderrLog = Join-Path $reportRoot "sdk_app_stderr.log"

$xsctArgs = @(
    "-d", $Distro,
    "--", $Xsct,
    $wslTcl,
    $wslRepoRoot,
    $wslBuildRoot,
    $wslHdf
)

$xsctProcess = Start-Process -FilePath "wsl.exe" -ArgumentList $xsctArgs `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog
$xsctExitCode = $xsctProcess.ExitCode

Get-Content -Path $stdoutLog, $stderrLog -ErrorAction SilentlyContinue |
    Tee-Object -FilePath $consoleLog

if ($xsctExitCode -ne 0) {
    throw "WSL XSCT SDK app build failed with exit code $xsctExitCode."
}

$elf = Join-Path $buildRoot "eth_pass_through.elf"
if (!(Test-Path $elf)) {
    throw "Expected SDK ELF was not produced: $elf"
}

Write-Output "STAGE1_SDK_APP_BUILD_OK elf=$elf"
