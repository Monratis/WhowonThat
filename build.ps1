<#
.SYNOPSIS
    Builds the WhoWonThat addon into a .zip ready to install in World of Warcraft.
.DESCRIPTION
    Reads the version from WhoWonThat.toc, creates the correct WhoWonThat/ folder structure
    and packs it into dist/WhoWonThat-v<version>.zip and dist/WhoWonThat.zip.
#>

param(
    [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Get-Location }

$tocPath = Join-Path $scriptDir "WhoWonThat.toc"
$version = "4.3.0"

if (Test-Path $tocPath) {
    $match = Select-String -Path $tocPath -Pattern '## Version:\s*(.+)' | Select-Object -First 1
    if ($match -and $match.Matches.Groups.Count -gt 1) {
        $version = $match.Matches.Groups[1].Value.Trim()
    }
}

$addonName = "WhoWonThat"
$outDir = Join-Path $scriptDir $OutputDir
$stageDir = Join-Path $outDir $addonName
$versionZip = Join-Path $outDir "$addonName-v$version.zip"
$latestZip = Join-Path $outDir "$addonName.zip"

Write-Host "Building addon $addonName (version $version)..." -ForegroundColor Cyan

# Prepare the output folder
if (Test-Path $stageDir) {
    Remove-Item -Recurse -Force $stageDir
}
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

# Copy the addon files
$filesToInclude = @(
    "WhoWonThat.toc",
    "WhoWonThat.lua",
    "README.md",
    "LICENSE",
    "CHANGELOG.md"
)

foreach ($file in $filesToInclude) {
    $src = Join-Path $scriptDir $file
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $stageDir
        Write-Host "  + $file" -ForegroundColor Gray
    }
}

# Remove old archives
if (Test-Path $versionZip) { Remove-Item -Force $versionZip }
if (Test-Path $latestZip) { Remove-Item -Force $latestZip }

# Create the ZIP with WhoWonThat/ as the root folder
Compress-Archive -Path $stageDir -DestinationPath $versionZip
Copy-Item -Path $versionZip -Destination $latestZip -Force

# Clean up the staging folder
Remove-Item -Recurse -Force $stageDir

Write-Host "`nDone! Created archives for WoW Forever:" -ForegroundColor Green
Write-Host "  - $versionZip" -ForegroundColor Yellow
Write-Host "  - $latestZip" -ForegroundColor Yellow
Write-Host "`nTo install: extract the ZIP directly into:" -ForegroundColor Gray
Write-Host "  <WoW Forever folder>\Interface\AddOns\`n" -ForegroundColor Gray
