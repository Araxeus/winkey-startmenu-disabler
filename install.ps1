<#
.SYNOPSIS
    Installs, updates, or uninstalls disable-winkey-startmenu.
.DESCRIPTION
    Default install (needs admin once):
    copies the exe to Program Files and registers a logon task that runs it elevated,
    so it also works while an admin window has focus.

    -NoAdmin install:
    copies the exe to %LOCALAPPDATA%\Programs and adds a Startup shortcut.
    It does not work while an admin window has focus.

    Every download is checked against the digest GitHub reports for the release asset,
    and its build attestation is verified when the GitHub CLI is installed and signed in.
.PARAMETER NoAdmin
    Install for the current user without admin rights.
.PARAMETER Uninstall
    Remove every install of the app. Asks for admin only if the admin install exists.
.PARAMETER ExePath
    Install a local exe instead of the latest release. Skips the digest and attestation checks.
.EXAMPLE
    irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1 | iex
.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1))) -NoAdmin
.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1))) -Uninstall
#>
param(
    [switch]$NoAdmin,
    [switch]$Uninstall,
    [string]$ExePath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo     = 'Araxeus/disable-winkey-startmenu'
$name     = 'disable-winkey-startmenu'
$userDir  = Join-Path $env:LOCALAPPDATA "Programs\$name"
$adminDir = Join-Path $env:ProgramFiles $name
$shortcut = Join-Path ([Environment]::GetFolderPath('Startup')) "$name.lnk"


# Elevated steps. They run in a separate admin process and must not use outside variables.

$adminInstall = {
    param($Source, $Sha256, $User, $Name)

    $ErrorActionPreference = 'Stop'
    $dir = Join-Path $env:ProgramFiles $Name
    $exe = Join-Path $dir "$Name.exe"

    Get-Process $Name -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300

    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item $Source $exe -Force

    # Hash the installed copy, since the user could change the staged file after it was verified.
    if ((Get-FileHash $exe -Algorithm SHA256).Hash -ne $Sha256) {
        Remove-Item $exe -Force
        throw 'The exe changed after it was verified.'
    }

    # Defaults would kill the app after 72 hours, on battery, and run it at below-normal priority.
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -Priority 4

    Register-ScheduledTask -TaskName $Name -Force `
        -Description 'Stops a lone Win key press from opening the Start menu' `
        -Action (New-ScheduledTaskAction -Execute $exe -WorkingDirectory $dir) `
        -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $User) `
        -Principal (New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Highest) `
        -Settings $settings | Out-Null

    Start-ScheduledTask -TaskName $Name
}

$adminUninstall = {
    param($Name)

    $ErrorActionPreference = 'Stop'
    Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction SilentlyContinue
    Get-Process $Name -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300
    Remove-Item (Join-Path $env:ProgramFiles $Name) -Recurse -Force -ErrorAction SilentlyContinue
}


function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Runs a script block as admin, prompting UAC when this session is not elevated.
function Invoke-Admin([scriptblock]$Block, [hashtable]$Arguments) {
    if (Test-Admin) {
        & $Block @Arguments
        return
    }

    $argText = ($Arguments.GetEnumerator() | ForEach-Object {
        "-$($_.Key) '$($_.Value -replace "'", "''")'"
    }) -join ' '

    # On failure the admin window stays open so the error is readable.
    $command = "try { & { $Block } $argText } catch { Write-Host `$_ -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

    $p = Start-Process (Get-Process -Id $PID).Path -Verb RunAs -Wait -PassThru `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
    if ($p.ExitCode -ne 0) { throw 'The admin step failed.' }
}

function Remove-UserInstall {
    # Only stop the per-user copy, so a running admin install is left alone.
    Get-Process $name -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($userDir, 'OrdinalIgnoreCase') } |
        Stop-Process -Force
    Start-Sleep -Milliseconds 300
    Remove-Item $shortcut -ErrorAction SilentlyContinue
    Remove-Item $userDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Returns the path of a verified exe in the temp folder.
function Get-VerifiedExe {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "$name-$([guid]::NewGuid()).exe"

    if ($ExePath) {
        Write-Host "Using local exe $ExePath (skipping release checks)"
        Copy-Item $ExePath $tmp
        return $tmp
    }

    $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
    $asset = $release.assets | Where-Object name -eq "$name.exe"
    if (-not $asset) { throw "Release $($release.tag_name) has no $name.exe asset." }

    Write-Host "Downloading $name $($release.tag_name)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $tmp -UseBasicParsing

    $expected = $asset.digest -replace '^sha256:', ''
    $actual = (Get-FileHash $tmp -Algorithm SHA256).Hash
    if ($actual -ne $expected) {
        Remove-Item $tmp
        throw "Digest mismatch. Expected $expected, got $actual."
    }

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($gh) { gh auth status *> $null }
    if ($gh -and $LASTEXITCODE -eq 0) {
        Write-Host 'Verifying build attestation'
        gh attestation verify $tmp --repo $repo
        if ($LASTEXITCODE -ne 0) {
            Remove-Item $tmp
            throw 'Attestation verification failed.'
        }
    }
    else {
        Write-Host 'GitHub CLI missing or signed out. Skipping attestation check.'
    }

    return $tmp
}


if ($Uninstall) {
    Remove-UserInstall
    if (Test-Path $adminDir) {
        Invoke-Admin $adminUninstall @{ Name = $name }
    }
    Write-Host "Uninstalled $name."
    return
}

if ($NoAdmin -and (Test-Path $adminDir)) {
    throw "The admin install exists. Run with -Uninstall first, or install without -NoAdmin to update it."
}

$exe = Get-VerifiedExe
try {
    if ($NoAdmin) {
        Remove-UserInstall
        New-Item -ItemType Directory -Force $userDir | Out-Null
        $target = Join-Path $userDir "$name.exe"
        Move-Item $exe $target -Force

        $link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
        $link.TargetPath = $target
        $link.WorkingDirectory = $userDir
        $link.Save()

        Start-Process $target
        Write-Host "Installed $name to $userDir and added it to Startup."
    }
    else {
        # Capture the user here, since UAC may elevate as a different admin account.
        Invoke-Admin $adminInstall @{
            Source = $exe
            Sha256 = (Get-FileHash $exe -Algorithm SHA256).Hash
            User   = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            Name   = $name
        }

        # Clear any older per-user install only after the admin install succeeds.
        Remove-UserInstall
        Write-Host "Installed $name to $adminDir with an elevated logon task."
    }
}
finally {
    Remove-Item $exe -ErrorAction SilentlyContinue
}
