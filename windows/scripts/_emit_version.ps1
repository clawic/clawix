# Reads VERSION + BUILD_NUMBER and emits MarketingVersion + BuildNumber for callers.
# Usage: . scripts/_emit_version.ps1; $env:CLAWIX_VERSION; $env:CLAWIX_BUILD

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
$build = (Get-Content (Join-Path $root "BUILD_NUMBER") -Raw).Trim()

if ([string]::IsNullOrEmpty($version)) { throw "VERSION file empty" }
if ([string]::IsNullOrEmpty($build)) { throw "BUILD_NUMBER file empty" }

$env:CLAWIX_VERSION = $version
$env:CLAWIX_BUILD = $build
Write-Host "Clawix version: $version (build $build)"
