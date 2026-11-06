# disable-winkey-startmenu

Stops a lone press of the left Windows key from opening the Start menu. Win shortcuts such as Win+E, Win+R and Win+Shift+S still work.

A small AutoHotkey v2 script, compiled to a standalone exe by GitHub Actions. Every release exe carries a signed [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations).

## Install

Run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1 | iex
```

The installer:

1. Downloads `disable-winkey-startmenu.exe` from the latest release
2. Checks it against the SHA-256 digest GitHub reports for the asset
3. Verifies the build attestation if the [GitHub CLI](https://cli.github.com) is installed
4. Copies it to `%LOCALAPPDATA%\Programs\disable-winkey-startmenu`
5. Adds a shortcut to your Startup folder and starts it

Running the installer again updates to the latest release.

## Uninstall

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1))) -Uninstall
```

## Verify a download manually

```powershell
gh attestation verify disable-winkey-startmenu.exe --repo Araxeus/disable-winkey-startmenu
```

## Usage

The app runs in the tray. Its menu has a single item, **Quit**.

## Limitations

- Windows blocks keyboard hooks from a normal process while an elevated (admin) window has focus. The Start menu still opens from those windows.
- Only the left Windows key is handled.

## Build locally

Requires PowerShell 7.

```powershell
./build.ps1 -Version 1.0.0
```

The script downloads pinned AutoHotkey, Ahk2Exe and UPX releases into `.tools`, checks their SHA-256 hashes, and writes `dist/disable-winkey-startmenu.exe`.

## Release

Push a version tag:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

The `Release` workflow builds the exe, attests it, and publishes a GitHub release. Running the workflow manually produces a test build as a workflow artifact instead.

## License

[MIT](LICENSE)
