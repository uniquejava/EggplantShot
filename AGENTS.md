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

1. **Snip (F1)** → drag region → **refine** (blue rect, 8 handles, toolbar) → Pin (or Copy) → floating image with focus ring (blue glow when key, gray when not; Esc / double-click closes).
2. **Snip and copy (⌘F1)** → same refine UX; toolbar primary is Copy (Pin still available).
3. Capture only after toolbar confirm / Return; overlay must be torn down before capture so it is not in the image.
4. **Esc** during drag or refine cancels the snip (no pin / clipboard). Esc on a pinned image closes that pin only.
5. Pinned images use a high window level (`.statusBar`) so they stay above ordinary app windows; still below the snip overlay.
6. **Disable hotkeys** pauses the event tap (persisted).
7. Preferences via `SettingsLink` / `openSettings` (not `showSettingsWindow:`).
8. Without Accessibility, global hotkeys do nothing. Without Screen Recording, capture fails with a prompt.

## Next (not done yet)

→ Annotate / save / magnifier stubs — see deferred list in [`docs/selection-refine.md`](docs/selection-refine.md).

## Prefer

- Small focused Swift diffs; keep AppKit overlay/pin logic in Controllers
- No App Sandbox unless there is a clear entitlement plan
- Match EggplantFred patterns for MenuBarExtra, permissions prompts, signing

## Git

- Identity: `uniquejava` / `uniquejava@gmail.com`
- Commit only when the user asks
