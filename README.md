# WinKey Start Menu Disabler

For people who never want the Windows key to open the Start menu, but still use it for shortcuts.

Pressing Win on its own does nothing. Win+E, Win+R, Win+Shift+S and every other Win shortcut work as usual, and clicking the Start button still opens the Start menu.

## Install

1. Download `winkey-startmenu-disabler-setup.exe` from the [latest release](https://github.com/Araxeus/winkey-startmenu-disabler/releases/latest)
2. Run it and approve the admin prompt

The setup is not code-signed, so Windows may show "Windows protected your PC". Click **More info**, then **Run anyway**.

Running a newer setup updates the app in place.

### Without admin rights

Run `winkey-startmenu-disabler-setup.exe /CURRENTUSER`. This install works everywhere except while an admin window is focused, because Windows blocks keyboard hooks from normal apps in admin windows.

## Usage

The app starts with Windows and lives in the tray.

- **Pause** gives the Win key back until you resume. The tray icon turns gray while paused. Double-clicking the tray icon also toggles it.
- **Quit** closes the app. To start it again, open **WinKey Start Menu Disabler** from the Start menu.
- Turn off starting with Windows in Task Manager › Startup apps
- Uninstall from Settings › Apps

## PowerShell

Install, verifying the download first:

```powershell
irm https://raw.githubusercontent.com/Araxeus/winkey-startmenu-disabler/main/install.ps1 | iex
```

Add `-NoAdmin` or `-Uninstall` with this form:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/winkey-startmenu-disabler/main/install.ps1))) -Uninstall
```

The script checks the setup against the SHA-256 digest GitHub reports for it. If the [GitHub CLI](https://cli.github.com) is installed and signed in, it also verifies the build attestation.

## Verify a download

Every release file has a signed [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations):

```powershell
gh attestation verify winkey-startmenu-disabler-setup.exe --repo Araxeus/winkey-startmenu-disabler
```

## Notes

- Only the left Windows key is handled
- The app runs elevated, so it also works in admin windows. A scheduled task elevates it at startup without a UAC prompt. This applies to the user who installed it. Other users get the app without elevation.
- Each release also includes the standalone `winkey-startmenu-disabler.exe`, which runs without installing

## Development

The app is an AutoHotkey v2 script compiled with Ahk2Exe and UPX, packaged with Inno Setup. Building requires PowerShell 7:

```powershell
./build.ps1 -Version 1.0.0
```

`build.ps1` downloads pinned, hash-checked tools into `.tools` and writes both exes to `dist/`.

To release, push a tag such as `v1.0.0`. The `Release` workflow builds, attests and publishes both exes. A manual workflow run uploads a test build as an artifact instead.

## License

[MIT](LICENSE)

### Third-party software

- The exe includes the [AutoHotkey](https://github.com/AutoHotkey/AutoHotkey) v2 interpreter, licensed under [GPL-2.0](https://github.com/AutoHotkey/AutoHotkey/blob/v2.0/license.txt)
- The exe is compressed with [UPX](https://github.com/upx/upx), whose [license](https://github.com/upx/upx/blob/devel/LICENSE) allows distributing compressed programs
- The installer is built with [Inno Setup](https://jrsoftware.org/isinfo.php), under the [Inno Setup License](https://jrsoftware.org/files/is/license.txt)
