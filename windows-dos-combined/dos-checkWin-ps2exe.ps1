#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path $PSScriptRoot "dos-checkWin.ps1"),
    [string]$RedhaviCheckerPath = (Join-Path $PSScriptRoot "redhavi-checkWin.ps1"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "Dos_team_artifacts.exe"),
    [switch]$Force
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
$resolvedRedhaviChecker = (Resolve-Path -LiteralPath $RedhaviCheckerPath).Path
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutput

if (-not (Select-String -LiteralPath $resolvedSource -SimpleMatch '$script:CombinedExpectedChecks = 13' -Quiet)) {
    throw "The DOS checker source is not the expected 13-check version: $resolvedSource"
}
if (-not (Select-String -LiteralPath $resolvedRedhaviChecker -SimpleMatch 'function Assert-LabUserClean' -Quiet)) {
    throw "The Redhavi checker source is missing the required cleanup functions: $resolvedRedhaviChecker"
}

if (Test-Path -LiteralPath $resolvedOutput) {
    if (-not $Force) {
        throw "Output already exists: $resolvedOutput. Use -Force to replace it."
    }
    Remove-Item -LiteralPath $resolvedOutput -Force
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
Install-PackageProvider NuGet -Force | Out-Null
Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
Import-Module ps2exe

Invoke-ps2exe `
    -inputFile $resolvedSource `
    -outputFile $resolvedOutput `
    -embedFiles @{ "%TEMP%\dos-redhavi-checkWin.ps1" = $resolvedRedhaviChecker } `
    -x64 `
    -requireAdmin

$hash = (Get-FileHash -LiteralPath $resolvedOutput -Algorithm SHA256).Hash
Write-Host "DOS checker executable: $resolvedOutput"
Write-Host "SHA-256: $hash"
