#Requires -Version 7

<#
.SYNOPSIS
    Downloads pinned, hash-checked build tools and compiles the script with Ahk2Exe + UPX.
.PARAMETER Version
    Version stamped into the exe. Defaults to 0.0.0.
#>
param(
    [string]$Version = '0.0.0'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root  = $PSScriptRoot
$tools = Join-Path $root '.tools'
$dist  = Join-Path $root 'dist'
$name  = 'disable-winkey-startmenu'

# Bump versions and hashes together.
$deps = @(
    @{
        Url    = 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.31/AutoHotkey_2.0.31.zip'
        Sha256 = 'ca1a595aca4528755d8d4cd7fed23d497a37bd9a0b6892072612d68dee1bd00a'
        Dir    = 'ahk'
    }
    @{
        Url    = 'https://github.com/AutoHotkey/Ahk2Exe/releases/download/Ahk2Exe1.1.37.02a2/Ahk2Exe1.1.37.02a2.zip'
        Sha256 = 'c29b8c3a5124850d79fc9e66e2ca79677c377d7f31631ad3022ba159c5d9e3be'
        Dir    = 'ahk2exe'
    }
    @{
        Url    = 'https://github.com/upx/upx/releases/download/v5.3.0/upx-5.3.0-win64.zip'
        Sha256 = 'd127996c76615e431be810e9c8d2910dbe3dd400600c5c0c50276fc5a17a9705'
        Dir    = 'upx'
    }
)

New-Item -ItemType Directory -Force $tools, $dist | Out-Null

foreach ($dep in $deps) {
    $zip = Join-Path $tools (Split-Path $dep.Url -Leaf)
    $out = Join-Path $tools $dep.Dir

    if (-not (Test-Path $zip)) {
        Write-Host "Downloading $($dep.Url)"
        Invoke-WebRequest $dep.Url -OutFile $zip
    }

    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($hash -ne $dep.Sha256) {
        Remove-Item $zip
        throw "Hash mismatch for $zip. Expected $($dep.Sha256), got $hash."
    }

    if (-not (Test-Path $out)) {
        Expand-Archive $zip $out
    }
}

# Ahk2Exe looks for upx.exe next to itself.
$ahk2exe = Join-Path $tools 'ahk2exe\Ahk2Exe.exe'
$upx = Get-ChildItem (Join-Path $tools 'upx') -Recurse -Filter upx.exe | Select-Object -First 1
Copy-Item $upx.FullName (Join-Path $tools 'ahk2exe\upx.exe') -Force

# Stamp the version into a temp copy so the tracked source stays at 0.0.0.
$src = Join-Path $root "$name.ahk"
$tmp = Join-Path $root "$name.build.ahk"
(Get-Content $src -Raw) -replace '(?m)^;@Ahk2Exe-SetVersion .*$', ";@Ahk2Exe-SetVersion $Version" |
    Set-Content $tmp -NoNewline

$exe = Join-Path $dist "$name.exe"
Remove-Item $exe -ErrorAction SilentlyContinue

try {
    $ahkArgs = @(
        '/in', "`"$tmp`""
        '/out', "`"$exe`""
        '/base', "`"$(Join-Path $tools 'ahk\AutoHotkey64.exe')`""
        '/compress', '2'
        '/silent', 'verbose'
    )
    $p = Start-Process $ahk2exe -ArgumentList $ahkArgs -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { throw "Ahk2Exe exited with code $($p.ExitCode)." }
}
finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

if (-not (Test-Path $exe)) { throw 'Ahk2Exe produced no exe.' }

$hash = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
Write-Host "Built $exe ($Version)"
Write-Host "SHA256 $hash"
