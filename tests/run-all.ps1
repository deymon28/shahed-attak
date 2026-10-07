param(
    [string]$FactorioExe = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "factorio-env.ps1")
$FactorioExe = Resolve-FactorioExe $FactorioExe
$readData = Get-FactorioReadData $FactorioExe
$projectRoot = Split-Path -Parent $PSScriptRoot

$scenarios = @(
    "integration-air-war-v5",
    "integration-small-fixes",
    "integration-ground-turrets",
    "integration-natural-sources",
    "integration-distant-flight",
    "integration-test",
    "integration-targeting",
    "integration-force",
    "integration-raid-cap",
    "integration-navigation",
    "integration-formation",
    "integration-recon",
    "integration-flak-accuracy",
    "integration-drone-impact",
    "integration-crash",
    "integration-target-loss",
    "integration-invalid-target",
    "integration-ballistic-flight",
    "integration-alert-delivery",
    "integration-radar-circuit",
    "integration-audio-prototypes",
    "integration-visual-prototypes",
    "integration-launch-handoff",
    "integration-wreck-completion",
    "integration-ballistic-motion",
    "integration-rail-defense"
)

Push-Location $projectRoot
try {
    Write-Output "Running standalone Lua tests..."
    foreach ($test in Get-ChildItem "tests" -Filter "test_*.lua" | Sort-Object Name) {
        & lua $test.FullName "."
        if ($LASTEXITCODE -ne 0) { throw "Lua test failed: $($test.Name)" }
    }

    Write-Output "Checking Lua globals..."
    & python "tools\check_lua_globals.py"
    if ($LASTEXITCODE -ne 0) { throw "Undeclared global check failed." }

    Write-Output "Running Python static, visual, audio, locale, and package tests..."
    & python -m pytest "tests\test_static.py" "tests\test_visual_assets.py" "tests\test_structure_shadows.py" "tests\test_audio_assets.py" "tests\test_locale.py" "tests\test_package.py" -q
    if ($LASTEXITCODE -ne 0) { throw "Python test suite failed." }

    Write-Output "Running unpacked Factorio smoke test..."
    & ".\tests\smoke-load.ps1" -FactorioExe $FactorioExe

    foreach ($scenario in $scenarios) {
        Write-Output "Running Factorio scenario: $scenario"
        & ".\tests\integration.ps1" -FactorioExe $FactorioExe -Scenario $scenario -TimeoutSeconds 120
    }

    & ".\tests\integration.ps1" -FactorioExe $FactorioExe -Scenario integration-ordnance-reload -ReloadSave ordnance-fixture -TimeoutSeconds 90
    & ".\tests\integration.ps1" -FactorioExe $FactorioExe -Scenario integration-abm-modes -ReloadSave _autosave-abm-modes-fixture -WithPlayer -TimeoutSeconds 180
    & ".\tests\integration.ps1" -FactorioExe $FactorioExe -Scenario integration-alert-loop -WithPlayer -TimeoutSeconds 240

    Write-Output "Running baseline save migration tests..."
    & ".\tests\migration.ps1" -FactorioExe $FactorioExe -TimeoutSeconds 90

    & ".\tests\migration.ps1" -FactorioExe $FactorioExe -OldVersion "0.5.0" -TimeoutSeconds 90

    & ".\tests\migration.ps1" -FactorioExe $FactorioExe -OldVersion "0.6.0" -TimeoutSeconds 90

    & ".\tests\migration.ps1" -FactorioExe $FactorioExe -OldVersion "0.6.7" -TimeoutSeconds 120

    Write-Output "PASS: Shahed Attack full verification completed."
}
finally {
    Pop-Location
}
