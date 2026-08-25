param(
    [switch]$Fix
)

# Format + lint + Rojo build + tests -- run before every commit.
# ./scripts/check.ps1 -Fix formats instead of just checking.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root ".tools"

Push-Location $root
try {
    Write-Host "== stylua =="
    if ($Fix) {
        & (Join-Path $tools "stylua.exe") src tests
    } else {
        & (Join-Path $tools "stylua.exe") --check src tests
        if ($LASTEXITCODE -ne 0) { throw "stylua found unformatted files -- run ./scripts/check.ps1 -Fix" }
    }

    Write-Host "== selene =="
    # Only src/ -- tests/ calls Lune-only APIs (@lune/fs, ...) the "roblox"
    # std does not know about and would false-positive on.
    & (Join-Path $tools "selene.exe") src
    if ($LASTEXITCODE -ne 0) { throw "selene found issues" }

    Write-Host "== rojo build =="
    New-Item -ItemType Directory -Force -Path (Join-Path $root ".build") | Out-Null
    & (Join-Path $tools "rojo.exe") build default.project.json -o ".build/TycoonOrbital.rbxlx"
    if ($LASTEXITCODE -ne 0) { throw "rojo build failed" }

    Write-Host "== tests =="
    & (Join-Path $root "scripts\test.ps1")
    if ($LASTEXITCODE -ne 0) { throw "tests failed" }

    Write-Host "All checks passed."
} finally {
    Pop-Location
}
