param(
    [string]$Blender = $env:BLENDER_EXE,
    [switch]$Force,
    [switch]$Pilot,
    [string]$Kind
)
$ErrorActionPreference = 'Stop'
if (-not $Blender -or -not (Test-Path -LiteralPath $Blender -PathType Leaf)) {
    throw 'Blender executable not found. Set BLENDER_EXE or pass -Blender.'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$renderRoot = Join-Path $projectRoot 'graphics/renders'
New-Item -ItemType Directory -Force -Path $renderRoot | Out-Null
$env:OPTIX_CACHE_PATH = Join-Path $projectRoot 'build/hybrid-overhaul/optix-cache'
$renderArgs = @('--background', '--disable-autoexec', '--python', 'tools/hybrid_scene.py', '--')
if ($Force) { $renderArgs += '--force' }
if ($Pilot) { $renderArgs += '--pilot' }
if ($Kind) { $renderArgs += @('--kind', $Kind) }
$process = Start-Process -FilePath $Blender -ArgumentList $renderArgs -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $renderRoot 'render.log') -RedirectStandardError (Join-Path $renderRoot 'render-error.log')
Write-Output "Blender PID: $($process.Id). Log: $renderRoot/render.log"
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw "Blender failed with exit code $($process.ExitCode). See render-error.log." }
if (-not $Pilot -and -not $Kind) {
    $reconProcess = Start-Process -FilePath $Blender -ArgumentList '--background','--disable-autoexec','--python','tools/render_recon_wreck.py' -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $renderRoot 'recon-wreck.log') -RedirectStandardError (Join-Path $renderRoot 'recon-wreck-error.log')
    $reconProcess.WaitForExit()
    if ($reconProcess.ExitCode -ne 0) { throw 'Recon wreck rendering failed.' }
    $shadowProcess = Start-Process -FilePath $Blender -ArgumentList '--background','--disable-autoexec','--python','tools/render_structure_shadows.py' -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $renderRoot 'structure-shadow.log') -RedirectStandardError (Join-Path $renderRoot 'structure-shadow-error.log')
    $shadowProcess.WaitForExit()
    if ($shadowProcess.ExitCode -ne 0) { throw 'Structure shadow rendering failed.' }
    $anchorProcess = Start-Process -FilePath $Blender -ArgumentList '--background','--disable-autoexec','--python','tools/export_abm_launch.py' -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $renderRoot 'abm-anchors.log') -RedirectStandardError (Join-Path $renderRoot 'abm-anchors-error.log')
    $anchorProcess.WaitForExit()
    if ($anchorProcess.ExitCode -ne 0) { throw 'ABM launch anchor export failed.' }
    Push-Location $projectRoot
    try {
        & python -m tools.check_render_quality --repair --blender $Blender
        if ($LASTEXITCODE -ne 0) { throw 'Rendered material quality check failed.' }
    } finally { Pop-Location }
    & python (Join-Path $PSScriptRoot 'process_assets.py') --root $projectRoot --contact-sheets build/contact-sheets
    if ($LASTEXITCODE -ne 0) { throw 'Asset packing failed.' }
}
