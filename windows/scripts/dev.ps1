# Dev launcher. Resolves the .app-mode toggle, builds the solution, kills
# any running instance, relaunches with the right env. Mirrors macos/scripts/dev.sh.

[CmdletBinding()]
param(
    [switch] $Real,
    [switch] $Dummy,
    [ValidateSet('Debug','Release')] [string] $Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent $PSScriptRoot
$workspace = (Resolve-Path (Join-Path $ROOT "..\..")).Path

# Resolve mode (priority: flag > .app-mode file > default 'dummy').
$appModeFile = Join-Path $workspace ".app-mode"
$mode = "dummy"
if ($Real.IsPresent)  { $mode = "real" }
elseif ($Dummy.IsPresent) { $mode = "dummy" }
elseif (Test-Path $appModeFile) {
    $raw = (Get-Content $appModeFile -Raw).Trim().ToLowerInvariant()
    if ($raw -in @("real","normal","no-dummy"))   { $mode = "real" }
    elseif ($raw -in @("dummy","fake","mock","demo")) { $mode = "dummy" }
}

# Source .signing.env for WIN_SIGN_* vars when present.
$signingEnv = Join-Path $workspace ".signing.env"
if (Test-Path $signingEnv) {
    Get-Content $signingEnv | ForEach-Object {
        if ($_ -match '^\s*([A-Z_][A-Z0-9_]*)=(.+)$') {
            $name = $Matches[1]; $val = $Matches[2].Trim('"').Trim("'")
            Set-Item -Path "Env:$name" -Value $val
        }
    }
}

if ($mode -eq "dummy") {
    $env:CLAWIX_BACKEND_HOME = Join-Path $workspace "dummy\.codex"
    $env:CLAWIX_DISABLE_BACKEND = "1"
    Write-Host "Mode: dummy"
} else {
    Remove-Item Env:\CLAWIX_BACKEND_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAWIX_DISABLE_BACKEND -ErrorAction SilentlyContinue
    Write-Host "Mode: real"
}

# Kill running instances.
foreach ($proc in @("Clawix","clawix-bridged")) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

& (Join-Path $PSScriptRoot "build-app.ps1") -Configuration $Configuration
