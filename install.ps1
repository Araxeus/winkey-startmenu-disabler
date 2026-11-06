<#
.SYNOPSIS
    Installs (or uninstalls) disable-winkey-startmenu for the current user.
.DESCRIPTION
    Downloads the latest release exe, checks it against the digest GitHub reports for the asset,
    verifies its build attestation when the GitHub CLI is available, copies it to
    %LOCALAPPDATA%\Programs, adds a Startup shortcut, and starts it.
.EXAMPLE
    irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1 | iex
.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1))) -Uninstall
#>
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo       = 'Araxeus/disable-winkey-startmenu'
$name       = 'disable-winkey-startmenu'
$installDir = Join-Path $env:LOCALAPPDATA "Programs\$name"
$exe        = Join-Path $installDir "$name.exe"
$shortcut   = Join-Path ([Environment]::GetFolderPath('Startup')) "$name.lnk"

# The running exe locks its file, so stop it before replacing or removing it.
Get-Process $name -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 300

if ($Uninstall) {
    Remove-Item $shortcut -ErrorAction SilentlyContinue
    Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Uninstalled $name."
    return
}

$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
$asset = $release.assets | Where-Object name -eq "$name.exe"
if (-not $asset) { throw "Release $($release.tag_name) has no $name.exe asset." }

$tmp = Join-Path ([IO.Path]::GetTempPath()) "$name-$([guid]::NewGuid()).exe"
try {
    Write-Host "Downloading $name $($release.tag_name)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $tmp -UseBasicParsing

    $expected = $asset.digest -replace '^sha256:', ''
    $actual = (Get-FileHash $tmp -Algorithm SHA256).Hash
    if ($actual -ne $expected) { throw "Digest mismatch. Expected $expected, got $actual." }

    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Write-Host 'Verifying build attestation'
        gh attestation verify $tmp --repo $repo
        if ($LASTEXITCODE -ne 0) { throw 'Attestation verification failed.' }
    }
    else {
        Write-Host 'GitHub CLI not found. Skipping attestation check.'
    }

    New-Item -ItemType Directory -Force $installDir | Out-Null
    Move-Item $tmp $exe -Force
}
finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($shortcut)
$link.TargetPath = $exe
$link.WorkingDirectory = $installDir
$link.Save()

Start-Process $exe
Write-Host "Installed $name $($release.tag_name) to $installDir and added it to Startup."
