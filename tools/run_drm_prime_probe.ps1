[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$HttpPort = 8095,
    [string]$OutDir = "build\native-720p30-dmabuf-display-v1\drm-prime-probe"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

& (Join-Path $repoRoot "tools\build_drm_prime_probe.ps1") -OutDir $OutDir
if ($LASTEXITCODE -ne 0) {
    throw "DRM PRIME probe build failed"
}

$serverJob = $null
try {
    $serverJob = Start-Job -ArgumentList $HttpPort, (Join-Path $outPath "drm_prime_probe") -ScriptBlock {
        param($BindPort, $FilePath)
        $listener = [System.Net.Sockets.TcpListener]::new(
            [System.Net.IPAddress]::Any,
            [int]$BindPort
        )
        $listener.Start()
        try {
            $client = $listener.AcceptTcpClient()
            try {
                $stream = $client.GetStream()
                $request = New-Object byte[] 4096
                [void]$stream.Read($request, 0, $request.Length)
                $bytes = [System.IO.File]::ReadAllBytes($FilePath)
                $header = [System.Text.Encoding]::ASCII.GetBytes(
                    "HTTP/1.1 200 OK`r`nContent-Length: $($bytes.Length)`r`n" +
                    "Content-Type: application/octet-stream`r`nConnection: close`r`n`r`n"
                )
                $stream.Write($header, 0, $header.Length)
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            } finally {
                $client.Close()
            }
        } finally {
            $listener.Stop()
        }
    }
    Start-Sleep -Milliseconds 500

    $commandFile = Join-Path $outPath "uart-run.commands"
    $logFile = Join-Path $outPath "uart-run.log"
    @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "wget -q -O /tmp/drm_prime_probe http://$($PcIp):$($HttpPort)/drm_prime_probe",
        "chmod 755 /tmp/drm_prime_probe",
        "LD_LIBRARY_PATH=/usr/lib:/lib /tmp/drm_prime_probe /dev/dri/card0",
        "echo DRM_PRIME_PROBE_RUN_END"
    ) | Set-Content -LiteralPath $commandFile -Encoding ASCII

    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port -CommandFile $commandFile -LoginRoot -Password root `
        -InitialReadSeconds 0 -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 6 -OutputPath (Join-Path $OutDir "uart-run.log") | Out-Null
    if (-not (Test-Path -LiteralPath $logFile)) {
        throw "DRM PRIME probe UART log missing: $logFile"
    }

    $text = Get-Content -Raw -LiteralPath $logFile
    $ok = $text -match "DRM_PRIME_PROBE_OK"
    $summary = [PSCustomObject]@{
        cycle = "native-720p30-dmabuf-display-v1"
        result = if ($ok) { "prime-capability-pass" } else { "prime-capability-fail" }
        uart_log = $logFile
        board_ip = $BoardIp
    }
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outPath "summary.json") -Encoding UTF8
    if (-not $ok) {
        throw "DRM PRIME capability gate failed; see $logFile"
    }
    Write-Output "DRM_PRIME_PROBE_RUN_OK summary=$(Join-Path $outPath 'summary.json')"
} finally {
    if ($serverJob) {
        Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue
    }
}
