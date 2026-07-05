[CmdletBinding()]
param(
    [string]$OutDir = "build\720p30-jpeg-chain-contract",
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$GstPort = 5011,
    [int]$DurationSec = 6,
    [int]$JpegQuality = 90,
    [string]$CondaEnv = "build\conda-gstreamer-pc",
    [switch]$PlanOnly,
    [switch]$AnalyzeOnly
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

$plan = [PSCustomObject]@{
    cycle = "720p30-jpeg-chain-contract"
    input_width = 1280
    input_height = 720
    fps = 30
    jpeg_quality = $JpegQuality
    transport = "RTP/JPEG"
    decoder_entry = "jpegpldec route reference uses existing software jpegdec benchmark first"
    current_display_output = "800x600 unless a separate 720p HDMI mode gate passes"
    board_ip = $BoardIp
    pc_ip = $PcIp
    gst_port = $GstPort
    duration_sec = $DurationSec
}
$plan | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outPath "720p30-gate-plan.json") -Encoding UTF8

if ($PlanOnly) {
    "720P30_JPEG_CHAIN_GATE_PLAN_OK out=$outPath" | Tee-Object -FilePath (Join-Path $outPath "720p30-gate.marker.txt")
    return
}

if (-not $AnalyzeOnly) {
    & (Join-Path $repoRoot "tools\run_video_bottleneck_probe.ps1") `
        -BoardIp $BoardIp `
        -PcIp $PcIp `
        -Port $Port `
        -GstPort $GstPort `
        -FpsList @(30) `
        -DurationSec $DurationSec `
        -InputWidth 1280 `
        -InputHeight 720 `
        -OutputWidth 800 `
        -OutputHeight 600 `
        -JpegQuality $JpegQuality `
        -CondaEnv $CondaEnv `
        -OutDir $OutDir
}

$summary = Join-Path $outPath "video-bottleneck-summary.json"
if (-not (Test-Path -LiteralPath $summary)) {
    throw "missing 720p30 summary: $summary"
}

$summaryJson = Get-Content -Raw -LiteralPath $summary | ConvertFrom-Json
$cases = @($summaryJson.jpeg_cases)
$measured = @($cases | Where-Object { $_.status -eq "measured" })
if ($measured.Count -eq 0) {
    throw "720p30 gate produced no measured cases"
}

$fakesink = $measured | Where-Object { $_.route -eq "rtp-jpeg-to-fakesink" } | Select-Object -First 1
$fbdevsink = $measured | Where-Object { $_.route -eq "rtp-jpeg-to-fbdevsink" } | Select-Object -First 1
$fakesinkFps = if ($null -ne $fakesink) { [double]$fakesink.board_average_fps } else { 0.0 }
$fbdevsinkFps = if ($null -ne $fbdevsink) { [double]$fbdevsink.board_average_fps } else { 0.0 }
$targetMet = $fakesinkFps -ge 25.0 -and $fbdevsinkFps -ge 25.0
$status = if ($targetMet) { "pass" } else { "blocked-software-baseline" }

$gateSummary = [PSCustomObject]@{
    cycle = "720p30-jpeg-chain-contract"
    target = "1280x720@30"
    current_output = "800x600"
    status = $status
    fakesink_average_fps = $fakesinkFps
    fbdevsink_average_fps = $fbdevsinkFps
    measured_cases = $measured.Count
    evidence = $summary
}
$gateSummary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outPath "720p30-gate-summary.json") -Encoding UTF8

$markerName = if ($targetMet) { "720P30_JPEG_CHAIN_GATE_OK" } else { "720P30_JPEG_CHAIN_GATE_BLOCKED" }
$marker = "$markerName status=$status input=1280x720@30 output=800x600 fakesink_fps=$fakesinkFps fbdevsink_fps=$fbdevsinkFps cases=$($measured.Count) summary=$summary"
$marker | Tee-Object -FilePath (Join-Path $outPath "720p30-gate.marker.txt")
