#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$StateFile = (Join-Path $env:ProgramData "redhavi\state-win.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Cleanup verifier for systems prepared with redhaviwin.ps1.
# It does not modify the system; it only checks the scenario's exact artifacts.
$script:ScenarioVersion = 7
$script:ExpectedChecks = 11
$script:TotalChecks = 0
$script:PassedChecks = 0
$script:FailedChecks = 0
$script:ErrorChecks = 0

function Write-Ok {
    param([string]$Id, [string]$Message)
    Write-Host ("[OK]    [{0,-20}] {1}" -f $Id, $Message) -ForegroundColor Green
    $script:PassedChecks++
}

function Write-Finding {
    param([string]$Id, [string]$Message)
    Write-Host ("[X]     [{0,-20}] {1}" -f $Id, $Message) -ForegroundColor Red
    $script:FailedChecks++
}

function Write-CheckError {
    param([string]$Id, [string]$Message)
    Write-Host ("[ERROR] [{0,-20}] {1}" -f $Id, $Message) -ForegroundColor Yellow
    $script:ErrorChecks++
}

function Throw-CheckError {
    param([Parameter(Mandatory)][string]$Message)
    throw "INFRA::$Message"
}

function Invoke-Check {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$SuccessMessage,
        [Parameter(Mandatory)][scriptblock]$Test
    )

    $script:TotalChecks++
    try {
        & $Test | Out-Null
        Write-Ok $Id $SuccessMessage
    } catch {
        $message = $_.Exception.Message
        if ($message.StartsWith("INFRA::")) {
            Write-CheckError $Id $message.Substring(7)
        } else {
            Write-Finding $Id $message
        }
    }
}

function Stop-Verification {
    param([Parameter(Mandatory)][string]$Message)
    throw "FATAL::$Message"
}

function Set-VerificationResult {
    param([Parameter(Mandatory)][ValidateSet(0, 1, 2)][int]$Code)
    $global:LASTEXITCODE = $Code
    [Environment]::ExitCode = $Code
}

function Read-ScenarioState {
    if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
        Stop-Verification "The state marker $StateFile is missing; scenario provisioning cannot be confirmed."
    }

    try {
        $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
    } catch {
        Stop-Verification "The state marker does not contain valid JSON: $($_.Exception.Message)"
    }

    $requiredProperties = @(
        "scenario", "version", "status", "expected_checks", "index_path",
        "authorized_keys", "root_key_blob", "task_name", "refresh_url",
        "refresh_script",
        "canary_task_name", "canary_interval",
        "run_key_path", "run_value_name", "canary_url", "canary_script"
    )
    foreach ($property in $requiredProperties) {
        if (-not ($state.PSObject.Properties.Name -contains $property)) {
            Stop-Verification "The state marker is missing the required '$property' field."
        }
    }

    if ($state.scenario -ne "redhavi-win") {
        Stop-Verification "The state marker does not belong to the redhavi-win scenario."
    }
    if ([int]$state.version -ne $script:ScenarioVersion) {
        Stop-Verification "Incompatible scenario version."
    }
    if ($state.status -ne "ready") {
        Stop-Verification "Provisioning is marked as incomplete; no points will be awarded."
    }
    if ([int]$state.expected_checks -ne $script:ExpectedChecks) {
        Stop-Verification "The state marker does not declare $($script:ExpectedChecks) checks."
    }

    return $state
}

function Assert-RequiredCommands {
    foreach ($commandName in @(
        "Get-LocalUser", "Get-LocalGroupMember", "Get-ScheduledTask",
        "Get-WindowsOptionalFeature"
    )) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            Stop-Verification "Required command is unavailable: $commandName"
        }
    }
}

function Get-AdministratorsGroup {
    try {
        $group = Get-CimInstance Win32_Group -Filter "LocalAccount=True AND SID='S-1-5-32-544'" |
            Select-Object -First 1
    } catch {
        Throw-CheckError "Could not query the Administrators group: $($_.Exception.Message)"
    }
    if (-not $group) {
        Throw-CheckError "The Administrators group (S-1-5-32-544) was not found."
    }
    return $group.Name
}

