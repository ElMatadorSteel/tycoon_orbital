# Runs the whole spec suite, or only the specs whose path contains <filter>.
# Usage: ./scripts/test.ps1 [filter]

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$lune = Join-Path $root ".tools\lune.exe"

Push-Location $root
try {
    if ($args.Count -gt 0) {
        & $lune run tests/run.luau $args[0]
    } else {
        & $lune run tests/run.luau
    }
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
