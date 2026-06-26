[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [string]$Vivado = "/opt/Xilinx/Vivado/2018.3/bin/vivado"
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
$buildRoot = Join-Path $repoRoot "build\eth-ps-pl-hdmi-pass-through\vdma-board"
$reportRoot = Join-Path $buildRoot "reports"
$tcl = Join-Path $PSScriptRoot "build_stage1_vdma_board.tcl"

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$wslRepoRoot = Convert-ToWslPath $repoRoot
$wslBuildRoot = Convert-ToWslPath $buildRoot
$wslTcl = Convert-ToWslPath $tcl
$wslVivadoLog = Convert-ToWslPath (Join-Path $reportRoot "vivado.log")
$consoleLog = Join-Path $reportRoot "stage1_vdma_board_console.log"
$stdoutLog = Join-Path $reportRoot "stage1_vdma_board_stdout.log"
$stderrLog = Join-Path $reportRoot "stage1_vdma_board_stderr.log"

$vivadoArgs = @(
    "-d", $Distro,
    "--", $Vivado,
    "-mode", "batch",
    "-nojournal",
    "-log", $wslVivadoLog,
    "-source", $wslTcl,
    "-tclargs", $wslRepoRoot, $wslBuildRoot
)

$vivadoProcess = Start-Process -FilePath "wsl.exe" -ArgumentList $vivadoArgs `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog
$vivadoExitCode = $vivadoProcess.ExitCode

Get-Content -Path $stdoutLog, $stderrLog -ErrorAction SilentlyContinue |
    Tee-Object -FilePath $consoleLog

if ($vivadoExitCode -ne 0) {
    throw "WSL Vivado stage1 VDMA board build failed with exit code $vivadoExitCode."
}

$bitstream = Join-Path $buildRoot "eth_ps_vdma_hdmi_stage1_board.bit"
if (!(Test-Path $bitstream)) {
    throw "Expected bitstream was not produced: $bitstream"
}

Write-Output "STAGE1_VDMA_BOARD_BUILD_OK bitstream=$bitstream"
