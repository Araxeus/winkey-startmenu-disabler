#Requires -Version 7

<#
.SYNOPSIS
    Downloads pinned, hash-checked build tools, compiles the script with Ahk2Exe + UPX,
    and builds the Inno Setup installer.
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
$name  = 'winkey-startmenu-disabler'

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
    @{
        Url    = 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_4/innosetup-6.7.4.exe'
        Sha256 = 'a549929319f9120716677c685535ca4671e4b937b5fdc87e2585f32d8eb30e8c'
        Dir    = 'inno'
    }
)

New-Item -ItemType Directory -Force $tools, $dist | Out-Null

foreach ($dep in $deps) {
    $file = Join-Path $tools (Split-Path $dep.Url -Leaf)
    $out = Join-Path $tools $dep.Dir

    if (-not (Test-Path $file)) {
        Write-Host "Downloading $($dep.Url)"
        Invoke-WebRequest $dep.Url -OutFile $file
    }

    $hash = (Get-FileHash $file -Algorithm SHA256).Hash
    if ($hash -ne $dep.Sha256) {
        Remove-Item $file
        throw "Hash mismatch for $file. Expected $($dep.Sha256), got $hash."
    }

    if (Test-Path $out) { continue }

    if ($file.EndsWith('.zip')) {
        Expand-Archive $file $out
    }
    else {
        # Portable mode unpacks Inno Setup without registering it on the system.
        $innoArgs = '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', '/PORTABLE=1', "/DIR=`"$out`""
        $p = Start-Process $file -ArgumentList $innoArgs -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "Inno Setup unpack exited with code $($p.ExitCode)." }
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

$setup = Join-Path $dist "$name-setup.exe"
Remove-Item $setup -ErrorAction SilentlyContinue

& (Join-Path $tools 'inno\ISCC.exe') /Q "/DAppVersion=$Version" (Join-Path $root 'installer.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC exited with code $LASTEXITCODE." }

foreach ($file in $exe, $setup) {
    $hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
    Write-Host "Built $file ($Version)"
    Write-Host "SHA256 $hash"
}
