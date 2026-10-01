#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$DosStateFile = (Join-Path $env:ProgramData "redhavi\dos-state-win.json"),
    [string]$RedhaviStateFile = (Join-Path $env:ProgramData "redhavi\state-win.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:DosScenarioVersion = 2
$script:CombinedExpectedChecks = 13
$embeddedCheckerPath = Join-Path $env:TEMP "dos-redhavi-checkWin.ps1"
$scriptRootValue = Get-Variable -Name PSScriptRoot -ValueOnly -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace([string]$scriptRootValue)) {
    $scriptRootValue = Get-Variable -Name ScriptRoot -ValueOnly -ErrorAction SilentlyContinue
}
if ([string]::IsNullOrWhiteSpace([string]$scriptRootValue)) {
    $scriptRootValue = (Get-Location).Path
}

$siblingCheckerPath = Join-Path $scriptRootValue "redhavi-checkWin.ps1"
$redhaviCheckerPath = $null
foreach ($candidate in @($siblingCheckerPath, $embeddedCheckerPath)) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        continue
    }
    if (Select-String -LiteralPath $candidate -SimpleMatch "function Assert-LabUserClean" -Quiet) {
        $redhaviCheckerPath = $candidate
        break
    }
}

if (-not $redhaviCheckerPath) {
    Write-Host "[ERROR] A compatible redhavi-checkWin.ps1 was not found beside this checker." -ForegroundColor Red
    $global:LASTEXITCODE = 2
    [Environment]::ExitCode = 2
    return
}

$script:RedhaviCheckLibraryOnly = $true
. $redhaviCheckerPath -StateFile $RedhaviStateFile
$script:AllowIncompleteScenarioState = $true
if ($redhaviCheckerPath -eq $embeddedCheckerPath) {
    Remove-Item -LiteralPath $embeddedCheckerPath -Force -ErrorAction SilentlyContinue
}

function Read-DosScenarioState {
    if (-not (Test-Path -LiteralPath $DosStateFile -PathType Leaf)) {
        Stop-Verification "The DOS state marker $DosStateFile is missing; combined provisioning cannot be confirmed."
    }

    try {
        $state = Get-Content -LiteralPath $DosStateFile -Raw | ConvertFrom-Json
    } catch {
        Stop-Verification "The DOS state marker does not contain valid JSON: $($_.Exception.Message)"
    }

    foreach ($property in @(
        "scenario", "version", "status", "expected_checks", "task_name",
        "executable_path", "redhavi_state_file"
    )) {
        if (-not ($state.PSObject.Properties.Name -contains $property)) {
            Stop-Verification "The DOS state marker is missing the required '$property' field."
        }
    }

    if ($state.scenario -ne "redhavi-dos-win") {
        Stop-Verification "The DOS state marker does not belong to the redhavi-dos-win scenario."
    }
    if ([int]$state.version -ne $script:DosScenarioVersion) {
        Stop-Verification "Incompatible DOS scenario version. Run the updated dos.ps1 again."
    }
    if ($state.status -ne "ready") {
        Stop-Verification "Combined provisioning is marked as incomplete; no points will be awarded."
    }
    if ([int]$state.expected_checks -ne $script:CombinedExpectedChecks) {
        Stop-Verification "The DOS state marker does not declare $($script:CombinedExpectedChecks) checks."
    }
    if ([string]::IsNullOrWhiteSpace([string]$state.task_name)) {
        Stop-Verification "The DOS state marker contains an empty scheduled-task name."
    }
    if ([string]::IsNullOrWhiteSpace([string]$state.executable_path)) {
        Stop-Verification "The DOS state marker contains an empty executable path."
    }
    if ([string]$state.redhavi_state_file -ne $RedhaviStateFile) {
        Stop-Verification "The DOS and Redhavi state paths do not match."
    }

    return $state
}

function Assert-DosScheduledTaskRemoved {
    param([Parameter(Mandatory)][string]$TaskName)

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    } catch {
        Throw-CheckError "Could not query scheduled task ${TaskName}: $($_.Exception.Message)"
    }
    if ($task) {
        throw "scheduled task '$TaskName' still exists"
    }
}

