# DaVinci Resolve Utility Scripts

Lua utility scripts for DaVinci Resolve.

## Combined Color Effects Toggle

Use `davinci-toggle-color-effects_v_1.lua` to enable or disable matching Color page nodes across every timeline in the current project.

When run from `Workspace > Scripts > Utility`, the script prompts for:

- Target: `Noise Reduction`, `AI Ultra Sharpen`, or `Both`
- Action: `Disable` or `Enable`

The script scans each timeline, temporarily makes it current while processing its node graph, applies the selected action to matching nodes, and restores the original timeline at the end.

## Windows 11 Install

Copy `davinci-toggle-color-effects_v_1.lua` to:

```text
%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility
```

Full expanded path is usually:

```text
C:\Users\<you>\AppData\Roaming\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility
```

Restart DaVinci Resolve if the script does not appear in the menu.

## Windows 11 Deploy Helper

From PowerShell or Command Prompt, inside this repo:

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

On Windows, read it with:

```powershell
python tools\get_log.py --name resolve_toggle_color_effects_v_1_log.txt
```

The log lives in `%TEMP%`.

## Notes

DaVinci Resolve's scripting API can enable or disable a node, but it does not expose a reliable `GetNodeEnabled()` call. For that reason, the combined script asks for an explicit `Enable` or `Disable` action rather than guessing the current node state.
