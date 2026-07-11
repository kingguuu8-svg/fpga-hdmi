[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$HttpPort = 8093,
    [int]$GstPort = 5011,
    [int]$Frames = 65,
    [int]$MinDecodedFrames = 60,
    [int]$Fps = 5,
    [string]$CaptureDevice = "1",
    [string]$CaptureBackend = "dshow",
    [string]$CondaEnv = "build\conda-gstreamer-pc",
    [string]$OutDir = "build\jpegpldec-real-pl-backend-v1"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
$artifacts = Join-Path $outPath "artifacts"
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

function Invoke-UartCommands {
    param([string[]]$Commands, [string]$Label, [int]$FinalReadSeconds = 4)

    $commandFile = Join-Path $outPath "uart-$Label.commands"
    $logFile = Join-Path $outPath "uart-$Label.log"
    $Commands | Set-Content -LiteralPath $commandFile -Encoding ASCII
    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port -CommandFile $commandFile -LoginRoot -Password root `
        -InitialReadSeconds 0 -InterCommandDelayMilliseconds 400 `
        -FinalReadSeconds $FinalReadSeconds `
        -OutputPath (Join-Path $OutDir "uart-$Label.log") | Out-Null
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

Write-Output "JPEGPLDEC_REAL_BACKEND_BUILD_START"
& (Join-Path $repoRoot "software\gstreamer\jpegpldec\build-wsl.ps1") -OutDir $artifacts
if ($LASTEXITCODE -ne 0) { throw "plugin build failed" }
& (Join-Path $repoRoot "software\kernel\jpegpl_dma_probe\build-wsl.ps1") -OutDir $artifacts
if ($LASTEXITCODE -ne 0) { throw "kernel client build failed" }
Copy-Item -LiteralPath (Join-Path $repoRoot "examples\jpeg-pl-decoder-qualification\vectors\gstreamer-ball-1280x720-q90.jpg") `
    -Destination (Join-Path $artifacts "vector.jpg") -Force

$pluginHash = ((Get-Content -LiteralPath (Join-Path $artifacts "libgstjpegpldec.sha256.txt") -TotalCount 1) -split "\s+")[0].ToLowerInvariant()
$http = $null
$capture = $null
try {
    $http = Start-Process -FilePath python `
        -ArgumentList @("-m", "http.server", "$HttpPort", "--bind", $PcIp, "--directory", $artifacts) `
        -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 1

    $fixedLog = Invoke-UartCommands -Label "fixed-and-software" -FinalReadSeconds 8 -Commands @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "killall gst-launch-1.0 2>/dev/null || true",
        "mkdir -p /tmp/gst-plugins /tmp/jpegpl-fixed-dot",
        "wget -O /tmp/gst-plugins/libgstjpegpldec.so http://$($PcIp):$($HttpPort)/libgstjpegpldec.so",
        "wget -O /tmp/jpegpl_dma_probe.ko http://$($PcIp):$($HttpPort)/jpegpl_dma_probe.ko",
        "wget -O /tmp/jpegpl-vector.jpg http://$($PcIp):$($HttpPort)/vector.jpg",
        "sha256sum /tmp/gst-plugins/libgstjpegpldec.so",
        "rmmod jpegpl_dma_probe 2>/dev/null || true",
        "insmod /tmp/jpegpl_dma_probe.ko",
        "rm -f /tmp/gst-registry-jpegpldec-real.bin /tmp/jpegpl-plugin.rgb /tmp/jpegpl-fixed.log /tmp/jpegpl-software.log",
        "GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec-real.bin gst-inspect-1.0 jpegpldec | sed -n '1,150p'",
        "GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec-real.bin GST_DEBUG_DUMP_DOT_DIR=/tmp/jpegpl-fixed-dot gst-launch-1.0 -q filesrc location=/tmp/jpegpl-vector.jpg blocksize=30054 num-buffers=1 ! image/jpeg,width=1280,height=720,framerate=1/1 ! jpegpldec backend=pl-decoder summary-interval=1 verify-output-hash=true ! filesink location=/tmp/jpegpl-plugin.rgb > /tmp/jpegpl-fixed.log 2>&1",
        "cat /tmp/jpegpl-fixed.log",
        "wc -c /tmp/jpegpl-plugin.rgb",
        "sha256sum /tmp/jpegpl-plugin.rgb",
        "echo FIXED_PL_CHILD_MATCHES=`$(grep -r -l 'pl-hardware-decoder' /tmp/jpegpl-fixed-dot | wc -l)",
        "echo FIXED_SOFTWARE_CHILD_MATCHES=`$(grep -r -l 'software-reference-decoder' /tmp/jpegpl-fixed-dot | wc -l)",
        "GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec-real.bin gst-launch-1.0 -q filesrc location=/tmp/jpegpl-vector.jpg blocksize=30054 num-buffers=1 ! image/jpeg,width=1280,height=720,framerate=1/1 ! jpegpldec backend=software-reference summary-interval=1 ! fakesink > /tmp/jpegpl-software.log 2>&1",
        "cat /tmp/jpegpl-software.log",
        "echo JPEGPLDEC_FIXED_AND_SOFTWARE_OK"
    )
    Require-Text $fixedLog $pluginHash "plugin hash"
    Require-Text $fixedLog "output_fnv=0x7127882c result=pass" "fixed PL FNV"
    Require-Text $fixedLog "2764800 /tmp/jpegpl-plugin.rgb" "fixed RGB size"
    Require-Text $fixedLog "01623472a5f3033e536d4691e3fde1ffc88e702c3b58c876743f5beb4c6d40c9" "fixed RGB SHA-256"
    Require-Text $fixedLog "FIXED_SOFTWARE_CHILD_MATCHES=0" "PL graph software exclusion"
    Require-Text $fixedLog "JPEGPLDEC_FIXED_AND_SOFTWARE_OK" "software regression"

    $startLog = Invoke-UartCommands -Label "start-stream" -FinalReadSeconds 3 -Commands @(
        "killall gst-launch-1.0 2>/dev/null || true",
        "rm -f /tmp/gst_jpegpldec_real.log /tmp/gst_jpegpldec_real.pid",
        "rm -rf /tmp/jpegpl-stream-dot; mkdir -p /tmp/jpegpl-stream-dot",
        "GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec-real.bin GST_DEBUG_DUMP_DOT_DIR=/tmp/jpegpl-stream-dot nohup gst-launch-1.0 -v udpsrc port=$GstPort caps=`"application/x-rtp,media=(string)video,clock-rate=(int)90000,encoding-name=(string)JPEG,payload=(int)26`" ! rtpjitterbuffer latency=100 drop-on-latency=true ! rtpjpegdepay ! jpegpldec backend=pl-decoder summary-interval=10 verify-output-hash=true ! videoconvert ! videoscale ! video/x-raw,format=BGR,width=800,height=600 ! fbdevsink device=/dev/fb0 sync=false qos=false > /tmp/gst_jpegpldec_real.log 2>&1 & echo `$! > /tmp/gst_jpegpldec_real.pid",
        "sleep 3",
        "ps | grep gst-launch | grep -v grep",
        "cat /tmp/gst_jpegpldec_real.log",
        "echo JPEGPLDEC_REAL_STREAM_STARTED"
    )
    Require-Text $startLog "software_jpegdec=absent" "PL backend selection"

    $captureDir = Join-Path $outPath "hdmi-motion-capture"
    Remove-Item -Recurse -Force -LiteralPath $captureDir -ErrorAction SilentlyContinue
    $capture = Start-Process -FilePath python -ArgumentList @(
        (Join-Path $repoRoot "tools\probe_hdmi_motion_capture.py"),
        "--device", $CaptureDevice, "--backend", $CaptureBackend,
        "--width", "800", "--height", "600", "--frames", "240",
        "--fps", "15", "--timeout-sec", "90", "--out-dir", $captureDir
    ) -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput (Join-Path $outPath "hdmi-capture.out.log") `
      -RedirectStandardError (Join-Path $outPath "hdmi-capture.err.log")
    Start-Sleep -Seconds 1

    $senderArgs = @(
        "run", "-p", (Join-Path $repoRoot $CondaEnv), "gst-launch-1.0", "-q",
        "videotestsrc", "num-buffers=$Frames", "is-live=true", "pattern=ball",
        "motion=sweep", "animation-mode=wall-time", "flip=false",
        "background-color=0xff14354a", "foreground-color=0xffffd166",
        "!", "video/x-raw,format=RGB,width=1280,height=720,framerate=$Fps/1",
        "!", "videoconvert", "!", "video/x-raw,format=I420",
        "!", "jpegenc", "quality=90", "!", "rtpjpegpay", "pt=26", "mtu=1200",
        "!", "udpsink", "host=$BoardIp", "port=$GstPort", "sync=false", "async=false"
    )
    $sender = Start-Process -FilePath conda -ArgumentList $senderArgs -WorkingDirectory $repoRoot `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $outPath "sender.out.log") `
        -RedirectStandardError (Join-Path $outPath "sender.err.log")
    if ($sender.ExitCode -ne 0) { throw "PC GStreamer sender failed" }
    if (-not $capture.WaitForExit(90000)) { throw "HDMI capture timed out" }
    $capture.WaitForExit()
    $captureText = Get-Content -Raw -LiteralPath (Join-Path $outPath "hdmi-capture.out.log")
    if ($captureText -notmatch "HDMI_MOTION_CAPTURE_OK") { throw "HDMI capture failed" }

    & python (Join-Path $repoRoot "tools\validate_hdmi_ball_motion.py") `
        (Join-Path $OutDir "hdmi-motion-capture\*.jpg") `
        --out-json (Join-Path $outPath "hdmi-ball-motion-validation.json") `
        --min-samples 200 --min-unique-hashes 4 --min-frames-with-ball 20 --min-centroid-span 20
    if ($LASTEXITCODE -ne 0) { throw "HDMI ball motion validation failed" }

    $stopLog = Invoke-UartCommands -Label "stop-stream" -FinalReadSeconds 6 -Commands @(
        "kill `$(cat /tmp/gst_jpegpldec_real.pid) 2>/dev/null || true",
        "sleep 2",
        "cat /tmp/gst_jpegpldec_real.log",
        "echo PL_CHILD_MATCHES=`$(grep -r -l 'pl-hardware-decoder' /tmp/jpegpl-stream-dot | wc -l)",
        "echo SOFTWARE_CHILD_MATCHES=`$(grep -r -l 'software-reference-decoder' /tmp/jpegpl-stream-dot | wc -l)",
        "if dmesg | grep -E 'Oops|BUG:|Kernel panic|hung task'; then echo KERNEL_HEALTH_FAIL; else echo KERNEL_HEALTH_OK; fi",
        "ifconfig eth0",
        "echo JPEGPLDEC_POST_RUN_HEALTH_OK"
    )
    $streamText = Get-Content -Raw -LiteralPath $stopLog
    $passes = [regex]::Matches($streamText, "JPEGPLDEC_PL_DECODE frame=.*result=pass")
    $fails = [regex]::Matches($streamText, "JPEGPLDEC_PL_DECODE frame=.*result=fail")
    if ($passes.Count -lt $MinDecodedFrames -or $fails.Count -ne 0) {
        throw "PL stream gate failed: pass=$($passes.Count) fail=$($fails.Count)"
    }
    $hashes = [regex]::Matches($streamText, "output_fnv=0x([0-9a-fA-F]+) result=pass") |
        ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Sort-Object -Unique
    if ($hashes.Count -lt 10) { throw "PL output did not show enough unique frames: $($hashes.Count)" }
    $pts = @([regex]::Matches($streamText, "JPEGPLDEC_PL_DECODE frame=.*pts=([0-9]+).*result=pass") |
        ForEach-Object { [UInt64]$_.Groups[1].Value })
    $ptsMonotonic = $pts.Count -ge $MinDecodedFrames
    for ($i = 1; $i -lt $pts.Count; $i++) {
        if ($pts[$i] -le $pts[$i - 1]) { $ptsMonotonic = $false; break }
    }
    if (-not $ptsMonotonic) { throw "PL output PTS values are missing or non-monotonic" }
    Require-Text $stopLog "SOFTWARE_CHILD_MATCHES=0" "stream graph software exclusion"
    Require-Text $stopLog "KERNEL_HEALTH_OK" "kernel health"
    Require-Text $stopLog "RX packets:.*errors:0 dropped:0" "Ethernet receive health"
    Require-Text $stopLog "JPEGPLDEC_POST_RUN_HEALTH_OK" "post-run health"

    $summary = [PSCustomObject]@{
        cycle = "jpegpldec-real-pl-backend-v1"
        plugin_sha256 = $pluginHash
        fixed_output_fnv = "0x7127882c"
        fixed_output_sha256 = "01623472a5f3033e536d4691e3fde1ffc88e702c3b58c876743f5beb4c6d40c9"
        requested_frames = $Frames
        decoded_pass_frames = $passes.Count
        decoded_fail_frames = $fails.Count
        unique_output_hashes = $hashes.Count
        pts_monotonic = $ptsMonotonic
        software_child_matches = 0
        hdmi_validation = Join-Path $outPath "hdmi-ball-motion-validation.json"
        fixed_log = $fixedLog
        stream_log = $stopLog
        result = "pass"
    }
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outPath "summary.json") -Encoding UTF8
    Write-Output "JPEGPLDEC_REAL_BACKEND_OK summary=$(Join-Path $outPath 'summary.json')"
} finally {
    if ($capture -and -not $capture.HasExited) {
        Stop-Process -Id $capture.Id -Force -ErrorAction SilentlyContinue
    }
    if ($http -and -not $http.HasExited) {
        Stop-Process -Id $http.Id -Force -ErrorAction SilentlyContinue
    }
}