function Assert-LabUserClean {
    param([Parameter(Mandatory)][string]$Name)

    try {
        $user = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    } catch {
        Throw-CheckError "Could not query user ${Name}: $($_.Exception.Message)"
    }
    if (-not $user) {
        return
    }

    $reasons = New-Object System.Collections.Generic.List[string]
    if ($user.Enabled) {
        $reasons.Add("the account is still enabled")
    }

    $administrators = Get-AdministratorsGroup
    try {
        $isAdministrator = [bool](Get-LocalGroupMember -Group $administrators -ErrorAction Stop |
            Where-Object { $_.SID -eq $user.SID })
    } catch {
        Throw-CheckError "Could not query group membership for ${Name}: $($_.Exception.Message)"
    }
    if ($isAdministrator) {
        $reasons.Add("the account is still a member of $administrators")
    }

    if ($reasons.Count -gt 0) {
        throw ($reasons -join "; ")
    }
}

function Assert-NoRefreshPersistence {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$RefreshUrl,
        [Parameter(Mandatory)][string]$IndexPath,
        [Parameter(Mandatory)][string]$RefreshScript
    )

    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop)
    } catch {
        Throw-CheckError "Could not enumerate scheduled tasks: $($_.Exception.Message)"
    }

    $matches = New-Object System.Collections.Generic.List[string]
    foreach ($task in $tasks) {
        $fullName = "$($task.TaskPath)$($task.TaskName)"
        $actionParts = New-Object System.Collections.Generic.List[string]
        foreach ($action in @($task.Actions)) {
            $execute = ""
            $arguments = ""
            if ($action.PSObject.Properties.Name -contains "Execute") {
                $execute = [string]$action.Execute
            }
            if ($action.PSObject.Properties.Name -contains "Arguments") {
                $arguments = [string]$action.Arguments
            }
            $actionParts.Add("$execute $arguments")
        }
        $actionText = $actionParts -join " "
        $isNamedTask = $task.TaskName -eq $TaskName
        $hasScenarioAction = (
            $actionText.Contains($RefreshScript) -or
            ($actionText.Contains($RefreshUrl) -and $actionText.Contains($IndexPath))
        )
        if ($isNamedTask -or $hasScenarioAction) {
            $matches.Add("task:$fullName")
        }
    }

    if (Test-Path -LiteralPath $RefreshScript) {
        $matches.Add("file:$RefreshScript")
    }

    if ($matches.Count -gt 0) {
        throw "persistence was found in: $($matches -join ', ')"
    }
}

function Assert-NoRegistryPersistence {
    param(
        [Parameter(Mandatory)][string]$KeyPath,
        [Parameter(Mandatory)][string]$ValueName,
        [Parameter(Mandatory)][string]$CanaryUrl,
        [Parameter(Mandatory)][string]$CanaryScript
    )

    $matches = New-Object System.Collections.Generic.List[string]
    if (Test-Path -Path $KeyPath) {
        try {
            $properties = Get-ItemProperty -Path $KeyPath -ErrorAction Stop
        } catch {
            Throw-CheckError "Could not inspect registry key ${KeyPath}: $($_.Exception.Message)"
        }

        foreach ($property in $properties.PSObject.Properties) {
            if ($property.Name -like "PS*") {
                continue
            }
            $value = [string]$property.Value
            $isNamedValue = $property.Name -eq $ValueName
            $hasScenarioAction = $value.Contains($CanaryScript) -or $value.Contains($CanaryUrl)
            if ($isNamedValue -or $hasScenarioAction) {
                $matches.Add($property.Name)
            }
        }
    }

    if ($matches.Count -gt 0) {
        throw "registry persistence was found in ${KeyPath}: $($matches -join ', ')"
    }
}

function Assert-NoPeriodicCanary {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$CanaryScript
    )

    $matches = New-Object System.Collections.Generic.List[string]
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop)
    } catch {
        Throw-CheckError "Could not enumerate scheduled tasks: $($_.Exception.Message)"
    }
    foreach ($task in $tasks) {
        $actionText = ($task.Actions | ForEach-Object {
            $execute = if ($_.PSObject.Properties.Name -contains "Execute") { [string]$_.Execute } else { "" }
            $arguments = if ($_.PSObject.Properties.Name -contains "Arguments") { [string]$_.Arguments } else { "" }
            "$execute $arguments"
        }) -join " "
        if ($task.TaskName -eq $TaskName -or $actionText.Contains($CanaryScript)) {
            $matches.Add("task:$($task.TaskPath)$($task.TaskName)")
        }
    }
    if (Test-Path -LiteralPath $CanaryScript) {
        $matches.Add("file:$CanaryScript")
    }
    if ($matches.Count -gt 0) {
        throw "periodic canary artifacts were found: $($matches -join ', ')"
    }
}

