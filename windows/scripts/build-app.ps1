# Build (Debug) and run the Clawix Windows app for development.
# Equivalent to macos/scripts/build_app.sh.

[CmdletBinding()]
param(
    [ValidateSet('Debug','Release')] [string] $Configuration = 'Debug',
    [ValidateSet('x64','arm64')] [string] $Platform = 'x64',
    [switch] $Sign,
    [switch] $NoRun
)

$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_emit_version.ps1")

Push-Location $ROOT
try {
    Write-Host "Building Clawix.sln ($Configuration / $Platform)..."
    dotnet build (Join-Path $ROOT "Clawix.sln") -c $Configuration -p:Platform=$Platform | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }

    $appExe = Join-Path $ROOT "Clawix.App\bin\$Platform\$Configuration\net8.0-windows10.0.19041.0\Clawix.exe"
    $bridgedExe = Join-Path $ROOT "Clawix.Bridged\bin\$Configuration\net8.0\clawix-bridged.exe"

    if ($Sign.IsPresent) {
        $thumb = $env:WIN_SIGN_THUMBPRINT
        if ([string]::IsNullOrEmpty($thumb)) { throw "WIN_SIGN_THUMBPRINT not set; source .signing.env first" }
        $tsa = $env:WIN_SIGN_TIMESTAMP_URL
        if ([string]::IsNullOrEmpty($tsa)) { $tsa = "http://timestamp.digicert.com" }
        foreach ($exe in @($appExe, $bridgedExe)) {
            if (Test-Path $exe) {
                signtool sign /sha1 $thumb /tr $tsa /td SHA256 /fd SHA256 $exe
                if ($LASTEXITCODE -ne 0) { throw "signtool failed for $exe" }
            }
        }
    }

    if (-not $NoRun.IsPresent) {
        Write-Host "Launching Clawix..."
        Start-Process -FilePath $appExe
    }
}
finally { Pop-Location }
