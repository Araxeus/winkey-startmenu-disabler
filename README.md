# disable-winkey-startmenu

Stops a lone press of the left Windows key from opening the Start menu. Win shortcuts such as Win+E, Win+R and Win+Shift+S still work.

A small AutoHotkey v2 script, compiled to a standalone exe and packaged with Inno Setup by GitHub Actions. Every release file carries a signed [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations).

## Install

1. Download `disable-winkey-startmenu-setup.exe` from the [latest release](https://github.com/Araxeus/disable-winkey-startmenu/releases/latest)
2. Run it and approve the UAC prompt

Setup asks for admin once and installs for all users. Windows blocks keyboard hooks from normal processes while an admin window has focus, so the all-users install runs the app elevated through a scheduled task, without a UAC prompt at each sign-in.

Declining UAC closes setup. Without admin rights, install for yourself only with `disable-winkey-startmenu-setup.exe /CURRENTUSER` or the PowerShell `-NoAdmin` command below. That install works everywhere except while an admin window has focus.

| Mode | Needs admin | Works while an admin window has focus |
|---|---|---|
| All users (default) | Yes, once | Yes |
| Current user (`/CURRENTUSER`) | No | No |

The setup is not code-signed, so Windows SmartScreen may show "Windows protected your PC". Click **More info**, then **Run anyway**.

Both modes add:

- A Start menu shortcut
- A startup entry you can turn off in Task Manager › Startup apps
- An entry in Settings › Apps for uninstalling

Running a newer setup updates the app in place.

### From PowerShell

```powershell
irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1 | iex
```

The script downloads the latest setup, checks it against the SHA-256 digest GitHub reports for the asset, verifies its attestation if the [GitHub CLI](https://cli.github.com) is installed and signed in, and runs it silently for all users.

To install for the current user only:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1))) -NoAdmin
```

### Silent install

```
disable-winkey-startmenu-setup.exe /VERYSILENT /ALLUSERS
disable-winkey-startmenu-setup.exe /VERYSILENT /CURRENTUSER
```

Without a mode flag, setup installs for all users.

## Uninstall

Uninstall from Settings › Apps, or run:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Araxeus/disable-winkey-startmenu/main/install.ps1))) -Uninstall
```

## Verify a download manually

```powershell
gh attestation verify disable-winkey-startmenu-setup.exe --repo Araxeus/disable-winkey-startmenu
```

## Usage

The app runs in the tray. Its menu has a single item, **Quit**. To start it again, open **Disable WinKey Start Menu** from the Start menu.

The standalone `disable-winkey-startmenu.exe` in each release also runs without installing.

## How the all-users install stays elevated

- Setup registers an on-demand scheduled task that runs the exe elevated for the user who installed it
- The startup entry and the Start menu shortcut launch the exe normally
- An unelevated exe starts the task and exits, so the running copy is elevated
- For other users, the task is unavailable and the app runs unelevated

## Limitations

- Only the left Windows key is handled
- In the just-me install, the Start menu still opens while an admin window has focus

## Build locally

Requires PowerShell 7.

```powershell
./build.ps1 -Version 1.0.0
```

The script downloads pinned AutoHotkey, Ahk2Exe, UPX and Inno Setup releases into `.tools` and checks their SHA-256 hashes. It writes `dist/disable-winkey-startmenu.exe` and `dist/disable-winkey-startmenu-setup.exe`.

To run a local setup silently, use `./install.ps1 -SetupPath dist/disable-winkey-startmenu-setup.exe`.

## Release

Push a version tag:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

The `Release` workflow builds both exes, attests them, and publishes a GitHub release. Running the workflow manually produces a test build as a workflow artifact instead.

## License

[MIT](LICENSE)
