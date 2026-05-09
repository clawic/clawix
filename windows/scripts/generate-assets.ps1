# Generate Windows app assets from clawix/brand/icon.svg.
# Requires ImageMagick on PATH (`magick.exe`). Idempotent: safe to run
# before every release build.

[CmdletBinding()]
param(
    [string] $Source,
    [string] $Out
)

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrEmpty($Source)) {
    $brand = (Resolve-Path (Join-Path $ROOT "..\brand")).Path
    $candidates = @("icon.svg","clawix.svg","logo.svg") | ForEach-Object { Join-Path $brand $_ }
    $Source = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $Source) { throw "Could not find brand SVG. Pass -Source <path>." }
}
if ([string]::IsNullOrEmpty($Out)) { $Out = Join-Path $ROOT "Clawix.App\Assets" }

New-Item -ItemType Directory -Force -Path $Out | Out-Null

$magick = (Get-Command magick.exe -ErrorAction SilentlyContinue) ??
          (Get-Command magick -ErrorAction SilentlyContinue) ??
          (Get-Command convert -ErrorAction SilentlyContinue)
if (-not $magick) { throw "ImageMagick not found on PATH (install from https://imagemagick.org)." }

function Render($size, $name) {
    & $magick.Source -background none -density 384 $Source `
        -resize "${size}x${size}" -quality 95 (Join-Path $Out $name)
}

Render 256 "Square150x150Logo.png" # also serves as Square150x150
Render 150 "Square150x150Logo.png"
Render 44  "Square44x44Logo.png"
Render 50  "StoreLogo.png"

# Wide tile is 310x150, padded.
& $magick.Source -size 310x150 xc:none `
    `( $Source -background none -density 384 -resize 120x120 `) -gravity Center -composite `
    (Join-Path $Out "Wide310x150Logo.png")

# Splash 620x300, centered.
& $magick.Source -size 620x300 xc:none `
    `( $Source -background none -density 384 -resize 256x256 `) -gravity Center -composite `
    (Join-Path $Out "SplashScreen.png")

# Multi-resolution .ico for the EXE (referenced by Clawix.App.csproj).
& $magick.Source -background none -density 384 $Source `
    -define icon:auto-resize="256,128,64,48,32,16" (Join-Path $Out "Clawix.ico")

Write-Host "Assets generated under $Out"
