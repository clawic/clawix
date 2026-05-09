# Build a signed release MSIX + appcast entry. Read RELEASE_WINDOWS.md
# in the workspace root before running with --no-dry-run.

[CmdletBinding()]
param(
    [switch] $DryRun,
    [ValidateSet('x64','arm64')] [string] $Platform = 'x64'
)

$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent $PSScriptRoot
$workspace = (Resolve-Path (Join-Path $ROOT "..\..\..")).Path

. (Join-Path $PSScriptRoot "_emit_version.ps1")
& (Join-Path $PSScriptRoot "public_hygiene_check.ps1")

$thumb = $env:WIN_SIGN_THUMBPRINT
if ([string]::IsNullOrEmpty($thumb)) { throw "WIN_SIGN_THUMBPRINT not set; source .signing.env first" }

$publishDir = Join-Path $ROOT "publish\$Platform"
if (Test-Path $publishDir) { Remove-Item -Recurse -Force $publishDir }
New-Item -ItemType Directory -Force -Path $publishDir | Out-Null

dotnet publish (Join-Path $ROOT "Clawix.App\Clawix.App.csproj") `
    -c Release -r "win-$Platform" --self-contained false `
    -o $publishDir -p:Platform=$Platform | Out-Host
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

dotnet publish (Join-Path $ROOT "Clawix.Bridged\Clawix.Bridged.csproj") `
    -c Release -r "win-$Platform" --self-contained false `
    -o (Join-Path $publishDir "bridged") | Out-Host
if ($LASTEXITCODE -ne 0) { throw "dotnet publish (bridged) failed" }

# Sign all binaries.
$tsa = $env:WIN_SIGN_TIMESTAMP_URL
if ([string]::IsNullOrEmpty($tsa)) { $tsa = "http://timestamp.digicert.com" }
foreach ($exe in (Get-ChildItem $publishDir -Recurse -Filter "*.exe")) {
    signtool sign /sha1 $thumb /tr $tsa /td SHA256 /fd SHA256 $exe.FullName | Out-Host
}

if ($DryRun.IsPresent) {
    Write-Host "[release] dry run only. Artifacts in $publishDir"
    exit 0
}

# Pack MSIX
$msix = Join-Path $ROOT "publish\Clawix-Setup.msix"
makeappx pack /d $publishDir /p $msix /o | Out-Host
if ($LASTEXITCODE -ne 0) { throw "makeappx failed" }
signtool sign /sha1 $thumb /tr $tsa /td SHA256 /fd SHA256 $msix

Write-Host "[release] MSIX ready: $msix"
Write-Host "[release] Update appcast.xml with sparkle:os=`"windows`" enclosure pointing here."
