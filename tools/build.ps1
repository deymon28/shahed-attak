param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) "dist")
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$metadata = Get-Content -Raw -LiteralPath (Join-Path $projectRoot "info.json.in") | ConvertFrom-Json
$folderName = "$($metadata.name)_$($metadata.version)"
$archiveName = "$folderName.zip"
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("shahed-attack-build-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $temporaryRoot $folderName
$resolvedTemp = [System.IO.Path]::GetFullPath($temporaryRoot)
$systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())

$files = @(
    "info.json",
    "settings.lua",
    "data.lua",
    "data-final-fixes.lua",
    "control.lua",
    "README.md",
    "changelog.txt",
    "LICENSE",
    "ASSET_LICENSES.md",
    "thumbnail.png"
)
$directories = @("prototypes", "scripts", "migrations", "locale", "graphics/entity", "graphics/icons", "sound")

try {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    foreach ($relativePath in $files) {
        $sourcePath = if ($relativePath -eq "info.json") { "info.json.in" } else { $relativePath }
        Copy-Item -LiteralPath (Join-Path $projectRoot $sourcePath) -Destination (Join-Path $packageRoot $relativePath) -Force
    }
    foreach ($relativePath in $directories) {
        $destination = Join-Path $packageRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot $relativePath) -Destination $destination -Recurse -Force
    }

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $archivePath = Join-Path $OutputDirectory $archiveName
    $temporaryArchive = Join-Path $temporaryRoot $archiveName
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $temporaryArchive -CompressionLevel Optimal
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Move-Item -LiteralPath $temporaryArchive -Destination $archivePath
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Output "Built: $archivePath"
    Write-Output "SHA256: $hash"
}
finally {
    if ($resolvedTemp.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith("shahed-attack-build-")) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
