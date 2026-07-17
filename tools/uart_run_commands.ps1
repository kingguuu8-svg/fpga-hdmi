[CmdletBinding()]
param(
    [string]$Port = "COM16",
    [int]$BaudRate = 115200,
    [string[]]$Command = @(),
    [string]$CommandFile = "",
    [int]$InitialReadSeconds = 2,
    [int]$InterCommandDelayMilliseconds = 500,
    [int]$FinalReadSeconds = 5,
    [string]$OutputPath = "build\uart_run_commands.log",
    [switch]$LoginRoot,
    [string]$Password = ""
)

$ErrorActionPreference = "Stop"

function Read-SerialForSeconds {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Ports.SerialPort]$Serial,
        [Parameter(Mandatory = $true)]
        [int]$Seconds,
        [Parameter(Mandatory = $true)]
        [System.Text.StringBuilder]$Builder
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $chunk = $Serial.ReadExisting()
        if ($chunk.Length -gt 0) {
            [void]$Builder.Append($chunk)
            Write-Host $chunk -NoNewline
        }
        Start-Sleep -Milliseconds 100
    }
}

if ($CommandFile -ne "") {
    $Command += Get-Content -LiteralPath $CommandFile
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$output = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
} else {
    Join-Path $repoRoot $OutputPath
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null

$serial = [System.IO.Ports.SerialPort]::new(
    $Port,
    $BaudRate,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)
$serial.ReadTimeout = 200
$builder = [System.Text.StringBuilder]::new()

try {
    $serial.Open()
    Read-SerialForSeconds -Serial $serial -Seconds $InitialReadSeconds -Builder $builder

    if ($LoginRoot) {
        $serial.Write("root`r`n")
        Start-Sleep -Milliseconds 800
        Read-SerialForSeconds -Serial $serial -Seconds 2 -Builder $builder
        if ($Password -ne "") {
            $serial.Write("$Password`r`n")
            Start-Sleep -Milliseconds 800
            Read-SerialForSeconds -Serial $serial -Seconds 2 -Builder $builder
        }
    }

    foreach ($line in $Command) {
        [void]$builder.AppendLine()
        [void]$builder.AppendLine("### UART_CMD: $line")
        $serial.Write("$line`r`n")
        Start-Sleep -Milliseconds $InterCommandDelayMilliseconds
        Read-SerialForSeconds -Serial $serial -Seconds 1 -Builder $builder
    }

    Read-SerialForSeconds -Serial $serial -Seconds $FinalReadSeconds -Builder $builder
}
finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
    $serial.Dispose()
}

$text = $builder.ToString()
Set-Content -LiteralPath $output -Value $text -NoNewline
Write-Output "UART_RUN_COMMANDS_OK path=$output bytes=$($text.Length)"
