#Requires -Version 5.1
<#
.SYNOPSIS
    tokscale CLI - Intune remediation script (Windows equivalent of Jamf policy script)
.DESCRIPTION
    Submits tokscale usage data for the currently logged-in console user.
    Deploy via Intune Proactive Remediations or SCCM package.
#>

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$TokscaleExe = Join-Path $ScriptDir 'tokscale.exe'

# Version and script metadata
$Version = try { & $TokscaleExe --version 2>$null | ForEach-Object { ($_ -split ' ')[1] } } catch { 'unknown' }
$ScriptDate = (Get-Item $MyInvocation.MyCommand.Definition).LastWriteTime.ToString('yyyy-MM-dd')
Write-Output "[tokscale-submit v${Version} / ${ScriptDate}]"

# Detect currently logged-in console user (equivalent of macOS scutil ConsoleUser)
$ConsoleUser = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
if (-not $ConsoleUser) {
    Write-Error 'No console user detected'
    exit 1
}

# Strip DOMAIN\ prefix if present
$UserName = $ConsoleUser -replace '^[^\\]+\\', ''

if (-not $UserName -or $UserName -eq 'SYSTEM') {
    Write-Error "No interactive user detected (got: $ConsoleUser)"
    exit 1
}

# Resolve user profile path
$UserProfile = (Get-CimInstance -ClassName Win32_UserProfile |
    Where-Object { $_.LocalPath -like "*\$UserName" } |
    Select-Object -First 1).LocalPath

if (-not $UserProfile) {
    $UserProfile = "C:\Users\$UserName"
}

if (-not (Test-Path $UserProfile)) {
    Write-Error "User profile not found: $UserProfile"
    exit 1
}

# Set environment for tokscale
$env:TOKSCALE_API_URL = 'https://tokscale.tmobiweb.com'
$env:TOKSCALE_API_TOKEN = "tt_${UserName}"
$env:HOME = $UserProfile
$env:USERPROFILE = $UserProfile

# Execute as the logged-in user via scheduled task (Intune runs as SYSTEM)
$TaskName = "tokscale-submit-$UserName"
$Principal = New-ScheduledTaskPrincipal -UserId $ConsoleUser -LogonType Interactive -RunLevel Limited
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Clean up any previous instance
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

# Build command with environment variables baked in (ScheduledTask runs in a clean env)
$CmdArgs = "/c `"set TOKSCALE_API_URL=https://tokscale.tmobiweb.com && set TOKSCALE_API_TOKEN=tt_${UserName} && set HOME=${UserProfile} && set USERPROFILE=${UserProfile} && `"${TokscaleExe}`" submit --no-spinner`""
$Action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument $CmdArgs -WorkingDirectory $ScriptDir

Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Settings $Settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

# Wait for completion (max 5 minutes)
$Timeout = 300
$Elapsed = 0
do {
    Start-Sleep -Seconds 2
    $Elapsed += 2
    $Running = (Get-ScheduledTask -TaskName $TaskName).State -eq 'Running'
} while ($Running -and $Elapsed -lt $Timeout)

# Collect result
$TaskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
$ExitCode = $TaskInfo.LastTaskResult

# Cleanup
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

if ($ExitCode -ne 0) {
    Write-Error "tokscale submit failed with exit code: $ExitCode"
    exit $ExitCode
}

Write-Output "tokscale submit completed successfully for user: $UserName"
exit 0
