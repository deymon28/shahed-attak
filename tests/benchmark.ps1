param(
    [string]$FactorioExe = "",
    # Mod source tree to measure (defaults to this repository). Point it at a
    # checkout of an older version to compare releases on the same world.
    [string]$ModSource = "",
    [int]$Ticks = 3600,
    [int]$Runs = 3
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "factorio-env.ps1")
$FactorioExe = Resolve-FactorioExe $FactorioExe
$readData = Get-FactorioReadData $FactorioExe
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ModSource) { $ModSource = $projectRoot }

$benchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("shahed-attack-benchmark-" + [guid]::NewGuid().ToString("N"))
$modsRoot = Join-Path $benchRoot "mods"
$modRoot = Join-Path $modsRoot "shahed-attack"
$configPath = Join-Path $benchRoot "config.ini"
$logPath = Join-Path $benchRoot "factorio-current.log"
$savePath = Join-Path $benchRoot "saves/benchmark.zip"
New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $benchRoot "saves") -Force | Out-Null

$runtimePaths = @("info.json", "settings.lua", "data.lua", "data-final-fixes.lua", "control.lua", "prototypes", "scripts", "migrations", "locale", "graphics/entity", "graphics/icons", "sound")
foreach ($relative in $runtimePaths) {
    $destination = Join-Path $modRoot $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    $sourcePath = if ($relative -eq "info.json") { "info.json.in" } else { $relative }
    Copy-Item -LiteralPath (Join-Path $ModSource $sourcePath) -Destination $destination -Recurse -Force
}
# The benchmark world comes from this repository for every measured version.
$scenarioTarget = Join-Path $modRoot "scenarios/benchmark-air-war"
New-Item -ItemType Directory -Path $scenarioTarget -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot "scenarios/benchmark-air-war/control.lua") -Destination $scenarioTarget -Force

@{ mods = @(@{ name = "base"; enabled = $true }, @{ name = "shahed-attack"; enabled = $true }) } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $modsRoot "mod-list.json") -Encoding UTF8
$writeData = $benchRoot.Replace("\", "/")
@"
; version=13
[path]
read-data=$readData
write-data=$writeData

[general]
locale=en
"@ | Set-Content -LiteralPath $configPath -Encoding UTF8
$serverSettings = Join-Path $benchRoot "server-settings.json"
@{
    name = "Shahed Attack Benchmark"; description = "Local benchmark"; max_players = 0
    visibility = @{ public = $false; lan = $false }
    username = ""; password = ""; token = ""; game_password = ""
    require_user_verification = $false; allow_commands = "true"
    auto_pause = $false; auto_pause_when_players_connect = $false; autosave_interval = 0
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $serverSettings -Encoding UTF8

# 1. Build the mid-battle save.
$arguments = @("--config", $configPath, "--mod-directory", $modsRoot, "--start-server-load-scenario",
    "shahed-attack/benchmark-air-war", "--server-settings", $serverSettings, "--port", (Get-Random -Minimum 35000 -Maximum 45000))
$process = Start-Process -FilePath $FactorioExe -ArgumentList $arguments -PassThru -WindowStyle Hidden
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(180)
    while ([DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
        Start-Sleep -Milliseconds 500
        if ((Test-Path -LiteralPath $logPath) -and (Get-Content -Raw -LiteralPath $logPath) -match "SHAHED_BENCH_SAVED" -and (Test-Path -LiteralPath $savePath)) {
            Start-Sleep -Seconds 2
            break
        }
    }
}
finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force; $process.WaitForExit() }
}
if (-not (Test-Path -LiteralPath $savePath)) {
    if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 30 }
    throw "Benchmark save was not created."
}
$profile = Select-String -LiteralPath $logPath -Pattern "SHAHED_PROFILE" | ForEach-Object { $_.Line.Trim() }

# 2. Measure.
$benchmarkLog = Join-Path $benchRoot "benchmark.txt"
$arguments = @("--config", $configPath, "--mod-directory", $modsRoot, "--benchmark", $savePath,
    "--benchmark-ticks", $Ticks, "--benchmark-runs", $Runs, "--disable-audio")
Start-Process -FilePath $FactorioExe -ArgumentList $arguments -Wait -WindowStyle Hidden -RedirectStandardOutput $benchmarkLog | Out-Null
$results = Select-String -LiteralPath $benchmarkLog -Pattern "Performed|avg:" | ForEach-Object { $_.Line.Trim() }
Write-Output "Benchmark root: $benchRoot"
Write-Output "Mod source: $ModSource"
$results
$profile
