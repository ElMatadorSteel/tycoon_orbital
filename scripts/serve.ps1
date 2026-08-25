# Serves the project to Roblox Studio via the Rojo plugin (Rojo -> Connect).
# NOT yet used to connect to the live Tycoon Orbital place -- see CLAUDE.md's
# "Migration status".

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$rojo = Join-Path $root ".tools\rojo.exe"

Push-Location $root
try {
    & $rojo serve default.project.json
} finally {
    Pop-Location
}
