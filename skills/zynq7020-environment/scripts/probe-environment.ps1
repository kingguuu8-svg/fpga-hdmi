[CmdletBinding()]
param(
    [string]$VivadoRoot = "E:\Xilinx\Vivado\2018.3",
    [string]$SdkRoot = "E:\Xilinx\SDK\2018.3",
    [string]$OutputPath = "build\reports\environment.json"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$output = Join-Path $repoRoot $OutputPath

$tools = [ordered]@{
    vivado = Join-Path $VivadoRoot "bin\vivado.bat"
    hw_server = Join-Path $VivadoRoot "bin\hw_server.bat"
    xsct = Join-Path $SdkRoot "bin\xsct.bat"
}

foreach ($entry in $tools.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Required tool '$($entry.Key)' not found at '$($entry.Value)'."
    }
}

$versionText = & $tools.vivado -version 2>&1
$versionLine = $versionText -join " "
if ($LASTEXITCODE -ne 0 -or $versionLine -notmatch "Vivado v2018\.3") {
    throw "Expected Vivado 2018.3. Actual output: $versionLine"
}

$usb = Get-PnpDevice -PresentOnly |
    Where-Object {
        $_.InstanceId -match "VID_0403|VID_1443|VID_03FD" -or
        $_.FriendlyName -match "Xilinx|Digilent|JTAG|FTDI"
    } |
    Select-Object Status, Class, FriendlyName, InstanceId

$report = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    repository = $repoRoot
    vivado_version = "2018.3"
    tools = $tools
    usb_devices = @($usb)
}

$parent = Split-Path -Parent $output
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $output -Encoding UTF8
$report | ConvertTo-Json -Depth 5
