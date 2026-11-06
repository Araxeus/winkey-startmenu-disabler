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
3. Verifies the build attestation if the [GitHub CLI](https://cli.github.com) is installed and signed in
4. Asks for admin once through UAC
5. Copies the exe and an uninstaller to `C:\Program Files\disable-winkey-startmenu`
6. Registers a scheduled task that runs the exe elevated
7. Adds a startup entry, a Start menu shortcut, and an entry in Settings › Apps, then starts the app

The app runs elevated so it also works while an admin window has focus. Windows blocks keyboard hooks from normal processes in that case.

The startup entry and the shortcut launch the exe normally. The exe then starts the scheduled task and exits, so the running copy is elevated without a UAC prompt. You can turn the startup entry off in Task Manager › Startup apps.

Running the installer again updates to the latest release.

### Without admin rights

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1))) -NoAdmin
```

This installs to `%LOCALAPPDATA%\Programs\disable-winkey-startmenu` with the same startup entry, shortcut and Settings entry. In this mode the Start menu still opens while an admin window has focus.

## Uninstall

Uninstall from Settings › Apps, or run:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1))) -Uninstall
```

Both remove every install type. They ask for admin only if the admin install exists.

## Verify a download manually

```powershell
gh attestation verify disable-winkey-startmenu.exe --repo Araxeus/disable-winkey-startmenu
```

## Usage

The app runs in the tray. Its menu has a single item, **Quit**. To start it again, open **Disable WinKey Start Menu** from the Start menu.

## Limitations

- Only the left Windows key is handled.
- With `-NoAdmin`, the Start menu still opens while an admin window has focus.

## Build locally

Requires PowerShell 7.

```powershell
./build.ps1 -Version 1.0.0
```

The script downloads pinned AutoHotkey, Ahk2Exe and UPX releases into `.tools`, checks their SHA-256 hashes, and writes `dist/disable-winkey-startmenu.exe`.

To install a local build, run `./install.ps1 -ExePath dist/disable-winkey-startmenu.exe`.

## Release

Push a version tag:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

The `Release` workflow builds the exe, attests it, and publishes a GitHub release. Running the workflow manually produces a test build as a workflow artifact instead.

## License

[MIT](LICENSE)
