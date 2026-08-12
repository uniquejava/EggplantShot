# AGENTS.md — EggplantShot

## What this is

Native **macOS 14+** Snipaste-style screenshot utility (MVP).

- Menu bar only (`LSUIElement`); Dock icon only while Preferences is open
- Global hotkeys via `CGEvent` tap (Accessibility required)
- Area snip → pin floating image, or copy to clipboard
- Screen Recording permission required for capture

Inspiration: Snipaste menu + pin workflow.

## Stack

| Layer | Tech |
|-------|------|
| UI | SwiftUI `MenuBarExtra` + AppKit overlays / pin panels |
| Hotkey | `CGEvent` tap (multi-binding) |
| Capture | `CGDisplayCreateImage` + crop |
| Login item | not yet |

Bundle ID: `click.yinsb.EggplantShot`  
Team: `DEVELOPMENT_TEAM = M5J7K9HVYB`  
Xcode: `EggplantShot.xcodeproj` (scheme `EggplantShot`)

## Layout

```
EggplantShot/
  EggplantShotApp.swift
  Hotkey/HotkeyMonitor.swift + HotkeyShortcut.swift
  Capture/ScreenPermissions.swift + ScreenCapturer.swift
  Controllers/SnipController.swift
  Controllers/SelectionOverlayController.swift
  Controllers/PinBoardController.swift
  UI/StatusMenuContent.swift + SettingsView.swift
  Assets.xcassets/
  Info.plist                 # LSUIElement = true
  EggplantShot.entitlements  # App Sandbox OFF
```

## Product behaviour to preserve

1. **Snip (F1)** → area select → pin floating image (draggable; Esc / double-click closes).
2. **Snip and copy (⌘F1)** → area select → clipboard only.
3. Overlay must be torn down before capture so it is not in the image.
4. **Disable hotkeys** pauses the event tap (persisted).
5. Preferences via `SettingsLink` / `openSettings` (not `showSettingsWindow:`).
6. Without Accessibility, global hotkeys do nothing. Without Screen Recording, capture fails with a prompt.

## Prefer

- Small focused Swift diffs; keep AppKit overlay/pin logic in Controllers
- No App Sandbox unless there is a clear entitlement plan
- Match EggplantFred patterns for MenuBarExtra, permissions prompts, signing

## Git

- Identity: `uniquejava` / `uniquejava@gmail.com`
- Commit only when the user asks
