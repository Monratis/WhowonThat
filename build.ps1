<#
.SYNOPSIS
    Buduje i paczkuje dodatek WhoWonThat do archiwum .zip gotowego dla World of Warcraft.
.DESCRIPTION
    Skrypt odczytuje wersje z pliku WhoWonThat.toc, tworzy poprawna strukture katalogu
    WhoWonThat/ i pakuje go do plikow dist/WhoWonThat-v<wersja>.zip oraz dist/WhoWonThat.zip.
#>

param(
    [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Get-Location }

$tocPath = Join-Path $scriptDir "WhoWonThat.toc"
$version = "4.0.1"

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

Write-Host "Budowanie dodatku $addonName (wersja $version)..." -ForegroundColor Cyan

# Przygotowanie folderu wyjsciowego
if (Test-Path $stageDir) {
    Remove-Item -Recurse -Force $stageDir
}
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

# Kopiowanie plikow dodatku
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

# Usuwanie starych archiwow
if (Test-Path $versionZip) { Remove-Item -Force $versionZip }
if (Test-Path $latestZip) { Remove-Item -Force $latestZip }

# Tworzenie archiwum ZIP ze sciezka glowna WhoWonThat/...
Compress-Archive -Path $stageDir -DestinationPath $versionZip
Copy-Item -Path $versionZip -Destination $latestZip -Force

# Czyszczenie katalogu staging
Remove-Item -Recurse -Force $stageDir

Write-Host "`nSukces! Utworzono archiwa dla WoW Forever:" -ForegroundColor Green
Write-Host "  - $versionZip" -ForegroundColor Yellow
Write-Host "  - $latestZip" -ForegroundColor Yellow
Write-Host "`nAby zainstalowac: wypakuj zawartosc ZIP bezposrednio do folderu:" -ForegroundColor Gray
Write-Host "  <Katalog WoW Forever>\Interface\AddOns\`n" -ForegroundColor Gray
