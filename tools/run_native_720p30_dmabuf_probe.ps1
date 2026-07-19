[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$HttpPort = 8097,
    [int]$GstPort = 5014,
    [int]$Frames = 120,
    [int]$Fps = 30,
    [switch]$TraceTiming,
    [switch]$SkipDmabufDeviceSync,
    [string]$CondaEnv = "build\conda-gstreamer-pc",
    [string]$OutDir = "build\native-720p30-dmabuf-display-v1\dmabuf-probe"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
$artifacts = Join-Path $outPath "artifacts"
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
$dmabufDeviceSync = if ($SkipDmabufDeviceSync) { "false" } else { "true" }

function Invoke-UartCommands {
    param(
        [string[]]$Commands,
        [string]$Label,
        [int]$FinalReadSeconds = 5
    )

    $commandFile = Join-Path $outPath "uart-$Label.commands"
    $logFile = Join-Path $outPath "uart-$Label.log"
    $Commands | Set-Content -LiteralPath $commandFile -Encoding ASCII
    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port -CommandFile $commandFile -LoginRoot -Password root `
        -InitialReadSeconds 0 -InterCommandDelayMilliseconds 400 `
        -FinalReadSeconds $FinalReadSeconds -OutputPath $logFile | Out-Null
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

Write-Output "NATIVE_720P30_DMABUF_PROBE_BUILD_START"
& (Join-Path $repoRoot "software\gstreamer\jpegpldec\build-wsl.ps1") -OutDir $artifacts
if ($LASTEXITCODE -ne 0) { throw "plugin build failed" }
& (Join-Path $repoRoot "software\kernel\jpegpl_dma_probe\build-wsl.ps1") -OutDir $artifacts
if ($LASTEXITCODE -ne 0) { throw "kernel client build failed" }

$pluginHash = ((Get-Content (Join-Path $artifacts "libgstjpegpldec.sha256.txt") -TotalCount 1) -split "\s+")[0].ToLowerInvariant()
$insmodCommand = "insmod /tmp/jpegpl_dma_probe.ko"
if ($TraceTiming) {
    $insmodCommand += " trace_timing=1"
}
$serverJob = $null
$sender = $null
try {
    $serverJob = Start-Job -ArgumentList $HttpPort,$artifacts -ScriptBlock {
        param($BindPort, $Root)
        $listener = [System.Net.Sockets.TcpListener]::new(
            [System.Net.IPAddress]::Any, [int]$BindPort)
        $listener.Start()
        try {
            while ($true) {
                $client = $listener.AcceptTcpClient()
                try {
                    $stream = $client.GetStream()
                    $buffer = New-Object byte[] 4096
                    $read = $stream.Read($buffer, 0, $buffer.Length)
                    $request = [System.Text.Encoding]::ASCII.GetString(
                        $buffer, 0, [Math]::Max(0, $read))
                    $line = ($request -split "`r?`n")[0]
                    $parts = $line -split " "
                    $name = if ($parts.Length -ge 2) {
                        [System.IO.Path]::GetFileName(
                            [Uri]::UnescapeDataString($parts[1].TrimStart("/")))
                    } else { "" }
                    $path = Join-Path $Root $name
                    if ($name -and (Test-Path -LiteralPath $path -PathType Leaf)) {
                        $body = [System.IO.File]::ReadAllBytes($path)
                        $header = [System.Text.Encoding]::ASCII.GetBytes(
                            "HTTP/1.0 200 OK`r`nContent-Length: $($body.Length)`r`n" +
                            "Content-Type: application/octet-stream`r`n" +
                            "Connection: close`r`n`r`n")
                    } else {
                        $body = [System.Text.Encoding]::ASCII.GetBytes("not found")
                        $header = [System.Text.Encoding]::ASCII.GetBytes(
                            "HTTP/1.0 404 Not Found`r`nContent-Length: $($body.Length)`r`n" +
                            "Connection: close`r`n`r`n")
                    }
                    $stream.Write($header, 0, $header.Length)
                    $stream.Write($body, 0, $body.Length)
                    $stream.Flush()
                } finally {
                    $client.Close()
                }
            }
        } finally {
            $listener.Stop()
        }
    }
    Start-Sleep -Milliseconds 500

    $startLog = Invoke-UartCommands -Label "start" -FinalReadSeconds 5 -Commands @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "killall gst-launch-1.0 2>/dev/null || true",
        "mkdir -p /tmp/gst-plugins",
        "wget -q -O /tmp/gst-plugins/libgstjpegpldec.so http://$($PcIp):$($HttpPort)/libgstjpegpldec.so",
        "wget -q -O /tmp/jpegpl_dma_probe.ko http://$($PcIp):$($HttpPort)/jpegpl_dma_probe.ko",
        "sha256sum /tmp/gst-plugins/libgstjpegpldec.so",
        "rmmod jpegpl_dma_probe 2>/dev/null || true",
        $insmodCommand,
        "rm -f /tmp/gst-native-720p30-dmabuf.log /tmp/gst-native-720p30-dmabuf.pid",
        "GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-native-720p30-dmabuf.bin nohup gst-launch-1.0 -q udpsrc port=$GstPort caps=`"application/x-rtp,media=(string)video,clock-rate=(int)90000,encoding-name=(string)JPEG,payload=(int)26`" ! rtpjitterbuffer latency=100 drop-on-latency=false ! rtpjpegdepay ! jpegpldec backend=pl-decoder output-mode=drm-dmabuf dmabuf-device-sync=$dmabufDeviceSync summary-interval=30 trace-frames=$($TraceTiming.ToString().ToLowerInvariant()) verify-output-hash=false ! queue max-size-buffers=4 max-size-bytes=0 max-size-time=0 ! fakesink sync=false async=false > /tmp/gst-native-720p30-dmabuf.log 2>&1 & echo `$! > /tmp/gst-native-720p30-dmabuf.pid",
        "sleep 2",
        "ps | grep gst-launch | grep -v grep",
        "cat /tmp/gst-native-720p30-dmabuf.log",
        "echo NATIVE_720P30_DMABUF_RECEIVER_STARTED"
    )
    Require-Text $startLog $pluginHash "deployed plugin sha256"
    Require-Text $startLog "NATIVE_720P30_DMABUF_RECEIVER_STARTED" "receiver start"

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

    Start-Sleep -Seconds 2
    $stopCommands = @(
        "kill `$(cat /tmp/gst-native-720p30-dmabuf.pid) 2>/dev/null || true",
        "sleep 1",
        "cat /tmp/gst-native-720p30-dmabuf.log",
        "dmesg | grep JPEGPL_DMABUF",
        "if dmesg | grep -E 'Oops|BUG:|Kernel panic|hung task'; then echo KERNEL_HEALTH_FAIL; else echo KERNEL_HEALTH_OK; fi",
        "ifconfig eth0",
        "echo NATIVE_720P30_DMABUF_RECEIVER_STOPPED"
    )
    if ($TraceTiming) {
        $stopCommands += "dmesg | grep JPEGPL_TIMING | tail -n 40"
    }
    $stopLog = Invoke-UartCommands -Label "stop" -FinalReadSeconds 8 -Commands $stopCommands
    $text = Get-Content -Raw -LiteralPath $stopLog
    $summaryMatch = [regex]::Match($text,
        "JPEGPLDEC_PL_DECODE_SUMMARY frames=(\d+) failures=(\d+)")
    $progressMatches = [regex]::Matches($text,
        "JPEGPLDEC_PL_DECODE_PROGRESS frames=(\d+) failures=(\d+)")
    $decodedFrames = if ($summaryMatch.Success) {
        [int]$summaryMatch.Groups[1].Value
    } elseif ($progressMatches.Count -gt 0) {
        [int]$progressMatches[$progressMatches.Count - 1].Groups[1].Value
    } else {
        [regex]::Matches($text,
            "JPEGPLDEC_PL_DECODE[\s\S]{0,1000}?output_mode=drm-dmabuf[\s\S]{0,300}?result=pass").Count
    }
    $decodedFailures = if ($summaryMatch.Success) {
        [int]$summaryMatch.Groups[2].Value
    } elseif ($progressMatches.Count -gt 0) {
        [int]$progressMatches[$progressMatches.Count - 1].Groups[2].Value
    } else {
        [regex]::Matches($text, "JPEGPLDEC_PL_DECODE frame=.*result=fail").Count
    }
    $fails = [regex]::Matches($text,
        "JPEGPLDEC_PL_DECODE frame=.*result=fail")
    if ($decodedFrames -lt $Frames -or $decodedFailures -ne 0 -or $fails.Count -ne 0) {
        throw "DMA-BUF decode gate failed: pass=$decodedFrames fail=$decodedFailures"
    }
    Require-Text $stopLog "JPEGPLDEC_DMABUF_POOL_READY" "DMA-BUF pool setup"
    if ($TraceTiming) {
        Require-Text $stopLog "JPEGPL_TIMING" "driver timing trace"
    }
    Require-Text $stopLog "KERNEL_HEALTH_OK" "kernel health"
    Require-Text $stopLog "RX packets:.*errors:0 dropped:0" "Ethernet receive health"
    Require-Text $stopLog "NATIVE_720P30_DMABUF_RECEIVER_STOPPED" "receiver stop"

    $summary = [PSCustomObject]@{
        cycle = "native-720p30-dmabuf-display-v1"
        plugin_sha256 = $pluginHash
        requested_frames = $Frames
        decoded_pass_frames = $decodedFrames
        decoded_fail_frames = $decodedFailures
        dmabuf_slots = 3
        dmabuf_device_sync = $SkipDmabufDeviceSync.IsPresent
        kernel_health = "ok"
        ethernet_errors_dropped = 0
        result = "pass"
        stop_log = $stopLog
    }
    $summary | ConvertTo-Json -Depth 4 | Set-Content `
        -LiteralPath (Join-Path $outPath "summary.json") -Encoding UTF8
    Write-Output "NATIVE_720P30_DMABUF_PROBE_OK summary=$(Join-Path $outPath 'summary.json')"
} finally {
    if ($sender -and -not $sender.HasExited) {
        Stop-Process -Id $sender.Id -Force -ErrorAction SilentlyContinue
    }
    if ($serverJob) {
        Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue
    }
}
