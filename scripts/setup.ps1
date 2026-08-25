# Downloads Rojo, Lune, Selene and StyLua into .tools/ (git-ignored) so the
# other scripts have something to call, without requiring Rokit to be
# installed globally first. Versions are read from rokit.toml so this script
# and `rokit install` never drift apart -- see DEVELOPMENT.md.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $root ".tools"
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

function Get-PinnedTool([string]$ToolName) {
    $line = Select-String -Path (Join-Path $root "rokit.toml") -Pattern "^$ToolName\s*=\s*`"([^@]+)@([^`"]+)`""
    if (-not $line) {
        throw "No pinned version for '$ToolName' in rokit.toml"
    }
    $m = $line.Matches[0]
    return [PSCustomObject]@{ Repo = $m.Groups[1].Value; Version = $m.Groups[2].Value }
}

function Install-GitHubTool {
    param(
        [string]$ToolName,
        [string]$AssetPattern,
        [string]$ExeName,
        [string]$TagPrefix = "v"
    )

    $exePath = Join-Path $toolsDir $ExeName
    if (Test-Path $exePath) {
        Write-Host "$ToolName already present at $exePath"
        return
    }

    $pin = Get-PinnedTool $ToolName
    $releaseUrl = "https://api.github.com/repos/$($pin.Repo)/releases/tags/$TagPrefix$($pin.Version)"
    Write-Host "Fetching $ToolName $($pin.Version) release metadata..."
    $release = Invoke-RestMethod -Uri $releaseUrl -Headers @{ "User-Agent" = "tycoon-orbital-setup" }

    $asset = $release.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
    if (-not $asset) {
        $available = ($release.assets | ForEach-Object { $_.name }) -join "`n  "
        throw "No asset matching '$AssetPattern' for $ToolName $($pin.Version). Available assets:`n  $available"
    }

    $downloadPath = Join-Path $toolsDir $asset.name
    Write-Host "Downloading $($asset.name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath

    if ($asset.name -like "*.zip") {
        Expand-Archive -Path $downloadPath -DestinationPath $toolsDir -Force
        Remove-Item $downloadPath
    }

    if (-not (Test-Path $exePath)) {
        throw "$ToolName was downloaded but $exePath does not exist after extraction."
    }
    Write-Host "$ToolName installed."
}

Install-GitHubTool -ToolName "rojo"   -AssetPattern "windows-x86_64\.zip$"    -ExeName "rojo.exe"
Install-GitHubTool -ToolName "lune"   -AssetPattern "windows-x86_64\.zip$"    -ExeName "lune.exe"
Install-GitHubTool -ToolName "selene" -AssetPattern "windows\.zip$"           -ExeName "selene.exe" -TagPrefix ""
Install-GitHubTool -ToolName "stylua" -AssetPattern "windows-x86_64\.zip$"    -ExeName "stylua.exe"

Write-Host "Generating Selene's Roblox standard library (roblox.yml)..."
# generate-roblox-std writes roblox.yml directly into the CWD itself -- it is
# not stdout output, so piping it (e.g. through Out-File) races selene's own
# file handle and fails with "used by another process".
Push-Location $root
& (Join-Path $toolsDir "selene.exe") generate-roblox-std
Pop-Location

Write-Host "Writing sourcemap.json..."
& (Join-Path $toolsDir "rojo.exe") sourcemap (Join-Path $root "default.project.json") -o (Join-Path $root "sourcemap.json")

Write-Host "Setup complete. Tools live in .tools/ -- the other scripts call them directly, nothing is added to PATH."
