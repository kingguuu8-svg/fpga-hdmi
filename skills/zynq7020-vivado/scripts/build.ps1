[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BoardProfile,
    [string]$VivadoRoot = "E:\Xilinx\Vivado\2018.3",
    [string]$Example = "led-chaser"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$profile = (Resolve-Path $BoardProfile).Path
$vivado = Join-Path $VivadoRoot "bin\vivado.bat"
$tcl = Join-Path $PSScriptRoot "build.tcl"
$buildRoot = Join-Path $repoRoot "build\$Example"
$tempRoot = Join-Path $repoRoot "build\temp"
$userRoot = Join-Path $repoRoot "build\user"

if (-not (Test-Path -LiteralPath $vivado -PathType Leaf)) {
    throw "Vivado not found at '$vivado'."
}

New-Item -ItemType Directory -Force -Path `
    $buildRoot, $tempRoot, $userRoot, `
    (Join-Path $userRoot "AppData\Roaming"), `
    (Join-Path $userRoot "AppData\Local") | Out-Null

$sandboxVariables = [ordered]@{
    TEMP = $tempRoot
    TMP = $tempRoot
    HOME = $userRoot
    USERPROFILE = $userRoot
    HOMEDRIVE = (Split-Path -Qualifier $userRoot)
    HOMEPATH = $userRoot.Substring(2)
    APPDATA = (Join-Path $userRoot "AppData\Roaming")
    LOCALAPPDATA = (Join-Path $userRoot "AppData\Local")
}
$previousEnvironment = @{}
foreach ($entry in $sandboxVariables.GetEnumerator()) {
    $previousEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable(
        $entry.Key,
        "Process"
    )
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
}

try {
    $stdoutLog = Join-Path $buildRoot "vivado.stdout.log"
    $stderrLog = Join-Path $buildRoot "vivado.stderr.log"
    $process = Start-Process -FilePath $vivado -ArgumentList @(
        "-mode", "batch",
        "-nojournal",
        "-nolog",
        "-source", $tcl,
        "-tclargs", $repoRoot, $profile, $Example, $buildRoot
    ) -WorkingDirectory $repoRoot -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog

    Get-Content -LiteralPath $stdoutLog
    if (Test-Path -LiteralPath $stderrLog) {
        Get-Content -LiteralPath $stderrLog
    }
    if ($process.ExitCode -ne 0) {
        throw "Vivado build failed with exit code $($process.ExitCode)."
    }
}
finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
    }
}

$bitstream = Join-Path $buildRoot "$Example.bit"
if (-not (Test-Path -LiteralPath $bitstream -PathType Leaf)) {
    throw "Vivado completed without producing '$bitstream'."
}
Write-Output $bitstream
