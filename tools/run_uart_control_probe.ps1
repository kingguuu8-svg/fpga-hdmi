[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$UdpPort = 5005,
    [int]$HttpPort = 8000,
    [int]$CaptureDevice = 1,
    [string]$ControlFifo = "/tmp/video_ctl",
    [string]$OutDir = "build\uart-control-endpoint"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

& (Join-Path $repoRoot "software\eth_pass_through\scripts\build-linux-receiver-wsl.ps1") -OutDir $OutDir
if ($LASTEXITCODE -ne 0) {
    throw "receiver build failed"
}

$shaLine = Get-Content -LiteralPath (Join-Path $outPath "fb_video_udp_receiver.sha256.txt") | Select-Object -First 1
$receiverSha = ($shaLine -split "\s+")[0]

$listener = Get-NetTCPConnection -LocalPort $HttpPort -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    throw "TCP port $HttpPort is already listening"
}

$receiverPath = Join-Path $outPath "fb_video_udp_receiver"
$serverJob = Start-Job -ArgumentList $PcIp,$HttpPort,$receiverPath -ScriptBlock {
    param($BindIp, $BindPort, $FilePath)

    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Parse($BindIp),
        [int]$BindPort
    )
    $listener.Start()
    try {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $buffer = New-Object byte[] 4096
            [void]$stream.Read($buffer, 0, $buffer.Length)
            $body = [System.IO.File]::ReadAllBytes($FilePath)
            $headerText = "HTTP/1.0 200 OK`r`nContent-Type: application/octet-stream`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
            $header = [System.Text.Encoding]::ASCII.GetBytes($headerText)
            $stream.Write($header, 0, $header.Length)
            $stream.Write($body, 0, $body.Length)
            $stream.Flush()
            Write-Output "ONE_SHOT_HTTP_SERVED bytes=$($body.Length)"
        }
        finally {
            $client.Close()
        }
    }
    finally {
        $listener.Stop()
    }
}

