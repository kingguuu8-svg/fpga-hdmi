[CmdletBinding()]
param(
    [string[]]$Ports = @("COM11", "COM12"),
    [int]$BaudRate = 115200,
    [int]$ReadTimeoutMs = 5000
)

$ErrorActionPreference = "Stop"

foreach ($portName in $Ports) {
    $port = [System.IO.Ports.SerialPort]::new(
        $portName,
        $BaudRate,
        [System.IO.Ports.Parity]::None,
        8,
        [System.IO.Ports.StopBits]::One
    )
    $port.ReadTimeout = $ReadTimeoutMs
    try {
        $port.Open()
        $line = $port.ReadLine()
        Write-Output "${portName}: $line"
    }
    catch [System.TimeoutException] {
        Write-Output "${portName}: no line received within ${ReadTimeoutMs}ms"
    }
    catch {
        Write-Output "${portName}: $($_.Exception.Message)"
    }
    finally {
        if ($port.IsOpen) {
            $port.Close()
        }
        $port.Dispose()
    }
}

