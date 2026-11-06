<#
.SYNOPSIS
    Installs, updates, or uninstalls disable-winkey-startmenu.
.DESCRIPTION
    Default install (needs admin once):
    copies the exe to Program Files and registers a scheduled task that runs it elevated,
    so it also works while an admin window has focus.

    -NoAdmin install:
    copies the exe to %LOCALAPPDATA%\Programs. It does not work while an admin window has focus.

    Both modes add a Start menu shortcut, a startup entry you can toggle in Task Manager,
    and an entry in Settings > Apps that uninstalls it.

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

$repo        = 'Araxeus/disable-winkey-startmenu'
$name        = 'disable-winkey-startmenu'
$displayName = 'Disable WinKey Start Menu'

$userDir      = Join-Path $env:LOCALAPPDATA "Programs\$name"
$adminDir     = Join-Path $env:ProgramFiles $name
$menuShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) "$displayName.lnk"

$uninstallPath = "Software\Microsoft\Windows\CurrentVersion\Uninstall\$name"
$runKey        = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$approvedKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'


# These blocks may run in a separate admin process, so they use only their parameters.
# Invoke-Admin defines $installFiles in that process.

# Copies the exe and its uninstaller into $Dir and registers the Settings > Apps entry.
# Returns the installed exe path.
$installFiles = {
    param($Exe, $ExeSha256, $Script, $ScriptSha256, $Dir, $UninstallKey, $Name)

    $ErrorActionPreference = 'Stop'
    New-Item -ItemType Directory -Force $Dir | Out-Null

    $targetExe = Join-Path $Dir "$Name.exe"
    $targetScript = Join-Path $Dir 'uninstall.ps1'
    Copy-Item $Exe $targetExe -Force
    Copy-Item $Script $targetScript -Force

    # Hash the installed copies, since the staged files could change after they were verified.
    if ((Get-FileHash $targetExe -Algorithm SHA256).Hash -ne $ExeSha256 -or
        (Get-FileHash $targetScript -Algorithm SHA256).Hash -ne $ScriptSha256) {
        Remove-Item $targetExe, $targetScript -Force
        throw 'A file changed after it was verified.'
    }

    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $uninstallCmd = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$targetScript`" -Uninstall"

    New-Item $UninstallKey -Force | Out-Null
    $strings = @{
        DisplayName          = 'Disable WinKey Start Menu'
        DisplayVersion       = (Get-Item $targetExe).VersionInfo.ProductVersion
        Publisher            = 'Araxeus'
        DisplayIcon          = $targetExe
        InstallLocation      = $Dir
        UninstallString      = $uninstallCmd
        QuietUninstallString = $uninstallCmd
        URLInfoAbout         = 'https://github.com/Araxeus/disable-winkey-startmenu'
    }
    foreach ($kv in $strings.GetEnumerator()) {
        New-ItemProperty $UninstallKey -Name $kv.Key -Value $kv.Value -PropertyType String -Force | Out-Null
    }
    $dwords = @{
        NoModify      = 1
        NoRepair      = 1
        EstimatedSize = [int]((Get-Item $targetExe).Length / 1KB)
    }
    foreach ($kv in $dwords.GetEnumerator()) {
        New-ItemProperty $UninstallKey -Name $kv.Key -Value $kv.Value -PropertyType DWord -Force | Out-Null
    }

    $targetExe
}

$adminInstall = {
    param($Exe, $ExeSha256, $Script, $ScriptSha256, $User, $Name)

    $ErrorActionPreference = 'Stop'
    Get-Process $Name -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300

    $dir = Join-Path $env:ProgramFiles $Name
    $key = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$Name"
    $target = & $installFiles $Exe $ExeSha256 $Script $ScriptSha256 $dir $key $Name

    # The task has no trigger. The startup entry and Start menu shortcut launch the exe,
    # which hands off to this task. Defaults would kill it after 72 hours, stop it on battery,
    # and run it at below-normal priority.
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -Priority 4

    Register-ScheduledTask -TaskName $Name -Force `
        -Description 'Runs Disable WinKey Start Menu elevated' `
        -Action (New-ScheduledTaskAction -Execute $target -Argument '/task' -WorkingDirectory $dir) `
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
    Remove-Item "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$Name" -Recurse -ErrorAction SilentlyContinue
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
    $command = "`$installFiles = { $installFiles }; " +
        "try { & { $Block } $argText } " +
        "catch { Write-Host `$_ -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

    $p = Start-Process (Get-Process -Id $PID).Path -Verb RunAs -Wait -PassThru `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
    if ($p.ExitCode -ne 0) { throw 'The admin step failed.' }
}

# The startup entry and Start menu shortcut belong to the signed-in user, so this session writes them.
function Set-UserEntries([string]$Exe) {
    New-ItemProperty $runKey -Name $displayName -Value "`"$Exe`"" -PropertyType String -Force | Out-Null

    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($menuShortcut)
    $link.TargetPath = $Exe
    $link.WorkingDirectory = Split-Path $Exe
    $link.Description = 'Stops a lone Win key press from opening the Start menu'
    $link.Save()
}

