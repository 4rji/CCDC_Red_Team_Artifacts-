#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules ScheduledTasks

[CmdletBinding()]
param(
    [uri]$DownloadUrl = "http://172.16.101.77:8087/apollo1.exe",
    [string]$InstallDirectory = (Join-Path $env:ProgramData "redhavi"),
    [string]$TaskName = "Redhavi-Apollo1",
    [ValidateRange(1, 1440)][int]$IntervalMinutes = 3,
    [ValidatePattern("^$|^[A-Fa-f0-9]{64}$")][string]$ExpectedSha256 = "",
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$executablePath = Join-Path $InstallDirectory "apollo1.exe"

function Remove-ApolloTask {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[apollo1] Scheduled task removed: $TaskName"
    }

    if (Test-Path -LiteralPath $executablePath -PathType Leaf) {
        Remove-Item -LiteralPath $executablePath -Force
        Write-Host "[apollo1] Executable removed: $executablePath"
    }
}

function Install-ApolloTask {
    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
    $temporaryPath = Join-Path $InstallDirectory "apollo1.exe.download"

    try {
        Write-Host "[apollo1] Downloading $DownloadUrl ..."
        Invoke-WebRequest -UseBasicParsing -Uri $DownloadUrl -OutFile $temporaryPath

        $downloadedFile = Get-Item -LiteralPath $temporaryPath
        if ($downloadedFile.Length -eq 0) {
            throw "The download produced an empty file."
        }

        $actualSha256 = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash
        if ($ExpectedSha256 -and $actualSha256 -ne $ExpectedSha256) {
            throw "Unexpected SHA-256. Expected: $ExpectedSha256; received: $actualSha256"
        }

        Move-Item -LiteralPath $temporaryPath -Destination $executablePath -Force
        Unblock-File -LiteralPath $executablePath -ErrorAction SilentlyContinue
        Write-Host "[apollo1] Installed at $executablePath"
        Write-Host "[apollo1] SHA-256: $actualSha256"
    } finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }

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
        -Description "Runs apollo1.exe every $IntervalMinutes minutes for the Redhavi lab." `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null

    Write-Host "[apollo1] Task created: $TaskName (every $IntervalMinutes minutes as SYSTEM)."
    Write-Host "[apollo1] Approximate first run: $((Get-Date).AddMinutes(1))"
}

if ($Remove) {
    Remove-ApolloTask
} else {
    Install-ApolloTask
}
