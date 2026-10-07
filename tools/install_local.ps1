param()
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$modsRoot = [IO.Path]::GetFullPath((Split-Path -Parent $projectRoot))
$metadata = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'info.json.in') | ConvertFrom-Json
if ($metadata.name -ne 'shahed-attack') { throw 'Unexpected mod identity' }
$installedRoot = [IO.Path]::GetFullPath((Join-Path $modsRoot 'shahed-attack'))
$expectedMods = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Factorio/mods'))
if ($modsRoot -ne $expectedMods -or (Split-Path -Parent $installedRoot) -ne $modsRoot) {
    throw "Unexpected installation directory: $installedRoot"
}
if ((Get-Item -LiteralPath $installedRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'Refusing to replace a linked installation directory'
}
$archive = Join-Path $projectRoot "dist/shahed-attack_$($metadata.version).zip"
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot "build/backups/pre-$($metadata.version)-$stamp"))
$stageRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot "build/install-stage-$stamp"))
$backupInstallation = [IO.Path]::GetFullPath((Join-Path $backupRoot 'shahed-attack'))
$stageInstallation = [IO.Path]::GetFullPath((Join-Path $stageRoot "shahed-attack_$($metadata.version)"))
foreach ($path in @($backupRoot, $stageRoot, $backupInstallation, $stageInstallation)) {
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe workspace staging path: $path"
    }
}
function Get-TreeHashes([string]$Root) {
    $hashes = @{}
    Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($Root.TrimEnd('\', '/').Length + 1).Replace('\', '/')
        $hashes[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $hashes
}
function Assert-SameHashes($Expected, $Actual, [string]$Label) {
    if ($Expected.Count -ne $Actual.Count) { throw "$Label file count differs" }
    foreach ($key in $Expected.Keys) {
        if ($Expected[$key] -ne $Actual[$key]) { throw "$Label hash differs: $key" }
    }
}
New-Item -ItemType Directory -Path $backupRoot, $stageRoot | Out-Null
$oldVersion = (Get-Content -Raw -LiteralPath (Join-Path $installedRoot 'info.json') | ConvertFrom-Json).version
$oldHashes = Get-TreeHashes $installedRoot
$settingHashes = @{}
foreach ($name in @('mod-list.json', 'mod-settings.dat')) {
    $path = Join-Path $modsRoot $name
    $settingHashes[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Copy-Item -LiteralPath $path -Destination (Join-Path $backupRoot $name)
}
Expand-Archive -LiteralPath $archive -DestinationPath $stageRoot
$newHashes = Get-TreeHashes $stageInstallation
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try { $archiveFiles = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') }).Count } finally { $zip.Dispose() }
if ($newHashes.Count -ne $archiveFiles) { throw 'Extracted file count differs from the archive; inspect package before installation' }
$movedOld = $false
try {
    # Absolute source/destination paths have been validated above.
    Move-Item -LiteralPath $installedRoot -Destination $backupInstallation
    $movedOld = $true
    Assert-SameHashes $oldHashes (Get-TreeHashes $backupInstallation) 'Backup'
    Move-Item -LiteralPath $stageInstallation -Destination $installedRoot
    Assert-SameHashes $newHashes (Get-TreeHashes $installedRoot) 'Installed release'
    foreach ($name in $settingHashes.Keys) {
        $actual = (Get-FileHash -LiteralPath (Join-Path $modsRoot $name) -Algorithm SHA256).Hash
        if ($actual -ne $settingHashes[$name]) { throw "Settings changed during installation: $name" }
    }
} catch {
    if ($movedOld -and -not (Test-Path -LiteralPath $installedRoot) -and (Test-Path -LiteralPath $backupInstallation)) {
        Move-Item -LiteralPath $backupInstallation -Destination $installedRoot
    }
    throw
}
$report = @{
    old_version = $oldVersion; new_version = $metadata.version
    installed_directory = $installedRoot; backup_directory = $backupRoot
    archive = $archive; archive_sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    backup_files = $oldHashes; installed_files = $newHashes; unchanged_settings = $settingHashes
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupRoot 'backup-manifest.json') -Encoding utf8
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $projectRoot 'build/installation.json') -Encoding utf8
Write-Output "Installed $($metadata.version): $installedRoot"
Write-Output "Verified backup of $oldVersion`: $backupRoot"
Write-Output "Verified $($newHashes.Count) runtime files; mod list and settings are byte-identical."
