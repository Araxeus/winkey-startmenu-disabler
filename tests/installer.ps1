# Run on a clean Windows VM. The installer manages the real current user's startup entry.
#Requires -Version 7
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$name = 'winkey-startmenu-disabler'
$displayName = 'WinKey Start Menu Disabler'
$subkey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{833F386A-62D2-4DF9-955B-F8DF8A9F2013}_is1'
$userEntry = "HKCU:\$subkey"
$machineEntry = "HKLM:\$subkey"
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$installScript = Join-Path $root 'install.ps1'

function Get-StartupCommand {
    (Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue).$displayName
}

function Get-AppTask {
    Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction SilentlyContinue
}

if ((Test-Path $userEntry) -or (Test-Path $machineEntry) -or (Get-StartupCommand) -or
    (Get-AppTask) -or (Get-Process -Name $name -ErrorAction SilentlyContinue)) {
    throw 'The app already has files running or registrations on this machine. Use a clean VM.'
}

try {
    & $installScript -NoAdmin -SetupPath (Join-Path $root "dist/$name-setup.exe")
    $entry = Get-ItemProperty -LiteralPath $userEntry
    $installedExe = Join-Path $entry.InstallLocation "$name.exe"
    if ((Get-StartupCommand) -cne ('"' + $installedExe + '"')) {
        throw "Current-user startup entry should point to the installed executable: $installedExe"
    }
    if ((Get-FileHash $installedExe).Hash -ne (Get-FileHash (Join-Path $root "dist/$name.exe")).Hash) {
        throw 'Installed executable differs from the PR build.'
    }
    if ((Test-Path $machineEntry) -or (Get-AppTask)) {
        throw 'Current-user setup created a machine registration or an elevated task.'
    }
} finally {
    & $installScript -Uninstall
}

if ((Test-Path $userEntry) -or (Get-StartupCommand) -or (Test-Path -LiteralPath $installedExe)) {
    throw 'Uninstall left the current-user registration, startup entry, or executable behind.'
}
Write-Host 'Silent current-user install and uninstall passed.'