function Assert-KeyRemoved {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Blob
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Throw-CheckError "$Path exists but is not a file."
    }

    try {
        foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
            $tokens = @($line.Trim() -split "\s+")
            if ($tokens -contains $Blob) {
                throw "the exact lab SSH key is still present"
            }
        }
    } catch {
        if ($_.Exception.Message -eq "the exact lab SSH key is still present") {
            throw
        }
        Throw-CheckError "Could not read ${Path}: $($_.Exception.Message)"
    }
}

function Assert-FileNotReadOnly {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        Throw-CheckError "Could not inspect ${Path}: $($_.Exception.Message)"
    }
    if ([bool]($item.Attributes -band [IO.FileAttributes]::ReadOnly)) {
        throw "$Path still has the ReadOnly attribute"
    }
}

function Assert-WebShellRemoved {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Throw-CheckError "$Path exists but is not a file."
    }
    try {
        if (Select-String -LiteralPath $Path -SimpleMatch "shell_exec" -Quiet -ErrorAction Stop) {
            throw "shell_exec is still present in $Path"
        }
    } catch {
        if ($_.Exception.Message.StartsWith("shell_exec is still present")) {
            throw
        }
        Throw-CheckError "Could not inspect ${Path}: $($_.Exception.Message)"
    }
}

function Assert-FeatureDisabled {
    param([Parameter(Mandatory)][string]$Name)

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop
    } catch {
        Throw-CheckError "Could not query the $Name feature: $($_.Exception.Message)"
    }
    if ($feature.State -eq "Enabled" -or $feature.State -eq "EnablePending") {
        throw "the optional $Name feature is still enabled"
    }
}

function Show-SummaryAndSetResult {
    if ($script:TotalChecks -ne $script:ExpectedChecks) {
        Stop-Verification "Internal error: $($script:TotalChecks) checks ran; expected $($script:ExpectedChecks)."
    }

    $percentage = [int](100 * $script:PassedChecks / $script:ExpectedChecks)
    Write-Host ""
    Write-Host "=== FINAL RESULT ===" -ForegroundColor Cyan
    Write-Host "Total:       $($script:TotalChecks)"
    Write-Host "Passed:      $($script:PassedChecks)"
    Write-Host "Remaining:   $($script:FailedChecks)"
    Write-Host "Errors:      $($script:ErrorChecks)"
    Write-Host "Score:       $percentage%"
    Write-Host ""

    if ($script:ErrorChecks -gt 0) {
        Write-Host "Verification encountered infrastructure errors." -ForegroundColor Yellow
        Set-VerificationResult 2
        return
    }
    if ($script:FailedChecks -gt 0) {
        Write-Host "The system still contains scenario artifacts." -ForegroundColor Red
        Set-VerificationResult 1
        return
    }

    Write-Host "The system is completely clean." -ForegroundColor Green
    Set-VerificationResult 0
}

function Invoke-RedhaviCheck {
    Assert-RequiredCommands
    $state = Read-ScenarioState
    $indexPath = [string]$state.index_path
    $authorizedKeys = [string]$state.authorized_keys
    $rootKeyBlob = [string]$state.root_key_blob
    $taskName = [string]$state.task_name
    $refreshUrl = [string]$state.refresh_url
    $refreshScript = [string]$state.refresh_script
    $canaryTaskName = [string]$state.canary_task_name
    $runKeyPath = [string]$state.run_key_path
    $runValueName = [string]$state.run_value_name
    $canaryUrl = [string]$state.canary_url
    $canaryScript = [string]$state.canary_script

    Write-Host ""
    Write-Host "=== Redhavi Windows Cleanup Verification ===" -ForegroundColor Cyan
    Write-Host "State marker: $StateFile"
    Write-Host ""

    Invoke-Check "user_ccdc" "ccdc was removed or is disabled without administrative privileges" {
        Assert-LabUserClean "ccdc"
    }
    Invoke-Check "user_splunk" "splunk was removed or is disabled without administrative privileges" {
        Assert-LabUserClean "splunk"
    }
    Invoke-Check "scheduled_task" "the persistence task and helper script were removed" {
        Assert-NoRefreshPersistence $taskName $refreshUrl $indexPath $refreshScript
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

    Show-SummaryAndSetResult
}

try {
    Invoke-RedhaviCheck
} catch {
    $message = $_.Exception.Message
    if ($message.StartsWith("FATAL::")) {
        $message = $message.Substring(7)
    }
    Write-Host "[ERROR] $message" -ForegroundColor Red
    Set-VerificationResult 2
}
