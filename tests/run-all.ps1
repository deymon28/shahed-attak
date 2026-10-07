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
    "integration-ballistic-motion"
)

Push-Location $projectRoot
try {
    Write-Output "Running standalone Lua algorithm tests..."
    & lua "tests\test_algorithms.lua" "."
    if ($LASTEXITCODE -ne 0) { throw "Algorithm tests failed." }

    Write-Output "Running standalone Lua runtime-rule tests..."
    & lua "tests\test_runtime_rules.lua" "."
    if ($LASTEXITCODE -ne 0) { throw "Runtime-rule tests failed." }

    & lua "tests\test_air_rules.lua" "."
    if ($LASTEXITCODE -ne 0) { throw "Air-war rules failed." }
    & lua "tests\test_interception_runtime.lua" "."
    if ($LASTEXITCODE -ne 0) { throw "Interceptor runtime failed." }

    & lua "tests\test_abm_modes.lua"
    if ($LASTEXITCODE -ne 0) { throw "ABM target mode tests failed." }
    & lua "tests\test_battery_gui.lua"
    if ($LASTEXITCODE -ne 0) { throw "Battery GUI tests failed." }

    & lua "tests\test_interceptor_motion.lua"
    if ($LASTEXITCODE -ne 0) { throw "Interceptor motion tests failed." }
    & lua "tests\test_interceptor_handoff.lua"
    if ($LASTEXITCODE -ne 0) { throw "Interceptor handoff tests failed." }
    & lua "tests\test_recon_wreck.lua"
    if ($LASTEXITCODE -ne 0) { throw "Recon wreck tests failed." }

    & lua "tests\test_alert_priority.lua"
    if ($LASTEXITCODE -ne 0) { throw "Alert priority tests failed." }

    & lua "tests\test_alert_loop.lua"
    if ($LASTEXITCODE -ne 0) { throw "Alert loop tests failed." }

    & lua "tests\test_visual_effects.lua"
    if ($LASTEXITCODE -ne 0) { throw "Visual effect lifecycle tests failed." }

    Write-Output "Running Python static, visual, audio, locale, and package tests..."
    & python -m pytest "tests\test_static.py" "tests\test_visual_assets.py" "tests\test_structure_shadows.py" "tests\test_audio_assets.py" "tests\test_locale.py" "tests\test_package.py" -q
    if ($LASTEXITCODE -ne 0) { throw "Python test suite failed." }

    Write-Output "Running unpacked Factorio smoke test..."
    & ".\tests\smoke-load.ps1" -FactorioExe $FactorioExe

    foreach ($scenario in $scenarios) {
        Write-Output "Running Factorio scenario: $scenario"
        & ".\tests\integration.ps1" -FactorioExe $FactorioExe -Scenario $scenario -TimeoutSeconds 90
    }

    & ".\tests\integration.ps1" -FactorioExe $FactorioExe -Scenario integration-ordnance-reload -ReloadSave ordnance-fixture -TimeoutSeconds 90
    & ".\tests\integration.ps1" -FactorioExe $FactorioExe -Scenario integration-abm-modes -ReloadSave _autosave-abm-modes-fixture -WithPlayer -TimeoutSeconds 120

    Write-Output "Running baseline save migration tests..."
    & ".\tests\migration.ps1" -FactorioExe $FactorioExe -TimeoutSeconds 90

    & ".\tests\migration.ps1" -FactorioExe $FactorioExe -OldVersion "0.5.0" -TimeoutSeconds 90

    & ".\tests\migration.ps1" -FactorioExe $FactorioExe -OldVersion "0.6.0" -TimeoutSeconds 90

    Write-Output "PASS: Shahed Attack 0.6.7 full verification completed."
}
finally {
    Pop-Location
}
