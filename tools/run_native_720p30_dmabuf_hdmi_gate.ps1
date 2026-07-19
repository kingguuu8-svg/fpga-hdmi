[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$HttpPort = 8098,
    [int]$GstPort = 5016,
    [int]$Frames = 1800,
    [int]$Fps = 30,
    [int]$CaptureFps = 60,
    [int]$TearingFrames = 300,
    [int]$WarmupSeconds = 25,
    [string]$CaptureDevice = "1",
    [string]$CaptureBackend = "dshow",
    [ValidateSet("drm-dmabuf", "mmap")]
    [string]$OutputMode = "drm-dmabuf",
    [switch]$SkipDmabufDeviceSync,
    [switch]$VerifyOutputHash,
    [switch]$TraceFrames,
    [switch]$KmsDebug,
    [switch]$DrmDebug,
    [switch]$UseV12Pipeline,
    [switch]$UseHistoricalV12Plugin,
    [string]$CondaEnv = "build\conda-gstreamer-pc",
    [string]$OutDir = "build\native-720p30-dmabuf-display-v1\hdmi-gate"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
$artifacts = Join-Path $outPath "artifacts"
$sequenceDir = Join-Path $outPath "tearing-sequence"
$dmabufDeviceSync = if ($SkipDmabufDeviceSync) { "false" } else { "true" }
$verifyOutputHashValue = if ($VerifyOutputHash) { "true" } else { "false" }
$traceFramesValue = if ($TraceFrames) { "true" } else { "false" }
$gstVerbosity = if ($KmsDebug) { "-v" } else { "-q" }
$gstDebug = if ($KmsDebug) { "GST_DEBUG=kmssink:7,bufferpool:7" } else { "" }
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

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

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Stop-PcVideoSenders {
    param(
        [string]$DestinationIp,
        [int]$DestinationPort
    )

    $escapedIp = [regex]::Escape($DestinationIp)
    $escapedPort = [regex]::Escape([string]$DestinationPort)
    $senders = Get-CimInstance Win32_Process -Filter "Name = 'gst-launch-1.0.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^gst-launch-1\.0(?:\.exe)?$' -and
        $_.CommandLine -match 'udpsink' -and
        $_.CommandLine -match "host=$escapedIp" -and
        $_.CommandLine -match "port=$escapedPort"
    }
    foreach ($sender in $senders) {
        Stop-Process -Id ([int]$sender.ProcessId) -Force -ErrorAction SilentlyContinue
    }
}

