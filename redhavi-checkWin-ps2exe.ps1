#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path $PSScriptRoot "redhavi-checkWin.ps1"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "redhavi-checkWin.exe"),
    [switch]$InstallPs2Exe,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Find-Ps2ExeCompiler {
    $command = Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command
    }

    $module = Get-Module -ListAvailable -Name ps2exe |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($module) {
        Import-Module $module.Path -Force
        return Get-Command Invoke-ps2exe -ErrorAction Stop
    }

    if (-not $InstallPs2Exe) {
        throw "PS2EXE is not installed. Run again with -InstallPs2Exe or install it with: Install-Module ps2exe -Scope CurrentUser"
    }
    if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
        throw "Install-Module is unavailable. Install PowerShellGet and then install the ps2exe module."
    }

    Write-Host "Installing PS2EXE for the current user..." -ForegroundColor Cyan
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber -Confirm:$false
    Import-Module ps2exe -Force
    return Get-Command Invoke-ps2exe -ErrorAction Stop
}

$source = Resolve-FullPath $SourcePath
$output = Resolve-FullPath $OutputPath
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Checker source was not found: $source"
}
if ([IO.Path]::GetExtension($output) -ne ".exe") {
    throw "OutputPath must use the .exe extension."
}
if (Test-Path -LiteralPath $output) {
    if (-not $Force) {
        throw "Output already exists: $output. Use -Force to replace it."
    }
    Remove-Item -LiteralPath $output -Force
}

$outputDirectory = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$compiler = Find-Ps2ExeCompiler
$compileOptions = @{
    inputFile    = $source
    outputFile   = $output
    x64          = $true
    requireAdmin = $true
    title        = "Redhavi Windows Cleanup Verification"
    description  = "Scores cleanup of the Redhavi Windows CCDC lab"
    product      = "Redhavi Windows Checker"
    company      = "4rji"
    version      = "1.0.0.0"
}
if ($compiler.Parameters.ContainsKey("supportOS")) {
    $compileOptions.supportOS = $true
}
if ($compiler.Parameters.ContainsKey("longPaths")) {
    $compileOptions.longPaths = $true
}

Write-Warning "PS2EXE packages PowerShell source and is not cryptographic source protection."
Write-Host "Compiling $source" -ForegroundColor Cyan
& $compiler @compileOptions

if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
    throw "PS2EXE completed without creating the expected output: $output"
}

$hash = Get-FileHash -LiteralPath $output -Algorithm SHA256
Write-Host "Created: $output" -ForegroundColor Green
Write-Host "SHA256:  $($hash.Hash)"
