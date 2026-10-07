param(
    [string]$FactorioExe = "",
    [int]$TimeoutSeconds = 75,
    [string]$OldVersion = "0.4.0"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "factorio-env.ps1")
$FactorioExe = Resolve-FactorioExe $FactorioExe
$readData = Get-FactorioReadData $FactorioExe
$projectRoot = Split-Path -Parent $PSScriptRoot
$fixtureArchive = Join-Path $projectRoot "dist\shahed-attack_$OldVersion.zip"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("shahed-attack-migration-" + [guid]::NewGuid().ToString("N"))
$modsRoot = Join-Path $testRoot "mods"
$oldModRoot = Join-Path $modsRoot "shahed-attack_$OldVersion"
$currentModRoot = Join-Path $modsRoot "shahed-attack"
$configPath = Join-Path $testRoot "config.ini"
$logPath = Join-Path $testRoot "factorio-current.log"
$serverSettingsPath = Join-Path $testRoot "server-settings.json"
$savePath = Join-Path $testRoot "saves\migration-fixture.zip"
$resolvedTemp = [System.IO.Path]::GetFullPath($testRoot)
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$succeeded = $false
$process = $null

if (-not $resolvedTemp.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase) -or
    -not (Split-Path -Leaf $resolvedTemp).StartsWith("shahed-attack-migration-")) {
    throw "Unsafe migration temporary path: $resolvedTemp"
}

function Start-MigrationServer {
    param([string[]]$Arguments)
    return Start-Process -FilePath $FactorioExe -ArgumentList $Arguments -PassThru -WindowStyle Hidden
}

function Wait-ForLogMarker {
    param([string]$Marker)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
        if (Test-Path -LiteralPath $logPath) {
            $text = Get-Content -Raw -LiteralPath $logPath
            if ($text -match "SHAHED_TEST_FAIL|Error MainLoop|InitializationFailed") {
                throw "Migration stage failed. Log: $logPath"
            }
            if ($text.Contains($Marker)) {
                return
            }
        }
        if ($process.HasExited) {
            throw "Factorio exited before marker '$Marker'. Log: $logPath"
        }
    }
    throw "Timed out waiting for '$Marker'. Log: $logPath"
}

try {
    New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $savePath) -Force | Out-Null
    Expand-Archive -LiteralPath $fixtureArchive -DestinationPath $modsRoot -Force
    $scenarioDestination = Join-Path $oldModRoot "scenarios\integration-save-migration"
    New-Item -ItemType Directory -Path (Split-Path -Parent $scenarioDestination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot "scenarios\integration-save-migration") -Destination $scenarioDestination -Recurse -Force

    @{ mods = @(
        @{ name = "base"; enabled = $true },
        @{ name = "shahed-attack"; enabled = $true }
    ) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $modsRoot "mod-list.json") -Encoding UTF8

    $writeData = $testRoot.Replace("\", "/")
    @"
; version=13
[path]
read-data=$readData
write-data=$writeData

[general]
locale=en
"@ | Set-Content -LiteralPath $configPath -Encoding UTF8

    @{
        name = "Shahed Attack Migration Test"
        description = "Local automated migration test"
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

    $port = Get-Random -Minimum 35000 -Maximum 45000
    $process = Start-MigrationServer @(
        "--config", $configPath,
        "--mod-directory", $modsRoot,
        "--start-server-load-scenario", "shahed-attack/integration-save-migration",
        "--server-settings", $serverSettingsPath,
        "--port", $port
    )
    Wait-ForLogMarker "SHAHED_MIGRATION_STAGE1_READY"
    if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) {
        throw "Stage-one save was not created: $savePath"
    }
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }

    $resolvedOld = [System.IO.Path]::GetFullPath($oldModRoot)
    $resolvedMods = [System.IO.Path]::GetFullPath($modsRoot)
    if ((Split-Path -Parent $resolvedOld) -ne $resolvedMods) {
        throw "Unsafe extracted old-mod path: $resolvedOld"
    }
    Remove-Item -LiteralPath $resolvedOld -Recurse -Force
    New-Item -ItemType Directory -Path $currentModRoot -Force | Out-Null
    foreach ($relative in @("info.json", "settings.lua", "data.lua", "data-final-fixes.lua", "control.lua", "prototypes", "scripts", "migrations", "locale", "graphics/entity", "graphics/icons", "sound", "scenarios")) {
        $destination = Join-Path $currentModRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        $sourcePath = if ($relative -eq "info.json") { "info.json.in" } else { $relative }
        Copy-Item -LiteralPath (Join-Path $projectRoot $sourcePath) -Destination $destination -Recurse -Force
    }

    if (Test-Path -LiteralPath $logPath) {
        Remove-Item -LiteralPath $logPath -Force
    }
    $port = Get-Random -Minimum 35000 -Maximum 45000
    $process = Start-MigrationServer @(
        "--config", $configPath,
        "--mod-directory", $modsRoot,
        "--start-server", $savePath,
        "--server-settings", $serverSettingsPath,
        "--port", $port
    )
    Wait-ForLogMarker "SHAHED_TEST_PASS"
    Write-Output "PASS: Shahed Attack $OldVersion to current save migration completed."
    $succeeded = $true
}
finally {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit()
    }
    if ($succeeded -and $resolvedTemp.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith("shahed-attack-migration-")) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    } elseif (-not $succeeded) {
        Write-Output "Migration diagnostics retained at: $testRoot"
    }
}
