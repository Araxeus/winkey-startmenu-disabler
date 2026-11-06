<#
.SYNOPSIS
    Installs, updates, or uninstalls winkey-startmenu-disabler from the command line.
.DESCRIPTION
    Downloads the latest setup exe, checks it against the digest GitHub reports for the release asset,
    verifies its build attestation when the GitHub CLI is installed and signed in, and runs it silently.

    The default install is for all users and asks for admin once. It runs the app elevated,
    so it also works while an admin window has focus.
.PARAMETER NoAdmin
    Install for the current user without admin rights. The Start menu still opens while an admin window has focus.
.PARAMETER Uninstall
    Remove the app. Asks for admin if it was installed for all users.
.PARAMETER SetupPath
    Run a local setup exe instead of the latest release. Skips the digest and attestation checks.
.EXAMPLE
    irm https://raw.githubusercontent.com/Araxeus/winkey-startmenu-disabler/main/install.ps1 | iex
.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/winkey-startmenu-disabler/main/install.ps1))) -NoAdmin
.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/winkey-startmenu-disabler/main/install.ps1))) -Uninstall
#>
param(
    [switch]$NoAdmin,
    [switch]$Uninstall,
    [string]$SetupPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo      = 'Araxeus/winkey-startmenu-disabler'
$setupName = 'winkey-startmenu-disabler-setup.exe'
$silent    = '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'

# Matches AppId in installer.iss.
$uninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{833F386A-62D2-4DF9-955B-F8DF8A9F2013}_is1'


function Test-CanAttest {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return $false }
    gh auth status *> $null
    $LASTEXITCODE -eq 0
}

# Downloads the latest setup exe to the temp folder and verifies it. Returns its path.
function Save-VerifiedSetup {
    $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
    $asset = $release.assets | Where-Object name -eq $setupName
    if (-not $asset) { throw "Release $($release.tag_name) has no $setupName asset." }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) "winkey-startmenu-disabler-$([guid]::NewGuid())-setup.exe"
    Write-Host "Downloading $setupName from $($release.tag_name)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $tmp -UseBasicParsing

    $expected = $asset.digest -replace '^sha256:', ''
    $actual = (Get-FileHash $tmp -Algorithm SHA256).Hash
    if ($actual -ne $expected) {
        Remove-Item $tmp
        throw "Digest mismatch. Expected $expected, got $actual."
    }

    if (Test-CanAttest) {
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

    $tmp
}


if ($Uninstall) {
    $found = $false

    foreach ($hive in 'HKCU', 'HKLM') {
        $key = "${hive}:\$uninstallKey"
        $entry = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if (-not $entry) { continue }

        $found = $true
        Write-Host "Uninstalling ($hive)"
        Start-Process $entry.UninstallString.Trim('"') -ArgumentList $silent | Out-Null

        # The uninstaller relaunches itself from a temp copy, so wait for its entry to disappear.
        $deadline = (Get-Date).AddMinutes(2)
        while ((Test-Path $key) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
        if (Test-Path $key) { throw 'The uninstaller did not finish. Was the UAC prompt declined?' }
    }

    if ($found) { Write-Host 'Uninstalled WinKey Start Menu Disabler.' }
    else { Write-Host 'WinKey Start Menu Disabler is not installed.' }
    return
}

$downloaded = -not $SetupPath
$setup = if ($SetupPath) { (Resolve-Path $SetupPath).Path } else { Save-VerifiedSetup }

try {
    $mode = if ($NoAdmin) { '/CURRENTUSER' } else { '/ALLUSERS' }
    Write-Host "Running setup ($mode)"

    # Start-Process -Wait would also wait for the app that setup starts.
    $p = Start-Process $setup -ArgumentList ($silent + $mode) -PassThru
    $null = $p.Handle
    $p.WaitForExit()

    switch ($p.ExitCode) {
        0 { Write-Host 'Installed WinKey Start Menu Disabler.' }
        2 { throw 'Setup was cancelled. Was the UAC prompt declined? Run with -NoAdmin to install without admin rights.' }
        7 { throw 'Setup stopped before installing. If the app is installed for all users, run without -NoAdmin to update it, or uninstall it first.' }
        default { throw "Setup failed with exit code $($p.ExitCode)." }
    }
}
finally {
    if ($downloaded) { Remove-Item $setup -ErrorAction SilentlyContinue }
}
