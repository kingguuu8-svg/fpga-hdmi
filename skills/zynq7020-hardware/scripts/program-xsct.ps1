[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Bitstream,
    [string]$VivadoRoot = "E:\Xilinx\Vivado\2018.3",
    [string]$SdkRoot = "E:\Xilinx\SDK\2018.3"
)

$ErrorActionPreference = "Stop"
$bit = (Resolve-Path $Bitstream).Path
$hwServer = Join-Path $VivadoRoot "bin\hw_server.bat"
$xsct = Join-Path $SdkRoot "bin\xsct.bat"
$tcl = Join-Path $PSScriptRoot "program-xsct.tcl"

$server = Start-Process -FilePath $hwServer -ArgumentList @("-s", "tcp::3121") `
    -WindowStyle Hidden -PassThru
try {
    & $xsct $tcl $bit
    if ($LASTEXITCODE -ne 0) {
        throw "XSCT programming failed with exit code $LASTEXITCODE."
    }
}
finally {
    if (-not $server.HasExited) {
        Stop-Process -Id $server.Id
    }
}