try {
    Start-Sleep -Seconds 1

    $deployCommands = Join-Path $outPath "uart_deploy_start_receiver.commands"
    @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "rm -f /tmp/fb_video_udp_receiver /tmp/fb_video_udp_receiver.log $ControlFifo",
        "wget -q -O /tmp/fb_video_udp_receiver http://$($PcIp):$($HttpPort)/fb_video_udp_receiver",
        "echo '$receiverSha  /tmp/fb_video_udp_receiver' | sha256sum -c -",
        "chmod +x /tmp/fb_video_udp_receiver",
        "/tmp/fb_video_udp_receiver --port $UdpPort --frames 1 --timeout-sec 120 --control-fifo $ControlFifo > /tmp/fb_video_udp_receiver.log 2>&1 & echo RECEIVER_PID=`$!",
        "sleep 1",
        "cat /tmp/fb_video_udp_receiver.log"
    ) | Set-Content -LiteralPath $deployCommands -Encoding ASCII

    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $deployCommands `
        -InitialReadSeconds 1 `
        -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 2 `
        -OutputPath (Join-Path $OutDir "uart_deploy_start_receiver.log")

    Receive-Job $serverJob -Wait -AutoRemoveJob | Tee-Object -FilePath (Join-Path $outPath "one-shot-http-server.log")
    $serverJob = $null

    $deployLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_deploy_start_receiver.log")
    if ($deployLog -notmatch "/tmp/fb_video_udp_receiver: OK" -or
        $deployLog -notmatch "CONTROL_FIFO_READY" -or
        $deployLog -notmatch "VIDEO_UDP_LINUX_RECEIVER_READY") {
        throw "receiver deploy/start markers missing"
    }

    $pauseCommands = Join-Path $outPath "uart_pause.commands"
    @(
        "echo pause > $ControlFifo",
        "sleep 1",
        "cat /tmp/fb_video_udp_receiver.log"
    ) | Set-Content -LiteralPath $pauseCommands -Encoding ASCII
    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $pauseCommands `
        -InitialReadSeconds 1 `
        -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 2 `
        -OutputPath (Join-Path $OutDir "uart_pause.log")

    $pauseLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_pause.log")
    if ($pauseLog -notmatch "CONTROL_PAUSED") {
        throw "CONTROL_PAUSED marker missing"
    }

    & python (Join-Path $repoRoot "tools\send_video_udp.py") $BoardIp `
        --port $UdpPort `
        --pattern rgb-stripes `
        --frames 1 `
        --start-frame-id 100 `
        --fps 1 `
        --payload 1200 `
        --inter-packet-us 200 |
        Tee-Object -FilePath (Join-Path $outPath "send_paused_frame.log")
    if ($LASTEXITCODE -ne 0) {
        throw "paused UDP sender failed"
    }

    $afterPauseCommands = Join-Path $outPath "uart_after_paused_frame.commands"
    @(
        "cat /tmp/fb_video_udp_receiver.log"
    ) | Set-Content -LiteralPath $afterPauseCommands -Encoding ASCII
    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $afterPauseCommands `
        -InitialReadSeconds 1 `
        -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 2 `
        -OutputPath (Join-Path $OutDir "uart_after_paused_frame.log")

    $afterPauseLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_after_paused_frame.log")
    if ($afterPauseLog -notmatch "VIDEO_UDP_FRAME_SKIPPED_PAUSED frame_id=100") {
        throw "paused-frame skip marker missing"
    }

    $resumeCommands = Join-Path $outPath "uart_resume_status.commands"
    @(
        "echo resume > $ControlFifo",
        "sleep 1",
        "echo status > $ControlFifo",
        "sleep 1",
        "cat /tmp/fb_video_udp_receiver.log"
    ) | Set-Content -LiteralPath $resumeCommands -Encoding ASCII
    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $resumeCommands `
        -InitialReadSeconds 1 `
        -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 2 `
        -OutputPath (Join-Path $OutDir "uart_resume_status.log")

    $resumeLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_resume_status.log")
    if ($resumeLog -notmatch "CONTROL_RESUMED" -or $resumeLog -notmatch "CONTROL_STATUS paused=0") {
        throw "resume/status markers missing"
    }

    & python (Join-Path $repoRoot "tools\send_video_udp.py") $BoardIp `
        --port $UdpPort `
        --pattern rgb-stripes `
        --frames 1 `
        --start-frame-id 101 `
        --fps 1 `
        --payload 1200 `
        --inter-packet-us 200 |
        Tee-Object -FilePath (Join-Path $outPath "send_resumed_frame.log")
    if ($LASTEXITCODE -ne 0) {
        throw "resumed UDP sender failed"
    }

    $finalCommands = Join-Path $outPath "uart_final.commands"
    @(
        "cat /tmp/fb_video_udp_receiver.log",
        "ifconfig eth0 | grep -E 'RX packets|TX packets|errors|dropped'"
    ) | Set-Content -LiteralPath $finalCommands -Encoding ASCII
    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $finalCommands `
        -InitialReadSeconds 1 `
        -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 2 `
        -OutputPath (Join-Path $OutDir "uart_final.log")

    $finalLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_final.log")
    if ($finalLog -notmatch "VIDEO_UDP_FRAME_WRITTEN frame_id=101" -or
        $finalLog -notmatch "VIDEO_UDP_RECEIVER_DONE frames=1 skipped=1 packets=2400 dropped=0") {
        throw "final write/done markers missing"
    }

    & python (Join-Path $repoRoot "tools\capture_hdmi.py") `
        --device $CaptureDevice `
        --backend dshow `
        --width 800 `
        --height 600 `
        --frames 45 `
        --save-samples 3 `
        --validation-profile rgb-stripes `
        --out-dir (Join-Path $OutDir "hdmi-after-uart-control")
    if ($LASTEXITCODE -ne 0) {
        throw "HDMI capture validation failed"
    }

    Write-Output "UART_CONTROL_PROBE_OK out=$outPath"
}
finally {
    if ($serverJob) {
        Stop-Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job $serverJob -Force -ErrorAction SilentlyContinue
    }
}
