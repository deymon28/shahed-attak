param(
    [string]$FactorioExe = "",
    [string]$Scenario = "integration-player-weapons",
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "factorio-env.ps1")
$FactorioExe = Resolve-FactorioExe $FactorioExe
$readData = Get-FactorioReadData $FactorioExe
$env:SteamAppId = "427520"
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("shahed-attack-graphics-" + [guid]::NewGuid().ToString("N"))
$modsRoot = Join-Path $testRoot "mods"
$modRoot = Join-Path $modsRoot "shahed-attack"
$configPath = Join-Path $testRoot "config.ini"
$logPath = Join-Path $testRoot "factorio-current.log"
$serverSettingsPath = Join-Path $testRoot "server-settings.json"
$port = Get-Random -Minimum 35000 -Maximum 45000

New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
$runtimePaths = @("info.json", "settings.lua", "data.lua", "data-final-fixes.lua", "control.lua", "prototypes", "scripts", "migrations", "locale", "graphics/entity", "graphics/icons", "sound", "scenarios")
    foreach ($relative in $runtimePaths) {
        $destination = Join-Path $modRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        $sourcePath = if ($relative -eq "info.json") { "info.json.in" } else { $relative }
        Copy-Item -LiteralPath (Join-Path $projectRoot $sourcePath) -Destination $destination -Recurse -Force
    }

@{
    mods = @(
        @{ name = "base"; enabled = $true },
        @{ name = "shahed-attack"; enabled = $true }
    )
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $modsRoot "mod-list.json") -Encoding UTF8

$writeData = $testRoot.Replace("\", "/")
@"
; version=13
[path]
read-data=$readData
write-data=$writeData

[general]
locale=en

[graphics]
full-screen=false
"@ | Set-Content -LiteralPath $configPath -Encoding UTF8

@{
    name = "Shahed Attack Integration Test"
    description = "Local automated test"
    max_players = 0
    visibility = @{ public = $false; lan = $false }
    username = ""
    password = ""
    token = ""
    game_password = ""
    require_user_verification = $false
    allow_commands = "true"
    auto_pause = $false
    auto_pause_when_players_connect = $false
    autosave_interval = 0
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $serverSettingsPath -Encoding UTF8

$arguments = @(
    "--config", $configPath,
    "--mod-directory", $modsRoot,
    "--load-scenario", "shahed-attack/$Scenario",
    "--window-size", "1600x1000",
    "--disable-audio"
)
$process = Start-Process -FilePath $FactorioExe -ArgumentList $arguments -PassThru -WindowStyle Hidden

try {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $passed = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
        if ($process.HasExited) {
            break
        }
        if (Test-Path -LiteralPath $logPath) {
            $logText = Get-Content -Raw -LiteralPath $logPath
            if ($logText -match "SHAHED_TEST_FAIL|Error MainLoop|non-recoverable error") {
                break
            }
            if ($logText -match "SHAHED_TEST_PASS") {
                $passed = $true
                break
            }
        }
    }

    Write-Output "Integration root: $testRoot"
    if (Test-Path -LiteralPath $logPath) {
        Select-String -LiteralPath $logPath -Pattern "SHAHED_TEST|Error|Checksum for script|Goodbye" |
            Select-Object -Last 100 |
            ForEach-Object { $_.Line }
    }
    if (-not $passed) {
        if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 35 }
        throw "Factorio integration scenario did not reach SHAHED_TEST_PASS."
    }
    $screenshotRoot = Join-Path $testRoot "script-output"
    if (Test-Path -LiteralPath $screenshotRoot) {
        $reviewRoot = Join-Path $projectRoot "build/game-review"
        New-Item -ItemType Directory -Path $reviewRoot -Force | Out-Null
        Get-ChildItem -LiteralPath $screenshotRoot -Filter "*.png" | Copy-Item -Destination $reviewRoot -Force
    }
    Write-Output "PASS: Factorio graphical integration scenario completed."
}
finally {
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
}