function Remove-UserEntries {
    Remove-ItemProperty $runKey -Name $displayName -ErrorAction SilentlyContinue
    Remove-ItemProperty $approvedKey -Name $displayName -ErrorAction SilentlyContinue
    Remove-Item $menuShortcut -ErrorAction SilentlyContinue
}

function Remove-UserInstall {
    # Only stop the per-user copy, so a running admin install is left alone.
    Get-Process $name -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($userDir, 'OrdinalIgnoreCase') } |
        Stop-Process -Force
    Start-Sleep -Milliseconds 300
    Remove-Item $userDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\$uninstallPath" -Recurse -ErrorAction SilentlyContinue
}

function Copy-ToTemp([string]$Path) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "$name-$([guid]::NewGuid())$([IO.Path]::GetExtension($Path))"
    Copy-Item $Path $tmp
    $tmp
}

function Test-CanAttest {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return $false }
    gh auth status *> $null
    $LASTEXITCODE -eq 0
}

# Downloads a release asset to the temp folder and verifies it. Returns its path.
function Save-VerifiedAsset($Release, [string]$AssetName, [bool]$Attest) {
    $asset = $Release.assets | Where-Object name -eq $AssetName
    if (-not $asset) { throw "Release $($Release.tag_name) has no $AssetName asset." }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) "$name-$([guid]::NewGuid())$([IO.Path]::GetExtension($AssetName))"
    Write-Host "Downloading $AssetName from $($Release.tag_name)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $tmp -UseBasicParsing

    $expected = $asset.digest -replace '^sha256:', ''
    $actual = (Get-FileHash $tmp -Algorithm SHA256).Hash
    if ($actual -ne $expected) {
        Remove-Item $tmp
        throw "Digest mismatch for $AssetName. Expected $expected, got $actual."
    }

    if ($Attest) {
        Write-Host "Verifying build attestation for $AssetName"
        gh attestation verify $tmp --repo $repo
        if ($LASTEXITCODE -ne 0) {
            Remove-Item $tmp
            throw "Attestation verification failed for $AssetName."
        }
    }

    $tmp
}

# Returns verified temp copies of the exe and of this script, which becomes the uninstaller.
function Get-StagedFiles {
    if ($ExePath) {
        if (-not $PSCommandPath) { throw '-ExePath requires running install.ps1 from a file.' }
        Write-Host "Using local exe $ExePath (skipping release checks)"
        return @{ Exe = Copy-ToTemp $ExePath; Script = Copy-ToTemp $PSCommandPath }
    }

    $attest = Test-CanAttest
    if (-not $attest) { Write-Host 'GitHub CLI missing or signed out. Skipping attestation checks.' }

    $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
    $exe = Save-VerifiedAsset $release "$name.exe" $attest

    # Under irm | iex there is no script file, so the release copy becomes the uninstaller.
    $script = if ($PSCommandPath) { Copy-ToTemp $PSCommandPath } else { Save-VerifiedAsset $release 'install.ps1' $attest }

    @{ Exe = $exe; Script = $script }
}


if ($Uninstall) {

    # A process can't delete the folder it runs from, and this script may live in the install folder.
    Set-Location $env:TEMP
    [Environment]::CurrentDirectory = $env:TEMP

    Remove-UserEntries
    Remove-UserInstall
    if (Test-Path $adminDir) {
        Invoke-Admin $adminUninstall @{ Name = $name }
    }
    Write-Host "Uninstalled $displayName."
    return
}

if ($NoAdmin -and (Test-Path $adminDir)) {
    throw 'The admin install exists. Run with -Uninstall first, or install without -NoAdmin to update it.'
}

$staged = Get-StagedFiles
try {
    $hashes = @{
        Exe    = (Get-FileHash $staged.Exe -Algorithm SHA256).Hash
        Script = (Get-FileHash $staged.Script -Algorithm SHA256).Hash
    }

    if ($NoAdmin) {
        Remove-UserInstall
        $target = & $installFiles $staged.Exe $hashes.Exe $staged.Script $hashes.Script `
            $userDir "HKCU:\$uninstallPath" $name
        Set-UserEntries $target
        Start-Process $target
        Write-Host "Installed $displayName to $userDir."
    }
    else {
        # Capture the user here, since UAC may elevate as a different admin account.
        Invoke-Admin $adminInstall @{
            Exe          = $staged.Exe
            ExeSha256    = $hashes.Exe
            Script       = $staged.Script
            ScriptSha256 = $hashes.Script
            User         = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            Name         = $name
        }

        # Clear any older per-user install only after the admin install succeeds.
        Remove-UserInstall
        Set-UserEntries (Join-Path $adminDir "$name.exe")
        Write-Host "Installed $displayName to $adminDir."
    }
}
finally {
    Remove-Item $staged.Exe, $staged.Script -ErrorAction SilentlyContinue
}
