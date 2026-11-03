# serial-console

A small terminal picker for serial consoles on Fortinet gear (FortiGate, FortiSwitch, FortiAP) on Windows.
Type `serial`, pick the device type (that sets the baud rate), pick the COM port, and you are connected.

It is a PowerShell front-end for [SerialTerm](https://github.com/AdamKeher/SerialTerm) by Adam Keher, which does the actual serial work.

```
  Serial console – device type
  ────────────────────────────────────────────────────────────
  > FortiGate          9600 baud
    FortiSwitch      115200 baud
    FortiAP            9600 baud
    Other (115200)   115200 baud
    Other (9600)       9600 baud

  Up/Down or 1-9 · Enter select · Esc cancel
```

## Install

Paste this into PowerShell (7 or Windows PowerShell 5.1, no admin needed):

```powershell
irm https://raw.githubusercontent.com/jensopt/serial-console/main/install.ps1 | iex
```

Run the same line again to **update**: it fetches the latest SerialTerm release and the latest module.

## What the installer changes

Everything is per user. Nothing needs admin rights, and **your PowerShell profile (`$PROFILE`) is not touched**.
PowerShell loads the module automatically the first time you type `serial`.

| What | Where | Notes |
|---|---|---|
| `SerialTerm.exe` | `%LOCALAPPDATA%\Programs\SerialTerm\` | Latest release from [AdamKeher/SerialTerm](https://github.com/AdamKeher/SerialTerm/releases/latest), x64 or arm64, checked against the release's SHA256 digest. Overwritten on update. |
| User `PATH` | `HKCU\Environment` → `Path` | Adds the folder above (once), so `SerialTerm` and `SerialTerm @fortigate` work directly. Takes effect in new terminals. |
| PowerShell module `SerialConsole` | `Documents\PowerShell\Modules\SerialConsole\` (PowerShell 7)<br>`Documents\WindowsPowerShell\Modules\SerialConsole\` (5.1) | Provides the `serial` command. Overwritten on update. |
| SerialTerm profiles | `%APPDATA%\SerialTerm\profiles\` | `fortigate.rsp`, `fortiswitch.rsp`, `fortiap.rsp`. **Existing files with these names are never overwritten**, so your own tweaks survive updates. |

## Profiles

There are two kinds of "profile". They do the same job (preset baud rate) from two different entry points.

**1. Device types in the `serial` picker.** These are built into the module:

| Device type | Baud | Typical use |
|---|---|---|
| FortiGate | 9600 | FortiGate console port (RJ45 or USB-C) |
| FortiSwitch | 115200 | FortiSwitch console port |
| FortiAP | 9600 | FortiAP console port |
| Other (115200) | 115200 | Anything else at 115200 |
| Other (9600) | 9600 | Anything else at 9600 |

The serial line is always 8N1 with no flow control (SerialTerm defaults). If you get garbage on screen, the baud rate is wrong. Press `Ctrl+A #` in the session to change it without reconnecting.

**2. SerialTerm argument profiles (`.rsp`).** Use these when you skip the picker and call SerialTerm directly:

| Command | Contents |
|---|---|
| `SerialTerm @fortigate` | `--baud 9600 --status-line` |
| `SerialTerm @fortiswitch` | `--baud 115200 --status-line` |
| `SerialTerm @fortiap` | `--baud 9600 --status-line` |

A `.rsp` file is a plain text file with one argument per line. `#` comments are allowed. Add your own in `%APPDATA%\SerialTerm\profiles\`, and list them with `SerialTerm profiles`. Command-line arguments override the profile: `SerialTerm @fortigate --port COM5`.

## Usage

```
serial                       device type -> COM port -> connect
serial --help                help, baud rates and all keys
serial --log boot.log        extra arguments are passed to SerialTerm
serial --timestamp abs
SerialTerm list              list COM ports
```

**In the picker:** `Up`/`Down` or `1`-`9` to choose, `Enter` to select, `R` to refresh the ports after plugging in a cable, `Esc` to go back or cancel.
USB/real ports are listed first and Bluetooth serial links last.

**In the session**, press `Ctrl+A`, then:

| Key | Action | Key | Action | Key | Action |
|---|---|---|---|---|---|
| `q` | quit | `l` | log on/off | `s` | send text file |
| `b` | send break | `#` | change baud | `d` | disconnect/reconnect |
| `i` | port settings | `f` | freeze screen | `v` | hex view |
| `o` | local echo | `c` | clear screen | `t` | DTR/RTS lines |
| `1`-`9` | send macro | `?` | key help | `Ctrl+A` | literal Ctrl+A |

## Tips

- Use **Windows Terminal**. The legacy console host renders the picker poorly.
- Is the console cable not listed? Install its USB-serial driver (Prolific, FTDI, CH340, Silicon Labs CP210x), then press `R`.
- `SerialTerm.exe is in use` during an update means a session is still open. Close it and run the installer again.

## Uninstall

```powershell
Remove-Item "$env:LOCALAPPDATA\Programs\SerialTerm" -Recurse -Force
$docs = [Environment]::GetFolderPath('MyDocuments')
'PowerShell', 'WindowsPowerShell' | ForEach-Object { Remove-Item "$docs\$_\Modules\SerialConsole" -Recurse -Force -ErrorAction SilentlyContinue }
Remove-Item "$env:APPDATA\SerialTerm\profiles\forti*.rsp"
```

Then remove `%LOCALAPPDATA%\Programs\SerialTerm` from your user `PATH`: Start → *Edit environment variables for your account* → `Path`.

## Credits

Serial engine: [SerialTerm](https://github.com/AdamKeher/SerialTerm) by Adam Keher. This repository does not contain or redistribute SerialTerm. The installer downloads it from the official GitHub releases.
