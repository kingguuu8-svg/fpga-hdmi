[CmdletBinding()]
param(
    [string]$VivadoRoot = "E:\Xilinx\Vivado\2018.3",
    [string]$SdkRoot = "E:\Xilinx\SDK\2018.3",
    [string]$OutputPath = "build\reports\target-properties.txt"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$output = Join-Path $repoRoot $OutputPath
$tcl = Join-Path $PSScriptRoot "probe-target-properties.tcl"
$hwServer = Join-Path $VivadoRoot "bin\hw_server.bat"
$xsct = Join-Path $SdkRoot "bin\xsct.bat"

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null

$server = Start-Process -FilePath $hwServer -ArgumentList @("-s", "tcp::3121") `
    -WindowStyle Hidden -PassThru
try {
    & $xsct $tcl $output
    if ($LASTEXITCODE -ne 0) {
        throw "XSCT target-property probe failed with exit code $LASTEXITCODE."
    }
    Get-Content -LiteralPath $output
}
finally {
    if (-not $server.HasExited) {
        Stop-Process -Id $server.Id
    }
}

