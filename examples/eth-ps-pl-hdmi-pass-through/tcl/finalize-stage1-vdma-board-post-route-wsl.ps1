[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [string]$Vivado = "/opt/Xilinx/Vivado/2018.3/bin/vivado",
    [string]$BuildDir = "build\eth-ps-pl-hdmi-pass-through\vdma-board"
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
$buildRoot = if ([System.IO.Path]::IsPathRooted($BuildDir)) {
    [System.IO.Path]::GetFullPath($BuildDir)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $BuildDir))
}
$reportRoot = Join-Path $buildRoot "reports"
$tcl = Join-Path $PSScriptRoot "finalize_stage1_vdma_board_post_route.tcl"

if (!(Test-Path (Join-Path $buildRoot "eth_ps_vdma_hdmi_stage1_board.xpr"))) {
    throw "Expected Vivado project is missing: $buildRoot"
}
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$wslBuildRoot = Convert-ToWslPath $buildRoot
$wslTcl = Convert-ToWslPath $tcl
$wslVivadoLog = Convert-ToWslPath (Join-Path $reportRoot "post_route_physopt.log")
$consoleLog = Join-Path $reportRoot "post_route_physopt_console.log"
$stdoutLog = Join-Path $reportRoot "post_route_physopt_stdout.log"
$stderrLog = Join-Path $reportRoot "post_route_physopt_stderr.log"

$vivadoArgs = @(
    "-d", $Distro,
    "--", $Vivado,
    "-mode", "batch",
    "-nojournal",
    "-log", $wslVivadoLog,
    "-source", $wslTcl,
    "-tclargs", $wslBuildRoot
)

$vivadoProcess = Start-Process -FilePath "wsl.exe" -ArgumentList $vivadoArgs `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog
$vivadoExitCode = $vivadoProcess.ExitCode

Get-Content -Path $stdoutLog, $stderrLog -ErrorAction SilentlyContinue |
    Tee-Object -FilePath $consoleLog

if ($vivadoExitCode -ne 0) {
    throw "WSL Vivado post-route optimization failed with exit code $vivadoExitCode."
}

$bitstream = Join-Path $buildRoot "eth_ps_vdma_hdmi_stage1_board.bit"
if (!(Test-Path $bitstream)) {
    throw "Expected optimized bitstream was not produced: $bitstream"
}

Write-Output "POST_ROUTE_PHYSOPT_WSL_OK bitstream=$bitstream"
