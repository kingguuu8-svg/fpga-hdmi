[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$HttpPort = 8091,
    [int]$GstPort = 5011,
    [int]$OutputWidth = 800,
    [int]$OutputHeight = 600,
    [int]$InputWidth = 320,
    [int]$InputHeight = 240,
    [int]$Fps = 5,
    [int]$Frames = 60,
    [int]$JpegQuality = 90,
    [string]$CondaEnv = "build\conda-gstreamer-pc",
    [string]$CaptureDevice = "1",
    [string]$CaptureBackend = "dshow",
    [int]$SummaryInterval = 30,
    [int]$CompressedMinPassFrames = 4,
    [string]$ProbeMode = "pl-probe",
    [string]$OutDir = "build\jpegpldec-pl-probe-and-profile",
    [string]$DashboardUrl = "http://127.0.0.1:8765"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
$pluginOut = Join-Path $outPath "plugin"
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

function Invoke-UartCommands {
    param(
        [string[]]$Commands,
        [string]$Label,
        [int]$FinalReadSeconds = 3
    )

    $commandFile = Join-Path $outPath "uart-$Label.commands"
    $logFile = Join-Path $outPath "uart-$Label.log"
    $Commands | Set-Content -LiteralPath $commandFile -Encoding ASCII
    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $commandFile `
        -LoginRoot `
        -Password root `
        -InitialReadSeconds 0 `
        -InterCommandDelayMilliseconds 400 `
        -FinalReadSeconds $FinalReadSeconds `
        -OutputPath (Join-Path $OutDir "uart-$Label.log") | Out-File -LiteralPath (Join-Path $outPath "uart-$Label.runner-output.log") -Encoding UTF8
    if (-not (Test-Path -LiteralPath $logFile)) {
        throw "UART log was not written: $logFile"
    }
    return $logFile
}

function Require-Text {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Label
    )
    $text = Get-Content -Raw -LiteralPath $Path
    if ($text -notmatch $Pattern) {
        throw "$Label missing in $Path"
    }
}