function Start-BoardReceiver {
    param(
        [string]$HttpRoot,
        [string]$Label = "start"
    )

    $logPath = "/tmp/gst-native-720p30-dmabuf-hdmi.log"
    $pidPath = "/tmp/gst-native-720p30-dmabuf-hdmi.pid"
    $pipeline = if ($UseV12Pipeline) {
        "$gstDebug GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-native-720p30-dmabuf-hdmi.bin nohup gst-launch-1.0 $gstVerbosity udpsrc port=$GstPort caps=`"application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)JPEG, payload=(int)26`" ! rtpjitterbuffer latency=100 drop-on-latency=true ! rtpjpegdepay ! jpegparse ! capssetter caps=`"image/jpeg,framerate=(fraction)$Fps/1`" ! jpegpldec backend=pl-decoder output-mode=mmap dmabuf-device-sync=$dmabufDeviceSync summary-interval=30 trace-frames=$traceFramesValue verify-output-hash=$verifyOutputHashValue ! video/x-raw,format=BGR,width=1280,height=720 ! kmssink force-modesetting=true sync=false qos=false > $logPath 2>&1 & echo `$! > $pidPath"
    } else {
        "$gstDebug GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-native-720p30-dmabuf-hdmi.bin nohup gst-launch-1.0 $gstVerbosity udpsrc port=$GstPort caps=`"application/x-rtp,media=(string)video,clock-rate=(int)90000,encoding-name=(string)JPEG,payload=(int)26`" ! rtpjitterbuffer latency=100 drop-on-latency=false ! rtpjpegdepay ! jpegpldec backend=pl-decoder output-mode=$OutputMode dmabuf-device-sync=$dmabufDeviceSync summary-interval=30 trace-frames=$traceFramesValue verify-output-hash=$verifyOutputHashValue ! queue max-size-buffers=3 max-size-bytes=0 max-size-time=0 ! kmssink force-modesetting=true sync=false qos=false > $logPath 2>&1 & echo `$! > $pidPath"
    }
    $receiverCommands = @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "killall gst-launch-1.0 2>/dev/null || true",
        "mkdir -p /tmp/gst-plugins",
        "wget -q -O /tmp/gst-plugins/libgstjpegpldec.so http://$($PcIp):$HttpPort/libgstjpegpldec.so",
        "wget -q -O /tmp/jpegpl_dma_probe.ko http://$($PcIp):$HttpPort/jpegpl_dma_probe.ko",
        "sha256sum /tmp/gst-plugins/libgstjpegpldec.so",
        "rmmod jpegpl_dma_probe 2>/dev/null || true",
        "insmod /tmp/jpegpl_dma_probe.ko",
        "rm -f $logPath $pidPath"
    )
    if ($UseV12Pipeline) {
        $runtimeRoot = Join-Path $repoRoot "build\native-720p-display-v2\runtime-staging"
        foreach ($tool in @("pip_effect_server", "pip_effect_ctl")) {
            $toolPath = Join-Path $runtimeRoot $tool
            if (-not (Test-Path -LiteralPath $toolPath)) {
                throw "missing v12 runtime tool: $toolPath"
            }
            Copy-Item -LiteralPath $toolPath -Destination (Join-Path $artifacts $tool) -Force
        }
        $receiverCommands += @(
            "mkdir -p /tmp/pip-tools",
            "wget -q -O /tmp/pip-tools/pip_effect_server http://$($PcIp):$HttpPort/pip_effect_server",
            "wget -q -O /tmp/pip-tools/pip_effect_ctl http://$($PcIp):$HttpPort/pip_effect_ctl",
            "chmod +x /tmp/pip-tools/pip_effect_server /tmp/pip-tools/pip_effect_ctl",
            "killall pip_effect_server 2>/dev/null || true",
            "nohup /tmp/pip-tools/pip_effect_server --port 5012 > /tmp/pip_effect_server.log 2>&1 & echo `$! > /tmp/pip_effect_server.pid",
            "sleep 1",
            "if ! kill -0 `$(cat /tmp/pip_effect_server.pid 2>/dev/null) 2>/dev/null; then echo PIP_CONTROL_SERVER_FAILED; tail -n 20 /tmp/pip_effect_server.log 2>/dev/null || true; exit 1; fi",
            "/tmp/pip-tools/pip_effect_ctl --preset large",
            "setterm -cursor off > /dev/`$(cat /sys/class/tty/tty0/active) 2>/dev/null || true"
        )
    }
    $receiverCommands += @(
        $pipeline,
        "sleep 3",
        "ps | grep gst-launch | grep -v grep",
        "cat $logPath",
        "echo NATIVE_720P30_DMABUF_HDMI_RECEIVER_STARTED"
    )
    $log = Invoke-UartCommands -Label $Label -FinalReadSeconds 6 -Commands $receiverCommands
    return $log
}

function Stop-BoardReceiver {
    param([string]$Label = "stop")

    return Invoke-UartCommands -Label $Label -FinalReadSeconds 10 -Commands @(
        "kill `$(cat /tmp/gst-native-720p30-dmabuf-hdmi.pid) 2>/dev/null || true",
        "sleep 2",
        "cat /tmp/gst-native-720p30-dmabuf-hdmi.log",
        "if dmesg | grep -E 'Oops|BUG:|Kernel panic|hung task'; then echo KERNEL_HEALTH_FAIL; else echo KERNEL_HEALTH_OK; fi",
        "ifconfig eth0",
        "echo NATIVE_720P30_DMABUF_HDMI_RECEIVER_STOPPED"
    )
}

