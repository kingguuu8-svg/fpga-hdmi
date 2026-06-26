[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$UartPort = "COM16",
    [int]$CaptureSeconds = 12,
    [int]$Frames = 1,
    [int]$InterPacketUs = 1000,
    [string]$OutputPath = "build\eth-ps-pl-hdmi-pass-through\hardware\reports\uart_stage1_during_udp_probe.log"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$captureScript = Join-Path $repoRoot "tools\capture_uart.ps1"
$output = Join-Path $repoRoot $OutputPath

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null

$capture = Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $captureScript,
    "-Port", $UartPort,
    "-DurationSeconds", $CaptureSeconds,
    "-OutputPath", $OutputPath
) -PassThru -WindowStyle Hidden

try {
    Start-Sleep -Seconds 1
    python (Join-Path $repoRoot "tools\send_video_udp.py") `
        $BoardIp `
        --frames $Frames `
        --fps 1 `
        --pattern bars `
        --inter-packet-us $InterPacketUs

    Wait-Process -Id $capture.Id
}
finally {
    if (-not $capture.HasExited) {
        Stop-Process -Id $capture.Id -Force
    }
}

if (Test-Path $output) {
    Get-Content -LiteralPath $output -Raw
    Write-Output "STAGE1_UDP_PROBE_OK uart_log=$output"
}
else {
    throw "UART capture log was not produced: $output"
}