function Start-PcJpegSender {
    $condaPath = Join-Path $repoRoot $CondaEnv
    $stdout = Join-Path $outPath "pc-gstreamer-sender.out.log"
    $stderr = Join-Path $outPath "pc-gstreamer-sender.err.log"
    $args = @(
        "run", "-p", $condaPath,
        "gst-launch-1.0", "-v",
        "videotestsrc", "num-buffers=$Frames", "is-live=true", "pattern=ball", "motion=sweep", "animation-mode=wall-time", "flip=false", "background-color=0xff14354a", "foreground-color=0xffffd166",
        "!", "video/x-raw,format=RGB,width=$InputWidth,height=$InputHeight,framerate=$Fps/1",
        "!", "videoconvert",
        "!", "video/x-raw,format=I420",
        "!", "jpegenc", "quality=$JpegQuality",
        "!", "rtpjpegpay", "pt=26", "mtu=1200",
        "!", "udpsink", "host=$BoardIp", "port=$GstPort", "sync=false", "async=false"
    )
    return Start-Process -FilePath "conda" -ArgumentList $args -WorkingDirectory $repoRoot `
        -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
}

Write-Output "JPEGPLDEC_PL_PROBE_BUILD_START"
& (Join-Path $repoRoot "software\gstreamer\jpegpldec\build-wsl.ps1") -OutDir $pluginOut
if ($LASTEXITCODE -ne 0) {
    throw "jpegpldec build failed"
}

$plugin = Join-Path $pluginOut "libgstjpegpldec.so"
$shaFile = Join-Path $pluginOut "libgstjpegpldec.sha256.txt"
if (-not (Test-Path -LiteralPath $plugin) -or -not (Test-Path -LiteralPath $shaFile)) {
    throw "plugin artifact or sha256 file missing under $pluginOut"
}
$hash = ((Get-Content -LiteralPath $shaFile -TotalCount 1) -split "\s+")[0].ToLowerInvariant()

if ($ProbeMode -match "dma") {
    $dmaOut = Join-Path $outPath "dma-client"
    & (Join-Path $repoRoot "software\kernel\jpegpl_dma_probe\build-wsl.ps1") -OutDir $dmaOut
    if ($LASTEXITCODE -ne 0) {
        throw "jpegpl DMA probe client build failed"
    }
    Copy-Item -LiteralPath (Join-Path $dmaOut "jpegpl_dma_probe.ko") -Destination $pluginOut -Force
    Copy-Item -LiteralPath (Join-Path $dmaOut "jpegpl_dma_probe_test") -Destination $pluginOut -Force
}

$listener = Get-NetTCPConnection -LocalPort $HttpPort -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    throw "TCP port $HttpPort is already listening"
}
$http = Start-Job -ArgumentList $HttpPort,$pluginOut -ScriptBlock {
    param($BindPort, $Root)

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, [int]$BindPort)
    $listener.Start()
    try {
        while ($true) {
            $client = $listener.AcceptTcpClient()
            try {
                $stream = $client.GetStream()
                $buffer = New-Object byte[] 2048
                $read = $stream.Read($buffer, 0, $buffer.Length)
                $request = [System.Text.Encoding]::ASCII.GetString($buffer, 0, [Math]::Max(0, $read))
                $line = ($request -split "`r?`n")[0]
                $parts = $line -split " "
                $name = if ($parts.Length -ge 2) { [System.IO.Path]::GetFileName([Uri]::UnescapeDataString($parts[1].TrimStart("/"))) } else { "" }
                $path = Join-Path $Root $name
                if ($name -and (Test-Path -LiteralPath $path -PathType Leaf)) {
                    $body = [System.IO.File]::ReadAllBytes($path)
                    $headerText = "HTTP/1.0 200 OK`r`nContent-Type: application/octet-stream`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
                    $header = [System.Text.Encoding]::ASCII.GetBytes($headerText)
                    $stream.Write($header, 0, $header.Length)
                    $stream.Write($body, 0, $body.Length)
                    $stream.Flush()
                    Write-Output "JPEGPLDEC_HTTP_SERVED file=$name bytes=$($body.Length)"
                } else {
                    $body = [System.Text.Encoding]::ASCII.GetBytes("not found")
                    $headerText = "HTTP/1.0 404 Not Found`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
                    $header = [System.Text.Encoding]::ASCII.GetBytes($headerText)
                    $stream.Write($header, 0, $header.Length)
                    $stream.Write($body, 0, $body.Length)
                    $stream.Flush()
                    Write-Output "JPEGPLDEC_HTTP_404 file=$name"
                }
            }
            finally {
                $client.Close()
            }
        }
    }
    finally {
        $listener.Stop()
    }
}
$sender = $null
$hdmiCapture = $null
try {
    Set-Content -LiteralPath (Join-Path $outPath "http-server.pid") -Value $http.Id -Encoding ASCII
    Write-Output "JPEGPLDEC_PL_PROBE_HTTP_SERVER job=$($http.Id) port=$HttpPort"
    Start-Sleep -Seconds 1
    $httpProbe = Join-Path $outPath "http-plugin-probe.bin"
    Invoke-WebRequest -Uri "http://127.0.0.1:$($HttpPort)/libgstjpegpldec.so" `
        -UseBasicParsing `
        -TimeoutSec 10 `
        -OutFile $httpProbe
    if ((Get-Item -LiteralPath $httpProbe).Length -le 0) {
        throw "HTTP plugin self-check returned an empty file"
    }

    $deployCommands = @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "mkdir -p /tmp/gst-plugins",
        "rm -f /tmp/gst-plugins/libgstjpegpldec.so /tmp/gst-registry-jpegpldec-profile.bin",
        "wget -O /tmp/gst-plugins/libgstjpegpldec.so http://$($PcIp):$($HttpPort)/libgstjpegpldec.so",
        "sha256sum /tmp/gst-plugins/libgstjpegpldec.so",
        "GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec-profile.bin gst-inspect-1.0 jpegpldec | sed -n '1,140p'",
        "echo JPEGPLDEC_DEPLOY_INSPECT_DONE"
    )
    if ($ProbeMode -match "dma") {
        $deployCommands += @(
            "wget -O /tmp/jpegpl_dma_probe.ko http://$($PcIp):$($HttpPort)/jpegpl_dma_probe.ko",
            "wget -O /tmp/jpegpl_dma_probe_test http://$($PcIp):$($HttpPort)/jpegpl_dma_probe_test",
            "chmod +x /tmp/jpegpl_dma_probe_test",
            "killall gst-launch-1.0 2>/dev/null || true",
            "rmmod jpegpl_dma_probe 2>/dev/null || true",
            "insmod /tmp/jpegpl_dma_probe.ko",
            "ls -l /dev/jpegpl_dma_probe",
            "devmem 0x43c10004 32 0x0; devmem 0x43c10000 32 0x5; devmem 0x43c10000 32 0x1; echo JPEGPL_DMA_PROBE_COUNTERS_RESET",
            "/tmp/jpegpl_dma_probe_test --length 115200",
            "echo JPEGPL_DMA_PROBE_DEPLOY_TEST_DONE"
        )
    }
    $deployLog = Invoke-UartCommands -Label "deploy-inspect" -Commands $deployCommands
    Require-Text -Path $deployLog -Pattern $hash -Label "deployed plugin sha256"
    Require-Text -Path $deployLog -Pattern "backend" -Label "backend property"
    Require-Text -Path $deployLog -Pattern "probe-mode" -Label "probe-mode property"
    Require-Text -Path $deployLog -Pattern "pl-base" -Label "pl-base property"
    Require-Text -Path $deployLog -Pattern "JPEGPLDEC_DEPLOY_INSPECT_DONE" -Label "deploy marker"
    if ($ProbeMode -match "dma") {
        Require-Text -Path $deployLog -Pattern "JPEGPL_DMA_PROBE_TEST_OK length=115200" -Label "full-frame DMA test"
        Require-Text -Path $deployLog -Pattern "JPEGPL_DMA_PROBE_DEPLOY_TEST_DONE" -Label "DMA deploy marker"
    }

    $caps = "application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)JPEG, payload=(int)26"
    $backendArg = if ($ProbeMode -match "compressed") { "backend=pl-compressed-probe " } else { "" }
    $pipeline = "GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec-profile.bin nohup gst-launch-1.0 -v udpsrc port=$GstPort caps=`"$caps`" ! rtpjitterbuffer latency=100 drop-on-latency=true ! rtpjpegdepay ! jpegpldec $($backendArg)probe-mode=$ProbeMode summary-interval=$SummaryInterval ! videoconvert ! videoscale ! video/x-raw,format=BGR,width=$OutputWidth,height=$OutputHeight ! fbdevsink device=/dev/fb0 sync=true > /tmp/gst_jpegpldec_profile.log 2>&1 & echo `$! > /tmp/gst_jpegpldec_profile.pid"
    $dmaResetCommand = if ($ProbeMode -match "dma") {
        "devmem 0x43c10000 32 0x5; devmem 0x43c10000 32 0x1; echo JPEGPL_DMA_PROBE_COUNTERS_RESET"
    } else {
        "true"
    }

    $startLog = Invoke-UartCommands -Label "start-profile" -FinalReadSeconds 3 -Commands @(
        "killall gst-launch-1.0 2>/dev/null || true",
        "rm -f /tmp/gst_jpegpldec_profile.log /tmp/gst_jpegpldec_profile.pid",
        "/tmp/pip_effect_ctl --preset bottom-right >/tmp/jpegpldec_pip_position.log 2>&1 || true",
        "cat /tmp/jpegpldec_pip_position.log 2>/dev/null || true",
        "setterm -cursor off > /dev/`$(cat /sys/class/tty/tty0/active) 2>/dev/null || true",
        $dmaResetCommand,
        $pipeline,
        "sleep 8",
        "echo JPEGPLDEC_PROFILE_RECEIVER_STARTED pid=`$(cat /tmp/gst_jpegpldec_profile.pid 2>/dev/null) log=/tmp/gst_jpegpldec_profile.log",
        "ps | grep gst-launch | grep -v grep || true",
        "tail -n 160 /tmp/gst_jpegpldec_profile.log",
        "echo JPEGPLDEC_PROFILE_RECEIVER_LOG_TAIL_DONE"
    )
    Require-Text -Path $startLog -Pattern "JPEGPLDEC_PROFILE_RECEIVER_STARTED" -Label "receiver start marker"
    if ($ProbeMode -notmatch "dma") {
        Require-Text -Path $startLog -Pattern "JPEGPLDEC_PROFILE frames=" -Label "profile marker"
    }
    if ($ProbeMode -match "pl" -and $ProbeMode -notmatch "dma") {
        Require-Text -Path $startLog -Pattern "JPEGPLDEC_PL_PROBE" -Label "PL probe marker"
    }
    if ($ProbeMode -match "buffer") {
        Require-Text -Path $startLog -Pattern "JPEGPLDEC_BUFFER_PROBE.*result=pass" -Label "buffer probe marker"
    }

    if ($ProbeMode -match "dma") {
        $hdmiCaptureOut = Join-Path $outPath "hdmi-motion-capture"
        Remove-Item -Recurse -Force -LiteralPath $hdmiCaptureOut -ErrorAction SilentlyContinue
        $hdmiCapture = Start-Process -FilePath "python" -ArgumentList @(
            (Join-Path $repoRoot "tools\probe_hdmi_motion_capture.py"),
            "--device", $CaptureDevice,
            "--backend", $CaptureBackend,
            "--width", "$OutputWidth",
            "--height", "$OutputHeight",
            "--frames", "300",
            "--fps", "15",
            "--timeout-sec", "120",
            "--out-dir", $hdmiCaptureOut
        ) -WorkingDirectory $repoRoot -NoNewWindow `
          -RedirectStandardOutput (Join-Path $outPath "hdmi-motion-capture.out.log") `
          -RedirectStandardError (Join-Path $outPath "hdmi-motion-capture.err.log") `
          -PassThru
        Start-Sleep -Seconds 1
        $sender = Start-PcJpegSender
    }

    $probeOut = Join-Path $outPath "dashboard-output-mjpeg-probe"
    $plDmaTransactions = 0
    $plDmaBytes = 0
    if ($ProbeMode -match "dma") {
        $mjpegStatus = "not-run-direct-hdmi"
    } else {
        try {
            & python (Join-Path $repoRoot "tools\probe_mjpeg_stream.py") `
                "$DashboardUrl/api/output-stream.mjpeg" `
                --out-dir $probeOut `
                --frames 60 `
                --min-unique 5 `
                --timeout-sec 20
            if ($LASTEXITCODE -ne 0) {
                throw "output mjpeg probe exited $LASTEXITCODE"
            }
            $mjpegStatus = "pass"
        } catch {
            $mjpegStatus = "skipped_or_failed: $($_.Exception.Message)"
        }
    }

    if ($sender) {
        $senderTimeoutSec = [Math]::Max(30, [int]([Math]::Ceiling($Frames / [Math]::Max(1, $Fps))) + 20)
        if (-not $sender.WaitForExit($senderTimeoutSec * 1000)) {
            Stop-Process -Id $sender.Id -Force -ErrorAction SilentlyContinue
            throw "PC GStreamer sender timed out"
        }
        $sender.Refresh()
        $senderText = Get-Content -Raw -LiteralPath (Join-Path $outPath "pc-gstreamer-sender.out.log")
        if (($null -ne $sender.ExitCode -and $sender.ExitCode -ne 0) -or
            $senderText -notmatch "Got EOS") {
            throw "PC GStreamer sender failed with exit code $($sender.ExitCode)"
        }
        if (-not $hdmiCapture.WaitForExit(120000)) {
            Stop-Process -Id $hdmiCapture.Id -Force -ErrorAction SilentlyContinue
            throw "HDMI motion capture timed out"
        }
        $hdmiCapture.Refresh()
        $hdmiCaptureText = Get-Content -Raw -LiteralPath (Join-Path $outPath "hdmi-motion-capture.out.log")
        if (($null -ne $hdmiCapture.ExitCode -and $hdmiCapture.ExitCode -ne 0) -or
            $hdmiCaptureText -notmatch "HDMI_MOTION_CAPTURE_OK") {
            throw "HDMI motion capture failed with exit code $($hdmiCapture.ExitCode)"
        }
        if ($ProbeMode -notmatch "writeback") {
            & python (Join-Path $repoRoot "tools\validate_hdmi_ball_motion.py") `
                (Join-Path $OutDir "hdmi-motion-capture\*.jpg") `
                --out-json (Join-Path $outPath "hdmi-ball-motion-validation.json") `
                --min-samples 200 `
                --min-unique-hashes 4 `
                --min-frames-with-ball 20 `
                --min-centroid-span 20
            if ($LASTEXITCODE -ne 0) {
                throw "HDMI ball motion validation failed"
            }
        }

        $stopLog = Invoke-UartCommands -Label "stop-dma-probe" -FinalReadSeconds 4 -Commands @(
            "kill `$(cat /tmp/gst_jpegpldec_profile.pid 2>/dev/null) 2>/dev/null || true",
            "sleep 2",
            "cat /tmp/gst_jpegpldec_profile.log",
            "echo PL_DMA_FRAMES=`$(devmem 0x43c10010 32)",
            "echo PL_DMA_BYTES=`$(devmem 0x43c10018 32)",
            "echo PL_DMA_LAST_FRAME_BYTES=`$(devmem 0x43c10024 32)",
            "echo JPEGPLDEC_DMA_PROBE_STREAM_DONE"
        )
        $dmaText = Get-Content -Raw -LiteralPath $stopLog
        $writebackMode = $ProbeMode -match "writeback"
        $compressedMode = $ProbeMode -match "compressed"
        $dmaMarker = if ($compressedMode) { "JPEGPLDEC_COMPRESSED_DMA_PROBE" } elseif ($writebackMode) { "JPEGPLDEC_DMA_WRITEBACK" } else { "JPEGPLDEC_DMA_PROBE" }
        $dmaPassFrames = ([regex]::Matches($dmaText, "$dmaMarker frame=.*result=pass")).Count
        $dmaFailFrames = ([regex]::Matches($dmaText, "$dmaMarker frame=.*result=fail")).Count
        $requiredPassFrames = if ($compressedMode) { [Math]::Min($Frames, $CompressedMinPassFrames) } else { $Frames - 1 }
        if ($dmaPassFrames -lt $requiredPassFrames -or $dmaFailFrames -ne 0) {
            throw "DMA frame probe failed: pass=$dmaPassFrames fail=$dmaFailFrames required=$requiredPassFrames requested=$Frames"
        }
        if ($compressedMode) {
            Require-Text -Path $stopLog -Pattern "JPEGPLDEC_COMPRESSED_DMA_PROBE frame=" -Label "compressed DMA marker"
        } else {
            Require-Text -Path $stopLog -Pattern "JPEGPLDEC_PROFILE frames=$Frames" -Label "logical-frame profile count"
        }
        if ($writebackMode) {
            Require-Text -Path $stopLog -Pattern "JPEGPLDEC_DMA_WRITEBACK_SUMMARY" -Label "DMA writeback summary"
        }
        if ($compressedMode) {
            $plFramesMatch = [regex]::Match($dmaText, "PL_DMA_FRAMES=0x([0-9A-Fa-f]+)")
            $plBytesMatch = [regex]::Match($dmaText, "PL_DMA_BYTES=0x([0-9A-Fa-f]+)")
            if (-not $plFramesMatch.Success -or -not $plBytesMatch.Success) {
                throw "compressed DMA PL counters missing"
            }
            $plFrames = [Convert]::ToInt64($plFramesMatch.Groups[1].Value, 16)
            $plBytes = [Convert]::ToInt64($plBytesMatch.Groups[1].Value, 16)
            if ($plFrames -le 0 -or $plBytes -le 0) {
                throw "compressed DMA PL counters did not advance: frames=$plFrames bytes=$plBytes"
            }
            $plDmaTransactions = $plFrames
            $plDmaBytes = $plBytes
            $chunksPerFrame = 0
            $frameBytes = 0
        } else {
            $frameBytes = [int](($InputWidth * $InputHeight * 3) / 2)
            $dmaChunkBytes = 16380
            $chunksPerFrame = [int][Math]::Ceiling($frameBytes / $dmaChunkBytes)
            $expectedFramesHex = "0x{0:X8}" -f ($Frames * $chunksPerFrame)
            $expectedBytesHex = "0x{0:X8}" -f ($frameBytes * $Frames)
            $lastChunkBytes = $frameBytes % $dmaChunkBytes
            if ($lastChunkBytes -eq 0) {
                $lastChunkBytes = $dmaChunkBytes
            }
            $expectedLastFrameHex = "0x{0:X8}" -f $lastChunkBytes
            Require-Text -Path $stopLog -Pattern "PL_DMA_FRAMES=$expectedFramesHex" -Label "PL frame counter"
            Require-Text -Path $stopLog -Pattern "PL_DMA_BYTES=$expectedBytesHex" -Label "PL byte counter"
            Require-Text -Path $stopLog -Pattern "PL_DMA_LAST_FRAME_BYTES=$expectedLastFrameHex" -Label "PL last-frame byte counter"
            $plDmaTransactions = $Frames * $chunksPerFrame
            $plDmaBytes = $frameBytes * $Frames
        }
        Require-Text -Path $stopLog -Pattern "JPEGPLDEC_DMA_PROBE_STREAM_DONE" -Label "DMA stream marker"
        if ($writebackMode) {
            & python (Join-Path $repoRoot "tools\validate_jpegpldec_buffer_marker.py") `
                $hdmiCaptureOut `
                --out (Join-Path $outPath "dma-writeback-marker-validation.json") `
                --min-frames 200 `
                --min-pass-frames 150
            if ($LASTEXITCODE -ne 0) {
                throw "DMA writeback marker validation failed"
            }
        }
    } else {
        $dmaPassFrames = 0
        $dmaFailFrames = 0
        $stopLog = $null
    }

    if ($ProbeMode -match "buffer" -and $mjpegStatus -eq "pass") {
        & python (Join-Path $repoRoot "tools\validate_jpegpldec_buffer_marker.py") `
            $probeOut `
            --out (Join-Path $outPath "buffer-marker-validation.json") `
            --min-frames 60 `
            --min-pass-frames 50
        if ($LASTEXITCODE -ne 0) {
            throw "buffer marker validation failed"
        }
        $bufferMarkerStatus = "pass"
    } else {
        $bufferMarkerStatus = "not-run"
    }

    $summary = [PSCustomObject]@{
        cycle = if ($ProbeMode -match "compressed") { "jpegpldec-pl-decode-720p30-v0" } elseif ($ProbeMode -match "writeback") { "jpegpldec-pl-returned-buffer-writeback" } elseif ($ProbeMode -match "dma") { "jpegpldec-ps-pl-buffer-datapath-probe" } elseif ($ProbeMode -match "buffer") { "jpegpldec-pl-buffer-datapath-probe" } else { "jpegpldec-pl-probe-and-profile" }
        plugin_sha256 = $hash
        probe_mode = $ProbeMode
        deployed_plugin = "/tmp/gst-plugins/libgstjpegpldec.so"
        receiver_log = "/tmp/gst_jpegpldec_profile.log"
        deploy_log = $deployLog
        start_log = $startLog
        dashboard_output_probe = $mjpegStatus
        buffer_marker_validation = $bufferMarkerStatus
        logical_frames = if ($ProbeMode -match "dma") { $Frames } else { 0 }
        dma_logged_pass_frames = $dmaPassFrames
        dma_fail_frames = $dmaFailFrames
        pl_dma_transactions = $plDmaTransactions
        pl_dma_bytes = $plDmaBytes
        dma_stop_log = $stopLog
        hdmi_motion_validation = if ($ProbeMode -match "dma" -and $ProbeMode -notmatch "writeback") { Join-Path $outPath "hdmi-ball-motion-validation.json" } else { $null }
        dma_writeback_marker_validation = if ($ProbeMode -match "writeback") { Join-Path $outPath "dma-writeback-marker-validation.json" } else { $null }
        result = "pass"
    }
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outPath "summary.json") -Encoding UTF8
    Write-Output "JPEGPLDEC_PL_PROBE_OK summary=$(Join-Path $outPath "summary.json")"
} finally {
    if ($sender -and -not $sender.HasExited) {
        Stop-Process -Id $sender.Id -Force -ErrorAction SilentlyContinue
    }
    if ($hdmiCapture -and -not $hdmiCapture.HasExited) {
        Stop-Process -Id $hdmiCapture.Id -Force -ErrorAction SilentlyContinue
    }
    if ($http) {
        Stop-Job -Job $http -ErrorAction SilentlyContinue
        Remove-Job -Job $http -Force -ErrorAction SilentlyContinue
    }
}