function Assert-DosExecutableRemoved {
    param([Parameter(Mandatory)][string]$ExecutablePath)

    try {
        $exists = Test-Path -LiteralPath $ExecutablePath
    } catch {
        Throw-CheckError "Could not inspect ${ExecutablePath}: $($_.Exception.Message)"
    }
    if ($exists) {
        throw "scoring executable still exists at '$ExecutablePath'"
    }
}

function Invoke-CombinedCheck {
    Assert-RequiredCommands

    $script:ScenarioVersion = 7
    $script:ExpectedChecks = 11
    $StateFile = $RedhaviStateFile
    $redhaviState = Read-ScenarioState
    $dosState = Read-DosScenarioState

    $script:ExpectedChecks = $script:CombinedExpectedChecks
    $script:TotalChecks = 0
    $script:PassedChecks = 0
    $script:FailedChecks = 0
    $script:ErrorChecks = 0

    $indexPath = [string]$redhaviState.index_path
    $authorizedKeys = [string]$redhaviState.authorized_keys
    $rootKeyBlob = [string]$redhaviState.root_key_blob
    $refreshTaskName = [string]$redhaviState.task_name
    $refreshUrl = [string]$redhaviState.refresh_url
    $refreshScript = [string]$redhaviState.refresh_script
    $canaryTaskName = [string]$redhaviState.canary_task_name
    $runKeyPath = [string]$redhaviState.run_key_path
    $runValueName = [string]$redhaviState.run_value_name
    $canaryUrl = [string]$redhaviState.canary_url
    $canaryScript = [string]$redhaviState.canary_script
    $dosTaskName = [string]$dosState.task_name
    $dosExecutablePath = [string]$dosState.executable_path

    Write-Host ""
    Write-Host "=== Combined Redhavi + DOS Windows Cleanup Verification ===" -ForegroundColor Cyan
    Write-Host "Redhavi state: $RedhaviStateFile"
    Write-Host "DOS state:      $DosStateFile"
    if ($redhaviState.status -eq "incomplete") {
        Write-Host "WARNING: Redhavi reached post-validation with one or more seed checks unresolved." -ForegroundColor Yellow
    }
    Write-Host ""

    Invoke-Check "user_ccdc" "ccdc was removed or is disabled without administrative privileges" {
        Assert-LabUserClean "ccdc"
    }
    Invoke-Check "user_splunk" "splunk was removed or is disabled without administrative privileges" {
        Assert-LabUserClean "splunk"
    }
    Invoke-Check "scheduled_task" "the Redhavi persistence task and helper script were removed" {
        Assert-NoRefreshPersistence $refreshTaskName $refreshUrl $indexPath $refreshScript
    }
    Invoke-Check "registry_run" "the registry Run persistence was removed" {
        Assert-NoRegistryPersistence $runKeyPath $runValueName $canaryUrl $canaryScript
    }
    Invoke-Check "canary_task" "the three-minute canary task and script were removed" {
        Assert-NoPeriodicCanary $canaryTaskName $canaryScript
    }
    Invoke-Check "ssh_lab_key" "the exact lab SSH key was removed" {
        Assert-KeyRemoved $authorizedKeys $rootKeyBlob
    }
    Invoke-Check "ssh_readonly" "authorized_keys no longer has the ReadOnly lock" {
        Assert-FileNotReadOnly $authorizedKeys
    }
    Invoke-Check "webshell" "the shell_exec payload was removed" {
        Assert-WebShellRemoved $indexPath
    }
    Invoke-Check "web_readonly" "index.php no longer has the ReadOnly lock" {
        Assert-FileNotReadOnly $indexPath
    }
    Invoke-Check "feature_telnet" "TelnetClient is disabled" {
        Assert-FeatureDisabled "TelnetClient"
    }
    Invoke-Check "feature_tftp" "TFTP is disabled" {
        Assert-FeatureDisabled "TFTP"
    }
    Invoke-Check "dos_task" "the ccdcscoring scheduled task was removed" {
        Assert-DosScheduledTaskRemoved $dosTaskName
    }
    Invoke-Check "dos_executable" "the ccdcscoring executable was removed" {
        Assert-DosExecutableRemoved $dosExecutablePath
    }

    Show-SummaryAndSetResult
}

try {
    Invoke-CombinedCheck
} catch {
    $message = $_.Exception.Message
    if ($message.StartsWith("FATAL::")) {
        $message = $message.Substring(7)
    }
    Write-Host "[ERROR] $message" -ForegroundColor Red
    Set-VerificationResult 2
}
