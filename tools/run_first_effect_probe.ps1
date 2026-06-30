[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$UdpPort = 5005,
    [int]$HttpPort = 8000,
    [int]$CaptureDevice = 1,
    [string]$OutDir = "build\first-board-side-effect"
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
        "rm -f /tmp/fb_video_udp_receiver /tmp/fb_video_udp_receiver.log",
        "wget -q -O /tmp/fb_video_udp_receiver http://$($PcIp):$($HttpPort)/fb_video_udp_receiver",
        "echo '$receiverSha  /tmp/fb_video_udp_receiver' | sha256sum -c -",
        "chmod +x /tmp/fb_video_udp_receiver",
        "/tmp/fb_video_udp_receiver --port $UdpPort --frames 1 --timeout-sec 90 --effect invert > /tmp/fb_video_udp_receiver.log 2>&1 & echo RECEIVER_PID=`$!",
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
        $deployLog -notmatch "VIDEO_UDP_LINUX_RECEIVER_READY.*effect=invert") {
        throw "receiver deploy/start effect markers missing"
    }

    & python (Join-Path $repoRoot "tools\send_video_udp.py") $BoardIp `
        --port $UdpPort `
        --pattern rgb-stripes `
        --frames 1 `
        --start-frame-id 200 `
        --fps 1 `
        --payload 1200 `
        --inter-packet-us 200 |
        Tee-Object -FilePath (Join-Path $outPath "send_rgb_stripes_input.log")
    if ($LASTEXITCODE -ne 0) {
        throw "UDP sender failed"
    }

    $afterCommands = Join-Path $outPath "uart_after_effect_frame.commands"
    @(
        "cat /tmp/fb_video_udp_receiver.log",
        "ifconfig eth0 | grep -E 'RX packets|TX packets|errors|dropped'"
    ) | Set-Content -LiteralPath $afterCommands -Encoding ASCII
    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $afterCommands `
        -InitialReadSeconds 1 `
        -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 2 `
        -OutputPath (Join-Path $OutDir "uart_after_effect_frame.log")

    $afterLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_after_effect_frame.log")
    if ($afterLog -notmatch "VIDEO_UDP_FRAME_WRITTEN frame_id=200.*effect=invert" -or
        $afterLog -notmatch "VIDEO_UDP_RECEIVER_DONE frames=1 skipped=0 packets=1200 dropped=0") {
        throw "effect frame write/done markers missing"
    }

    & python (Join-Path $repoRoot "tools\capture_hdmi.py") `
        --device $CaptureDevice `
        --backend dshow `
        --width 800 `
        --height 600 `
        --frames 45 `
        --save-samples 3 `
        --validation-profile inverted-rgb-stripes `
        --out-dir (Join-Path $OutDir "hdmi-after-invert-effect")
    if ($LASTEXITCODE -ne 0) {
        throw "HDMI inverted effect validation failed"
    }

    Write-Output "FIRST_EFFECT_PROBE_OK out=$outPath"
}
finally {
    if ($serverJob) {
        Stop-Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job $serverJob -Force -ErrorAction SilentlyContinue
    }
}
