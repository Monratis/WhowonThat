<#
.SYNOPSIS
    Checks the addon code: syntax, forgotten imports, load order. Run before every build / deploy.
.DESCRIPTION
    1. luac -p on every file listed in WhoWonThat.toc (syntax).
    2. A global read in one file of a name that is a top-level local of another file = a missing
       `local X = ns.X` import (or a missing export).
    3. tools/loadtest.lua: loads all files in .toc order with a stub of the game API.
    Needs Lua 5.4 (winget install DEVCOM.Lua). Exit code 0 = all good.
#>
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (Get-Command luac -ErrorAction SilentlyContinue)) { throw "luac not found. Install it: winget install DEVCOM.Lua" }

$toc = Join-Path $root "WhoWonThat.toc"
$files = Get-Content $toc | Where-Object { $_ -match '\.lua\s*$' } | ForEach-Object { Join-Path $root $_.Trim() }
$problems = 0

Write-Host "1. Syntax" -ForegroundColor Cyan
foreach ($f in $files) {
    luac -p $f
    if ($LASTEXITCODE -ne 0) { $problems++ }
}

Write-Host "2. Imports (globals that are locals of another file)" -ForegroundColor Cyan
$topLocals = @{}   # name -> file that defines it at the top level
foreach ($f in $files) {
    foreach ($line in Get-Content $f) {
        if ($line -match '^local [\w, ]+ = ns\.') { continue } # an import, not a definition
        if ($line -match '^local function (\w+)') { $topLocals[$Matches[1]] = $f }
        elseif ($line -match '^local ([\w, ]+?)\s*(=|$)') {
            foreach ($n in $Matches[1].Split(',')) { if ($n.Trim() -ne '_') { $topLocals[$n.Trim()] = $f } }
        }
    }
}
foreach ($f in $files) {
    $globals = luac -l -l -p $f | Select-String '_ENV "(\w+)"' -AllMatches |
        ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    foreach ($g in $globals) {
        if ($topLocals.ContainsKey($g) -and $topLocals[$g] -ne $f) {
            Write-Host ("  {0}: uses '{1}' without import (defined in {2})" -f (Split-Path $f -Leaf), $g, (Split-Path $topLocals[$g] -Leaf)) -ForegroundColor Red
            $problems++
        }
    }
}

Write-Host "3. Load test" -ForegroundColor Cyan
Push-Location $root
lua tools/loadtest.lua
if ($LASTEXITCODE -ne 0) { $problems++ }

Write-Host "4. Simulator scenarios (tools/scenarios, run against a fake WoW client)" -ForegroundColor Cyan
lua tools/sim/run.lua
if ($LASTEXITCODE -ne 0) { $problems++ }
Pop-Location

if ($problems -eq 0) { Write-Host "`nAll checks passed." -ForegroundColor Green; exit 0 }
Write-Host "`n$problems problem(s) found." -ForegroundColor Red
exit 1
