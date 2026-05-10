# DaVinci Resolve Utility Scripts

Lua utility scripts for DaVinci Resolve.

## Combined Color Effects Toggle

Use `davinci-toggle-color-effects_v_1.lua` to enable or disable matching Color page nodes across every timeline in the current project.

When run from `Workspace > Scripts > Utility`, the script prompts for:

- Target: `Noise Reduction`, `AI Ultra Sharpen`, or `Both`
- Action: `Disable` or `Enable`
- Scope: `Pre-Clip`, `Clip`, `Post-Clip`, `Timeline`, or `All`

The script scans each timeline, temporarily makes it current while processing, applies the selected action to matching nodes, and restores the original timeline at the end.

The first run defaults to `Both`, `Disable`, and `All`. After that, it remembers your last valid Target and Scope choices in the system temp folder, while the Action defaults to the opposite of the last valid run.

Scopes covered:

- Clip nodes, including clip node stack layers
- Timeline nodes
- Group Pre-Clip nodes
- Group Post-Clip nodes

## macOS Install

Double-click `install_macos.command`, or run:

```bash
./install_macos.command
```

Manual install path:

```text
~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility
```

Restart DaVinci Resolve if the script does not appear in the menu.

## Windows 11 Install

Double-click `install_win11.bat`, or run it from PowerShell / Command Prompt:

```powershell
.\install_win11.bat
```

Manual install path:

```text
%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility
```

Full expanded path is usually:

```text
C:\Users\<you>\AppData\Roaming\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility
```

Restart DaVinci Resolve if the script does not appear in the menu.

## Deploy Helper

The installer scripts call the shared Python deploy helper. You can also run it directly.

macOS:

```bash
python3 tools/deploy.py davinci-toggle-color-effects_v_1.lua
```

Windows 11:

```powershell
python tools\deploy.py davinci-toggle-color-effects_v_1.lua
```

Dry-run first if you want to check the resolved path:

```powershell
python tools\deploy.py davinci-toggle-color-effects_v_1.lua --dry-run --verbose
```

## Logs

The combined script writes a log named:

```text
resolve_toggle_color_effects_v_1_log.txt
```

Read it with:

macOS:

```bash
python3 tools/get_log.py --name resolve_toggle_color_effects_v_1_log.txt
```

Windows 11:

```powershell
python tools\get_log.py --name resolve_toggle_color_effects_v_1_log.txt
```

The log lives in the system temp folder: `%TEMP%` on Windows and `$TMPDIR` on macOS.

## Notes

DaVinci Resolve's scripting API can enable or disable a node, but it does not expose a reliable `GetNodeEnabled()` call. For that reason, the combined script asks for an explicit `Enable` or `Disable` action rather than guessing the current node state.
