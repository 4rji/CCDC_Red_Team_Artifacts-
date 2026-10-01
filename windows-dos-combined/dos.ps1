#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules ScheduledTasks

[CmdletBinding()]
param(
    [uri]$DownloadUrl = "http://172.16.101.73:9988/ccdcscoring.exe",
    [string]$InstallDirectory = (Join-Path $env:ProgramData "CCDC-Lab"),
    [string]$TaskName = "Redhavi-ccdcscoring",
    [ValidateRange(1, 1440)][int]$IntervalMinutes = 3,
    [ValidatePattern("^$|^[A-Fa-f0-9]{64}$")][string]$ExpectedSha256 = "",
    [string]$StateFile = (Join-Path $env:ProgramData "redhavi\dos-state-win.json"),
    [string]$RedhaviStateFile = (Join-Path $env:ProgramData "redhavi\state-win.json"),
    [string]$RedhaviSeederPath = (Join-Path $PSScriptRoot "redhaviwin.ps1"),
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ScenarioVersion = 2
$script:ExpectedChecks = 13
$script:CurrentStep = "startup"
$executablePath = Join-Path $InstallDirectory "ccdcscoring.exe"

function Write-ScenarioState {
    param([Parameter(Mandatory)][ValidateSet("incomplete", "ready")][string]$Status)

    $stateDirectory = Split-Path -Parent $StateFile
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $temporaryState = "$StateFile.$PID.tmp"
    $state = [ordered]@{
        scenario           = "redhavi-dos-win"
        version            = $script:ScenarioVersion
        status             = $Status
        expected_checks    = $script:ExpectedChecks
        step               = $script:CurrentStep
        updated_at         = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        task_name          = $TaskName
        executable_path    = $executablePath
        download_url       = $DownloadUrl.AbsoluteUri
        interval_minutes   = $IntervalMinutes
        redhavi_state_file = $RedhaviStateFile
    }

    try {
        $state | ConvertTo-Json | Set-Content -LiteralPath $temporaryState -Encoding UTF8
        Copy-Item -LiteralPath $temporaryState -Destination $StateFile -Force
    } finally {
        Remove-Item -LiteralPath $temporaryState -Force -ErrorAction SilentlyContinue
    }
}

function Test-RedhaviScenarioUsable {
    if (-not (Test-Path -LiteralPath $RedhaviStateFile -PathType Leaf)) {
        return $false
    }

    try {
        $state = Get-Content -LiteralPath $RedhaviStateFile -Raw | ConvertFrom-Json
        $completedProvisioning = (
            $state.status -eq "ready" -or
            ($state.status -eq "incomplete" -and $state.step -eq "post-validation")
        )
        return (
            $state.scenario -eq "redhavi-win" -and
            [int]$state.version -eq 7 -and
            [int]$state.expected_checks -eq 11 -and
            $completedProvisioning
        )
    } catch {
        return $false
    }
}

function Ensure-RedhaviScenario {
    if (Test-RedhaviScenarioUsable) {
        Write-Host "[ccdcscoring] Existing Redhavi Windows scenario reached post-validation."
        return
    }

    if (-not (Test-Path -LiteralPath $RedhaviSeederPath -PathType Leaf)) {
        throw "The required Redhavi seeder was not found: $RedhaviSeederPath"
    }

    Write-Host "[ccdcscoring] Preparing the complete Redhavi Windows scenario..."
    & $RedhaviSeederPath
    if (-not (Test-RedhaviScenarioUsable)) {
        throw "redhaviwin.ps1 did not reach post-validation."
    }
}

function Test-ScoringTaskReady {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        return $false
    }
    $installedFile = Get-Item -LiteralPath $executablePath
    if ($installedFile.Length -eq 0) {
        return $false
    }
    if ($ExpectedSha256) {
        $installedSha256 = (Get-FileHash -LiteralPath $executablePath -Algorithm SHA256).Hash
        if ($installedSha256 -ne $ExpectedSha256) {
            return $false
        }
    }

    $actionText = ($task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join " "
    return $actionText.Contains($executablePath)
}

function Remove-ScoringTask {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[ccdcscoring] Scheduled task removed: $TaskName"
    }

    if (Test-Path -LiteralPath $executablePath -PathType Leaf) {
        Remove-Item -LiteralPath $executablePath -Force
        Write-Host "[ccdcscoring] Executable removed: $executablePath"
    }
}

function Install-ScoringTask {
    if (Test-ScoringTaskReady) {
        Write-Host "[ccdcscoring] Existing executable and scheduled task passed validation."
        return
    }

    $script:CurrentStep = "payload download"
    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
    $temporaryPath = Join-Path $InstallDirectory "ccdcscoring.exe.download"

    try {
        Write-Host "[ccdcscoring] Downloading $DownloadUrl ..."
        Invoke-WebRequest -UseBasicParsing -Uri $DownloadUrl -OutFile $temporaryPath

        $downloadedFile = Get-Item -LiteralPath $temporaryPath
        if ($downloadedFile.Length -eq 0) {
            throw "The download produced an empty file."
        }

        $actualSha256 = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash
        if ($ExpectedSha256 -and $actualSha256 -ne $ExpectedSha256) {
            throw "Unexpected SHA-256. Expected: $ExpectedSha256; received: $actualSha256"
        }

        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        }
        Copy-Item -LiteralPath $temporaryPath -Destination $executablePath -Force
        Unblock-File -LiteralPath $executablePath -ErrorAction SilentlyContinue
        Write-Host "[ccdcscoring] Installed at $executablePath"
        Write-Host "[ccdcscoring] SHA-256: $actualSha256"
    } finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }

    $script:CurrentStep = "scheduled task"
    $action = New-ScheduledTaskAction `
        -Execute $executablePath `
        -WorkingDirectory $InstallDirectory
    $trigger = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval ([TimeSpan]::FromMinutes($IntervalMinutes)) `
        -RepetitionDuration ([TimeSpan]::FromDays(3650))
    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Description "Runs ccdcscoring.exe every $IntervalMinutes minutes for the Redhavi lab." `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null

    Write-Host "[ccdcscoring] Task created: $TaskName (every $IntervalMinutes minutes as SYSTEM)."
    Write-Host "[ccdcscoring] Approximate first run: $((Get-Date).AddMinutes(1))"

    $script:CurrentStep = "post-validation"
    if (-not (Test-ScoringTaskReady)) {
        throw "The executable or scheduled task did not pass post-validation."
    }
}

if ($Remove) {
    Remove-ScoringTask
} else {
    Write-ScenarioState "incomplete"
    try {
        $script:CurrentStep = "Redhavi Windows provisioning"
        Ensure-RedhaviScenario
        Install-ScoringTask
        $script:CurrentStep = "ready"
        Write-ScenarioState "ready"
        Write-Host "[ccdcscoring] The DOS Windows scenario is ready for the exercise."
    } catch {
        try { Write-ScenarioState "incomplete" } catch { }
        Write-Host "[ccdcscoring][ERROR] Failure during '$($script:CurrentStep)': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
