[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$HttpPort = 8094,
    [int]$GstPort = 5012,
    [int]$Frames = 330,
    [int]$MinFrames = 300,
    [int]$Fps = 30,
    [string]$CondaEnv = "build\conda-gstreamer-pc",
    [string]$OutDir = "build\jpegpldec-pl-throughput-720p30-v1\runtime"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
$artifacts = Join-Path $outPath "artifacts"
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

function Invoke-UartCommands {
    param([string[]]$Commands, [string]$Label, [int]$FinalReadSeconds = 5)

    $commandFile = Join-Path $outPath "uart-$Label.commands"
    $Commands | Set-Content -LiteralPath $commandFile -Encoding ASCII
    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port -CommandFile $commandFile -LoginRoot -Password root `
        -InitialReadSeconds 5 -InterCommandDelayMilliseconds 400 `
        -FinalReadSeconds $FinalReadSeconds `
        -OutputPath (Join-Path $OutDir "uart-$Label.log") | Out-Null
    $logFile = Join-Path $outPath "uart-$Label.log"
    if (-not (Test-Path -LiteralPath $logFile)) {
        throw "UART log missing: $logFile"
    }
    return $logFile
}

function Require-Text {
    param([string]$Path, [string]$Pattern, [string]$Label)
    if ((Get-Content -Raw -LiteralPath $Path) -notmatch $Pattern) {
        throw "$Label missing in $Path"
    }
}

Write-Output "JPEGPLDEC_720P30_THROUGHPUT_BUILD_START"
& (Join-Path $repoRoot "software\gstreamer\jpegpldec\build-wsl.ps1") -OutDir $artifacts
if ($LASTEXITCODE -ne 0) { throw "plugin build failed" }
& (Join-Path $repoRoot "software\kernel\jpegpl_dma_probe\build-wsl.ps1") -OutDir $artifacts
if ($LASTEXITCODE -ne 0) { throw "kernel client build failed" }

$pluginHash = ((Get-Content (Join-Path $artifacts "libgstjpegpldec.sha256.txt") -TotalCount 1) -split "\s+")[0].ToLowerInvariant()
$http = $null
try {
    $http = Start-Process -FilePath python -ArgumentList @(
        "-m", "http.server", "$HttpPort", "--bind", $PcIp, "--directory", $artifacts
    ) -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 1

    $startLog = Invoke-UartCommands -Label "start" -FinalReadSeconds 4 -Commands @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "killall gst-launch-1.0 2>/dev/null || true",
        "mkdir -p /tmp/gst-plugins",
        "wget -q -O /tmp/gst-plugins/libgstjpegpldec.so http://$($PcIp):$($HttpPort)/libgstjpegpldec.so",
        "wget -q -O /tmp/jpegpl_dma_probe.ko http://$($PcIp):$($HttpPort)/jpegpl_dma_probe.ko",
        "sha256sum /tmp/gst-plugins/libgstjpegpldec.so",
        "rmmod jpegpl_dma_probe 2>/dev/null || true",
        "insmod /tmp/jpegpl_dma_probe.ko",
        "rm -f /tmp/gst-jpegpldec-720p30.log /tmp/gst-jpegpldec-720p30.pid",
        "GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec-720p30.bin nohup gst-launch-1.0 -q udpsrc port=$GstPort caps=`"application/x-rtp,media=(string)video,clock-rate=(int)90000,encoding-name=(string)JPEG,payload=(int)26`" ! rtpjitterbuffer latency=100 drop-on-latency=false ! rtpjpegdepay ! jpegpldec backend=pl-decoder summary-interval=30 verify-output-hash=false ! fakesink sync=false > /tmp/gst-jpegpldec-720p30.log 2>&1 & echo `$! > /tmp/gst-jpegpldec-720p30.pid",
        "sleep 2",
        "ps | grep gst-launch | grep -v grep",
        "echo JPEGPLDEC_720P30_RECEIVER_STARTED"
    )
    Require-Text $startLog $pluginHash "plugin hash"
    Require-Text $startLog "JPEGPLDEC_720P30_RECEIVER_STARTED" "receiver start"

    $sender = Start-Process -FilePath conda -ArgumentList @(
        "run", "-p", (Join-Path $repoRoot $CondaEnv), "gst-launch-1.0", "-q",
        "videotestsrc", "num-buffers=$Frames", "is-live=true", "pattern=ball",
        "motion=sweep", "animation-mode=wall-time", "flip=false",
        "background-color=0xff14354a", "foreground-color=0xffffd166",
        "!", "video/x-raw,format=RGB,width=1280,height=720,framerate=$Fps/1",
        "!", "videoconvert", "!", "video/x-raw,format=I420",
        "!", "jpegenc", "quality=90", "!", "rtpjpegpay", "pt=26", "mtu=1200",
        "!", "udpsink", "host=$BoardIp", "port=$GstPort", "sync=false", "async=false"
    ) -WorkingDirectory $repoRoot -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $outPath "sender.out.log") `
        -RedirectStandardError (Join-Path $outPath "sender.err.log")
    if ($sender.ExitCode -ne 0) { throw "PC GStreamer sender failed" }

    Start-Sleep -Seconds 3
    $stopLog = Invoke-UartCommands -Label "stop" -FinalReadSeconds 8 -Commands @(
        "kill `$(cat /tmp/gst-jpegpldec-720p30.pid) 2>/dev/null || true",
        "sleep 1",
        "cat /tmp/gst-jpegpldec-720p30.log",
        "if dmesg | grep -E 'Oops|BUG:|Kernel panic|hung task'; then echo KERNEL_HEALTH_FAIL; else echo KERNEL_HEALTH_OK; fi",
        "ifconfig eth0",
        "echo JPEGPLDEC_720P30_RECEIVER_STOPPED"
    )
    $text = Get-Content -Raw -LiteralPath $stopLog
    $passes = [regex]::Matches($text, "JPEGPLDEC_PL_DECODE frame=.*total_ms=([0-9.]+).*result=pass")
    $fails = [regex]::Matches($text, "JPEGPLDEC_PL_DECODE frame=.*result=fail")
    if ($passes.Count -lt $MinFrames -or $fails.Count -ne 0) {
        throw "720p30 decode gate failed: pass=$($passes.Count) fail=$($fails.Count)"
    }
    $times = @($passes | ForEach-Object { [double]$_.Groups[1].Value } | Sort-Object)
    $p95Index = [Math]::Min($times.Count - 1, [Math]::Ceiling($times.Count * 0.95) - 1)
    $p95 = $times[$p95Index]
    if ($p95 -gt 33.333) { throw "720p30 wall-time gate failed: p95_ms=$p95" }
    Require-Text $stopLog "KERNEL_HEALTH_OK" "kernel health"
    Require-Text $stopLog "RX packets:.*errors:0 dropped:0" "Ethernet receive health"
    Require-Text $stopLog "JPEGPLDEC_720P30_RECEIVER_STOPPED" "receiver stop"

    $summary = [PSCustomObject]@{
        cycle = "jpegpldec-pl-throughput-720p30-v1"
        plugin_sha256 = $pluginHash
        requested_frames = $Frames
        decoded_pass_frames = $passes.Count
        decoded_fail_frames = $fails.Count
        total_ms_p95 = $p95
        target_fps = $Fps
        kernel_health = "ok"
        ethernet_errors_dropped = 0
        result = "pass"
        stop_log = $stopLog
    }
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outPath "summary.json") -Encoding UTF8
    Write-Output "JPEGPLDEC_720P30_THROUGHPUT_OK summary=$(Join-Path $outPath 'summary.json')"
} finally {
    if ($http -and -not $http.HasExited) {
        Stop-Process -Id $http.Id -Force -ErrorAction SilentlyContinue
    }
}
