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
$buildRoot = Join-Path $repoRoot "build\eth-ps-pl-hdmi-pass-through\board"
$reportRoot = Join-Path $buildRoot "reports"
$tcl = Join-Path $PSScriptRoot "audit_stage1_board_timing.tcl"

New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$wslBuildRoot = Convert-ToWslPath $buildRoot
$wslTcl = Convert-ToWslPath $tcl
$wslVivadoLog = Convert-ToWslPath (Join-Path $reportRoot "timing_audit_vivado.log")
$consoleLog = Join-Path $reportRoot "timing_audit_console.log"
$stdoutLog = Join-Path $reportRoot "timing_audit_stdout.log"
$stderrLog = Join-Path $reportRoot "timing_audit_stderr.log"

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
    throw "WSL Vivado timing audit failed with exit code $vivadoExitCode."
}

Write-Output "STAGE1_TIMING_AUDIT_OK report_root=$reportRoot"
