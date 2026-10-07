param(
    [string]$FactorioExe = "",
    [string]$PackagePath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "factorio-env.ps1")
$FactorioExe = Resolve-FactorioExe $FactorioExe
$readData = Get-FactorioReadData $FactorioExe
$projectRoot = Split-Path -Parent $PSScriptRoot
$smokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("shahed-attack-smoke-" + [guid]::NewGuid().ToString("N"))
$modsRoot = Join-Path $smokeRoot "mods"
$modRoot = Join-Path $modsRoot "shahed-attack"
$savePath = Join-Path $smokeRoot "smoke-test.zip"
$logPath = Join-Path $smokeRoot "factorio-current.log"
$configPath = Join-Path $smokeRoot "config.ini"

New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null
if ($PackagePath) {
    Copy-Item -LiteralPath $PackagePath -Destination (Join-Path $modsRoot (Split-Path -Leaf $PackagePath)) -Force
}
else {
    New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
    $runtimePaths = @("info.json", "settings.lua", "data.lua", "data-final-fixes.lua", "control.lua", "prototypes", "scripts", "migrations", "locale", "graphics/entity", "graphics/icons", "sound", "scenarios")
    foreach ($relative in $runtimePaths) {
        $destination = Join-Path $modRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        $sourcePath = if ($relative -eq "info.json") { "info.json.in" } else { $relative }
        Copy-Item -LiteralPath (Join-Path $projectRoot $sourcePath) -Destination $destination -Recurse -Force
    }
}

$modList = @{
    mods = @(
        @{ name = "base"; enabled = $true },
        @{ name = "shahed-attack"; enabled = $true }
    )
} | ConvertTo-Json -Depth 4
Set-Content -LiteralPath (Join-Path $modsRoot "mod-list.json") -Value $modList -Encoding UTF8

$writeData = $smokeRoot.Replace("\", "/")
$config = @"
; version=13
[path]
read-data=$readData
write-data=$writeData

[general]
locale=en
"@
Set-Content -LiteralPath $configPath -Value $config -Encoding UTF8

$arguments = @(
    "--config", $configPath,
    "--mod-directory", $modsRoot,
    "--create", $savePath
)
$process = Start-Process -FilePath $FactorioExe -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden

Write-Output "Smoke root: $smokeRoot"
if (Test-Path -LiteralPath $logPath) {
    Select-String -LiteralPath $logPath -Pattern "Factorio 2|Loading mod shahed-attack|Checksum of shahed-attack|Error|Goodbye" |
        Select-Object -Last 100 |
        ForEach-Object { $_.Line }
}

$hasFactorioError = $false
if (Test-Path -LiteralPath $logPath) {
    $hasFactorioError = [bool](Select-String -LiteralPath $logPath -Pattern "Error Util.cpp" -Quiet)
}
if ($process.ExitCode -ne 0 -or $hasFactorioError -or -not (Test-Path -LiteralPath $savePath)) {
    throw "Factorio smoke load failed. See $logPath"
}

Write-Output "PASS: Factorio created a save with shahed-attack enabled."
