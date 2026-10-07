# Shared Factorio location helpers for the test scripts.
# Set FACTORIO_EXE to the game executable (for example <Factorio>/bin/x64/factorio.exe).
# FACTORIO_DATA optionally overrides the read-data directory; by default it is
# derived from the executable location.

function Resolve-FactorioExe([string]$Requested) {
    $candidate = if ($Requested) { $Requested } elseif ($env:FACTORIO_EXE) { $env:FACTORIO_EXE } else { "" }
    if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Factorio executable not found. Set the FACTORIO_EXE environment variable or pass -FactorioExe."
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Get-FactorioReadData([string]$FactorioExe) {
    if ($env:FACTORIO_DATA) {
        return $env:FACTORIO_DATA.Replace("\", "/")
    }
    $installRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $FactorioExe))
    return (Join-Path $installRoot "data").Replace("\", "/")
}