function Start-Capture {
    param([string]$CaptureDir, [int]$CaptureFrames, [int]$CaptureFps, [string]$Label)

    Remove-Item -Recurse -Force -LiteralPath $CaptureDir -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $CaptureDir | Out-Null
    $stdout = Join-Path $outPath "$Label-capture.out.log"
    $stderr = Join-Path $outPath "$Label-capture.err.log"
    return Start-Process -FilePath python -WindowStyle Hidden -PassThru `
        -WorkingDirectory $repoRoot `
        -ArgumentList @(
            (Join-Path $repoRoot "tools\probe_hdmi_motion_capture.py"),
            "--device", $CaptureDevice,
            "--backend", $CaptureBackend,
            "--width", "1280",
            "--height", "720",
            "--frames", "$CaptureFrames",
            "--fps", "$CaptureFps",
            "--timeout-sec", "180",
            "--out-dir", $CaptureDir
        ) `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
}

function Read-BoardDrmDebug {
    return Invoke-UartCommands -Label "drm-debug" -FinalReadSeconds 6 -Commands @(
        "mount -t debugfs none /sys/kernel/debug 2>/dev/null || true",
        "cat /sys/kernel/debug/dri/0/framebuffer 2>/dev/null || true",
        "cat /sys/kernel/debug/dri/0/state 2>/dev/null || true",
        "echo VDMA0_MM2S",
        "for addr in 0x43000000 0x43000004 0x43000050 0x43000054 0x43000058 0x4300005c 0x43000060 0x43000064; do printf '%s=' `$addr; devmem `$addr 32; done",
        "echo VDMA1_MM2S",
        "for addr in 0x43020000 0x43020004 0x43020050 0x43020054 0x43020058 0x4302005c 0x43020060 0x43020064; do printf '%s=' `$addr; devmem `$addr 32; done"
    )
}

$serverJob = $null
$ballCapture = $null
$stripeCapture = $null
$ballSender = $null
$stripeSender = $null
$ballStopLog = $null
$stopLog = $null
$receiverStarted = $false
try {
    Write-Output "NATIVE_720P30_DMABUF_HDMI_GATE_BUILD_START"
    & (Join-Path $repoRoot "software\gstreamer\jpegpldec\build-wsl.ps1") -OutDir $artifacts
    if ($LASTEXITCODE -ne 0) { throw "plugin build failed" }
    & (Join-Path $repoRoot "software\kernel\jpegpl_dma_probe\build-wsl.ps1") -OutDir $artifacts
    if ($LASTEXITCODE -ne 0) { throw "kernel client build failed" }
    if ($UseHistoricalV12Plugin) {
        $historicalPlugin = Join-Path $repoRoot "build\native-720p-display-v2\runtime-staging\libgstjpegpldec.so"
        $historicalDriver = Join-Path $repoRoot "build\native-720p-display-v2\runtime-staging\jpegpl_dma_probe.ko"
        if (-not (Test-Path -LiteralPath $historicalPlugin)) {
            throw "missing historical v12 plugin: $historicalPlugin"
        }
        if (-not (Test-Path -LiteralPath $historicalDriver)) {
            throw "missing historical v12 driver: $historicalDriver"
        }
        Copy-Item -LiteralPath $historicalPlugin -Destination (Join-Path $artifacts "libgstjpegpldec.so") -Force
        Copy-Item -LiteralPath $historicalDriver -Destination (Join-Path $artifacts "jpegpl_dma_probe.ko") -Force
    }
    & python (Join-Path $repoRoot "tools\generate_jpeg_tearing_sequence.py") `
        --out-dir $sequenceDir --frames $TearingFrames --width 1280 --height 720 --quality 95
    if ($LASTEXITCODE -ne 0) { throw "tearing sequence generation failed" }

    $pluginHashFile = Join-Path $artifacts "libgstjpegpldec.so"
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $pluginHash = ([System.BitConverter]::ToString(
            $sha256.ComputeHash([System.IO.File]::ReadAllBytes($pluginHashFile))
        )).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
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
                    $request = [System.Text.Encoding]::ASCII.GetString($buffer, 0, [Math]::Max(0, $read))
                    $line = ($request -split "`r?`n")[0]
                    $parts = $line -split " "
                    $name = if ($parts.Length -ge 2) {
                        [System.IO.Path]::GetFileName([Uri]::UnescapeDataString($parts[1].TrimStart("/")))
                    } else { "" }
                    $path = Join-Path $Root $name
                    if ($name -and (Test-Path -LiteralPath $path -PathType Leaf)) {
                        $body = [System.IO.File]::ReadAllBytes($path)
                        $header = [System.Text.Encoding]::ASCII.GetBytes(
                            "HTTP/1.0 200 OK`r`nContent-Length: $($body.Length)`r`n" +
                            "Content-Type: application/octet-stream`r`nConnection: close`r`n`r`n")
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

    $null = Stop-PcVideoSenders -DestinationIp $BoardIp -DestinationPort $GstPort
    $startLog = Start-BoardReceiver -HttpRoot $artifacts -Label "start"
    Require-Text $startLog $pluginHash "deployed plugin sha256"
    $selectionPattern = if ($UseHistoricalV12Plugin) {
        "JPEGPLDEC_BACKEND_SELECTED.*output_mmap=1"
    } else {
        "JPEGPLDEC_BACKEND_SELECTED.*output_mode=$OutputMode"
    }
    Require-Text $startLog $selectionPattern "PL decoder selection"
    Require-Text $startLog "NATIVE_720P30_DMABUF_HDMI_RECEIVER_STARTED" "receiver start"
    $receiverStarted = $true

    $ballDir = Join-Path $outPath "ball-capture"
    $ballSourceFrames = $Frames + ($Fps * ($WarmupSeconds + 5))
    $ballCaptureFrames = [Math]::Ceiling($Frames * $CaptureFps / [double]$Fps)
    $null = Stop-PcVideoSenders -DestinationIp $BoardIp -DestinationPort $GstPort
    $ballSender = Start-Process -FilePath conda -ArgumentList @(
        "run", "-p", (Join-Path $repoRoot $CondaEnv), "gst-launch-1.0", "-q",
        "videotestsrc", "num-buffers=$ballSourceFrames", "is-live=true", "pattern=ball",
        "motion=sweep", "animation-mode=wall-time", "flip=false",
        "background-color=0xff14354a", "foreground-color=0xffffd166",
        "!", "video/x-raw,format=RGB,width=1280,height=720,framerate=$Fps/1",
        "!", "videoconvert", "!", "video/x-raw,format=I420",
        "!", "jpegenc", "quality=90", "!", "rtpjpegpay", "pt=26", "mtu=1200",
        "!", "udpsink", "host=$BoardIp", "port=$GstPort", "sync=false", "async=false"
    ) -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $outPath "ball-sender.out.log") `
        -RedirectStandardError (Join-Path $outPath "ball-sender.err.log")
    Start-Sleep -Seconds $WarmupSeconds
    $ballCapture = Start-Capture -CaptureDir $ballDir -CaptureFrames $ballCaptureFrames -CaptureFps $CaptureFps -Label "ball"
    if (-not $ballCapture.WaitForExit(180000)) { throw "ball HDMI capture timed out" }
    $ballCapture.Refresh()
    if (-not $ballSender.WaitForExit(180000)) { throw "ball sender timed out" }
    $ballSender.Refresh()
    if ($null -ne $ballSender.ExitCode -and $ballSender.ExitCode -ne 0) {
        throw "ball sender failed exit_code=$($ballSender.ExitCode)"
    }
    if ($DrmDebug) {
        $null = Read-BoardDrmDebug
    }
    $ballReport = Join-Path $ballDir "mjpeg-stream-probe.json"
    Require-Text (Join-Path $outPath "ball-capture.out.log") "HDMI_MOTION_CAPTURE_OK" "ball HDMI capture"
    & python (Join-Path $repoRoot "tools\validate_hdmi_ball_motion.py") `
        (Join-Path $ballDir "*.jpg") --out-json (Join-Path $outPath "ball-motion-validation.json") `
        --min-samples 120 --min-unique-hashes 4 --min-frames-with-ball 60 --min-centroid-span 20
    if ($LASTEXITCODE -ne 0) { throw "ball HDMI validation failed" }
    & python (Join-Path $repoRoot "tools\analyze_hdmi_content_cadence.py") `
        $ballReport --out-json (Join-Path $outPath "ball-content-cadence.json") `
        --min-fps 29.5 `
        --min-distinct-frames ([Math]::Max(1, [int][Math]::Floor($Frames * 29.5 / [double]$Fps)))
    if ($LASTEXITCODE -ne 0) { throw "HDMI content cadence failed" }

    $ballStopLog = Stop-BoardReceiver -Label "ball-stop"
    $receiverStarted = $false
    Require-Text $ballStopLog "JPEGPLDEC_DMABUF_POOL_READY" "ball DMA-BUF pool"
    Require-Text $ballStopLog "JPEGPLDEC_PL_DECODE_PROGRESS frames=$Frames failures=0" "full ball decode count"
    Require-Text $ballStopLog "KERNEL_HEALTH_OK" "ball kernel health"
    Require-Text $ballStopLog "RX packets:.*errors:0 dropped:0" "ball Ethernet receive health"
    Require-Text $ballStopLog "NATIVE_720P30_DMABUF_HDMI_RECEIVER_STOPPED" "ball receiver stop"

    $stripeStartLog = Start-BoardReceiver -HttpRoot $artifacts -Label "stripe-start"
    Require-Text $stripeStartLog $pluginHash "deployed plugin sha256 for stripe receiver"
    Require-Text $stripeStartLog $selectionPattern "PL decoder selection for stripe receiver"
    Require-Text $stripeStartLog "NATIVE_720P30_DMABUF_HDMI_RECEIVER_STARTED" "stripe receiver start"
    $receiverStarted = $true

    $stripeDir = Join-Path $outPath "stripe-capture"
    $stripeCaptureFrames = [Math]::Ceiling($TearingFrames * $CaptureFps / [double]$Fps)
    $sequenceLocation = $sequenceDir -replace '\\', '/'
    $null = Stop-PcVideoSenders -DestinationIp $BoardIp -DestinationPort $GstPort
    $stripeSender = Start-Process -FilePath conda -ArgumentList @(
        "run", "-p", (Join-Path $repoRoot $CondaEnv), "gst-launch-1.0", "-q",
        "multifilesrc", "location=$sequenceLocation/frame-%04d.jpg",
        "start-index=0", "stop-index=$($TearingFrames - 1)",
        "caps=image/jpeg,framerate=(fraction)$Fps/1", "loop=true",
        "!", "jpegparse", "!", "identity", "sleep-time=20000", "!", "jpegdec",
        "!", "videoconvert", "!", "video/x-raw,format=I420,width=1280,height=720,framerate=$Fps/1",
        "!", "jpegenc", "quality=90", "!", "rtpjpegpay", "pt=26", "mtu=1200",
        "!", "udpsink", "host=$BoardIp", "port=$GstPort", "sync=false", "async=false"
    ) -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $outPath "stripe-sender.out.log") `
        -RedirectStandardError (Join-Path $outPath "stripe-sender.err.log")
    Start-Sleep -Seconds $WarmupSeconds
    $stripeCapture = Start-Capture -CaptureDir $stripeDir -CaptureFrames $stripeCaptureFrames -CaptureFps $CaptureFps -Label "stripe"
    if (-not $stripeCapture.WaitForExit(180000)) { throw "stripe HDMI capture timed out" }
    $stripeCapture.Refresh()
    if ($stripeSender -and -not $stripeSender.HasExited) {
        Stop-Process -Id $stripeSender.Id -Force -ErrorAction SilentlyContinue
    }
    if ($stripeSender -and -not $stripeSender.WaitForExit(10000)) {
        throw "stripe sender did not stop"
    }
    $stripeReport = Join-Path $stripeDir "mjpeg-stream-probe.json"
    Require-Text (Join-Path $outPath "stripe-capture.out.log") "HDMI_MOTION_CAPTURE_OK" "stripe HDMI capture"
    & python (Join-Path $repoRoot "tools\validate_bidirectional_tearing.py") `
        $stripeReport --result-json (Join-Path $outPath "bidirectional-tearing-validation.json")
    if ($LASTEXITCODE -ne 0) { throw "bidirectional tearing validation failed" }

    $stopLog = Stop-BoardReceiver
    $receiverStarted = $false
    Require-Text $stopLog "JPEGPLDEC_DMABUF_POOL_READY" "DMA-BUF pool"
    Require-Text $ballStopLog "JPEGPLDEC_PL_DECODE_PROGRESS frames=$Frames failures=0" "full ball decode count"
    Require-Text $stopLog "KERNEL_HEALTH_OK" "kernel health"
    Require-Text $stopLog "RX packets:.*errors:0 dropped:0" "Ethernet receive health"
    Require-Text $stopLog "NATIVE_720P30_DMABUF_HDMI_RECEIVER_STOPPED" "receiver stop"

    $ballCadence = Read-JsonFile (Join-Path $outPath "ball-content-cadence.json")
    $ballMotion = Read-JsonFile (Join-Path $outPath "ball-motion-validation.json")
    $tearing = Read-JsonFile (Join-Path $outPath "bidirectional-tearing-validation.json")
    $summary = [PSCustomObject]@{
        cycle = "native-720p30-dmabuf-display-v1"
        plugin_sha256 = $pluginHash
        output_mode = $OutputMode
        pipeline_variant = if ($UseV12Pipeline) { "v12-mmap" } else { "four-slot-dmabuf" }
        dmabuf_device_sync = $dmabufDeviceSync
        verify_output_hash = $verifyOutputHashValue
        trace_frames = $traceFramesValue
        warmup_seconds = $WarmupSeconds
        source_fps = $Fps
        capture_fps = $CaptureFps
        queue = "three-buffer-bounded"
        requested_ball_frames = $Frames
        ball_content_fps = $ballCadence.effective_content_fps
        ball_distinct_content_frames = $ballCadence.distinct_content_frames
        ball_motion_status = $ballMotion.status
        ball_stop_log = $ballStopLog
        tearing_capture_frames = $tearing.mjpeg_frames
        tearing_frames = $tearing.tearing_frames
        tearing_status = $tearing.validator_status
        kernel_health = "ok"
        ethernet_errors_dropped = 0
        result = "pass"
        ball_cadence_report = Join-Path $outPath "ball-content-cadence.json"
        ball_motion_report = Join-Path $outPath "ball-motion-validation.json"
        tearing_report = Join-Path $outPath "bidirectional-tearing-validation.json"
        stop_log = $stopLog
    }
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outPath "summary.json") -Encoding UTF8
    Write-Output "NATIVE_720P30_DMABUF_HDMI_GATE_OK summary=$(Join-Path $outPath 'summary.json')"
} finally {
    foreach ($process in @($ballSender, $stripeSender, $ballCapture, $stripeCapture)) {
        if ($process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    $null = Stop-PcVideoSenders -DestinationIp $BoardIp -DestinationPort $GstPort
    if ($serverJob) {
        Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue
    }
    if ($receiverStarted) {
        try {
            $null = Stop-BoardReceiver
        } catch {
            Write-Warning "failed to stop board receiver during cleanup: $($_.Exception.Message)"
        }
    }
}
