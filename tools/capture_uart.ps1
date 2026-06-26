[CmdletBinding()]
param(
    [string]$Port = "COM16",
    [int]$BaudRate = 115200,
    [int]$DurationSeconds = 10,
    [string]$OutputPath = "build\eth-ps-pl-hdmi-pass-through\hardware\reports\uart_capture.log"
)

$ErrorActionPreference = "Stop"

if ($DurationSeconds -le 0) {
    throw "DurationSeconds must be positive."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$output = Join-Path $repoRoot $OutputPath
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null

$serial = [System.IO.Ports.SerialPort]::new(
    $Port,
    $BaudRate,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)
$serial.ReadTimeout = 200
$deadline = [DateTime]::UtcNow.AddSeconds($DurationSeconds)
$builder = [System.Text.StringBuilder]::new()

try {
    $serial.Open()
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $chunk = $serial.ReadExisting()
            if ($chunk.Length -gt 0) {
                [void]$builder.Append($chunk)
                Write-Host $chunk -NoNewline
            }
        }
        catch [TimeoutException] {
        }
        Start-Sleep -Milliseconds 50
    }
}
finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
    $serial.Dispose()
}

$text = $builder.ToString()
Set-Content -LiteralPath $output -Value $text -NoNewline
Write-Output "UART_CAPTURE_OK path=$output bytes=$($text.Length)"
