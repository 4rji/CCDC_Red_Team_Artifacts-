#Requires -Version 5.1

param(
    [string]$OutputPath = ".\Red_team_artifacts.exe"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sourceUrl = "https://raw.githubusercontent.com/4rji/CCDC_Red_Team_Artifacts-/3fe27c94aae17031da4cac9a24d2b2e95a5cd925/redhavi-checkWin.ps1"
$expectedHash = "F9203222A95D37B53BEE89EFE25CF88C90AF9F5B0581CFC762774255C798B327"
$tempSource = Join-Path ([IO.Path]::GetTempPath()) "redhavi-checkWin.ps1"

Install-PackageProvider NuGet -Force | Out-Null
Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
Import-Module ps2exe

try {
    Invoke-WebRequest -Uri $sourceUrl -OutFile $tempSource -UseBasicParsing

    if ((Get-FileHash -LiteralPath $tempSource -Algorithm SHA256).Hash -ne $expectedHash) {
        throw "The downloaded checker failed its SHA-256 integrity check."
    }

    Invoke-ps2exe `
        -inputFile $tempSource `
        -outputFile $OutputPath `
        -x64 `
        -requireAdmin
} finally {
    Remove-Item -LiteralPath $tempSource -Force -ErrorAction SilentlyContinue
}
