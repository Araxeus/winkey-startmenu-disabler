# Disable WinKey Start Menu

For people who never want the Windows key to open the Start menu, but still use it for shortcuts.

Pressing Win on its own does nothing. Win+E, Win+R, Win+Shift+S and every other Win shortcut work as usual, and clicking the Start button still opens the Start menu.

## Install

1. Download `disable-winkey-startmenu-setup.exe` from the [latest release](https://github.com/Araxeus/disable-winkey-startmenu/releases/latest)
2. Run it and approve the admin prompt

The setup is not code-signed, so Windows may show "Windows protected your PC". Click **More info**, then **Run anyway**.

Running a newer setup updates the app in place.

### Without admin rights

Run `disable-winkey-startmenu-setup.exe /CURRENTUSER`. This install works everywhere except while an admin window is focused, because Windows blocks keyboard hooks from normal apps in admin windows.

## Usage

The app starts with Windows and lives in the tray. Its tray menu has **Quit**. To start it again, open **Disable WinKey Start Menu** from the Start menu.

- Turn off starting with Windows in Task Manager › Startup apps
- Uninstall from Settings › Apps

## PowerShell

Install, verifying the download first:

```powershell
irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1 | iex
```

Add `-NoAdmin` or `-Uninstall` with this form:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1))) -Uninstall
```

The script checks the setup against the SHA-256 digest GitHub reports for it. If the [GitHub CLI](https://cli.github.com) is installed and signed in, it also verifies the build attestation.

## Verify a download

Every release file has a signed [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations):

```powershell
gh attestation verify disable-winkey-startmenu-setup.exe --repo Araxeus/disable-winkey-startmenu
```

## Notes

- Only the left Windows key is handled
- The app runs elevated, so it also works in admin windows. A scheduled task elevates it at startup without a UAC prompt. This applies to the user who installed it. Other users get the app without elevation.
- Each release also includes the standalone `disable-winkey-startmenu.exe`, which runs without installing

## Development

The app is an AutoHotkey v2 script compiled with Ahk2Exe and UPX, packaged with Inno Setup. Building requires PowerShell 7:

```powershell
./build.ps1 -Version 1.0.0
```

`build.ps1` downloads pinned, hash-checked tools into `.tools` and writes both exes to `dist/`.

To release, push a tag such as `v1.0.0`. The `Release` workflow builds, attests and publishes both exes. A manual workflow run uploads a test build as an artifact instead.

## License

[MIT](LICENSE)
