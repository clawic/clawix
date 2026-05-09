# Fail-fast pre-publish check. Scans clawix/windows for any literal that
# must NEVER ship to the public repo. Mirrors macos/scripts/public_hygiene_check.sh.

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $PSScriptRoot

# Forbidden literals are read from the workspace .signing.env so they
# are NEVER hardcoded in this script (listing them here would be a leak).
# Pattern: BUNDLE_ID, APP_SKU, WIN_SIGN_THUMBPRINT, AAD_TENANT_ID,
# APPLE_TEAM_ID, plus generic Apple Team-ID regex.

$workspace = (Resolve-Path (Join-Path $ROOT "..\..")).Path
$signingEnv = Join-Path $workspace ".signing.env"

$forbiddenLiterals = @()
if (Test-Path $signingEnv) {
    Get-Content $signingEnv | ForEach-Object {
        if ($_ -match '^\s*([A-Z_][A-Z0-9_]*)=(.+)$') {
            $name = $Matches[1]
            $value = $Matches[2].Trim('"').Trim("'")
            if ($value.Length -ge 6 -and ($name -in @('BUNDLE_ID','BUNDLE_ID_IOS','APP_SKU','WIN_SIGN_THUMBPRINT','APPLE_TEAM_ID'))) {
                $forbiddenLiterals += $value
            }
        }
    }
}

# Generic Apple Team ID regex (10 uppercase alnum). Matches anything that
# even *looks* like one. Conservative; will catch false positives that
# an engineer can whitelist on review.
$genericPatterns = @('\b[A-Z0-9]{10}\b')

$exitCode = 0
$files = Get-ChildItem -Path $ROOT -Recurse -File `
    | Where-Object { $_.FullName -notmatch '\\(bin|obj|\.git|publish|out|AppPackages)\\' }

foreach ($file in $files) {
    if ($file.Length -gt 5MB) { continue }
    $text = Get-Content -Raw -LiteralPath $file.FullName -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($text)) { continue }

    foreach ($lit in $forbiddenLiterals) {
        if ($text -match [regex]::Escape($lit)) {
            Write-Host "[hygiene] forbidden literal in $($file.FullName)" -ForegroundColor Red
            $exitCode = 1
        }
    }
    # Generic Apple Team ID: only flag inside Xcode project / signing files.
    if ($file.Name -match '\.(pbxproj|entitlements|appxmanifest)$') {
        foreach ($pat in $genericPatterns) {
            if ($text -match $pat) {
                Write-Host "[hygiene] suspicious 10-char ID in $($file.FullName) (set DEVELOPMENT_TEAM via env)" -ForegroundColor Yellow
            }
        }
    }
}

if ($exitCode -ne 0) {
    Write-Host "[hygiene] FAIL" -ForegroundColor Red
    exit 1
}
Write-Host "[hygiene] OK" -ForegroundColor Green
