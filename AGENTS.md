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

## Build / run (agents — always)

**Always** pass `-derivedDataPath build` so the binary lands at a stable path. Without it, `xcodebuild` writes to `~/Library/Developer/Xcode/DerivedData/...` and `open build/...` launches a **stale** app.

Menu-bar apps also keep the old process on a second `open` — **kill first**.

```bash
killall EggplantShot 2>/dev/null
xcodebuild -project EggplantShot.xcodeproj -scheme EggplantShot \
  -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/EggplantShot.app
```

Do **not** open the DerivedData path, and do **not** skip `-derivedDataPath build`.
`build/` is gitignored.

## Layout

```
EggplantShot/
  EggplantShotApp.swift
  Hotkey/HotkeyMonitor.swift + HotkeyShortcut.swift
  Capture/ScreenPermissions.swift + ScreenCapturer.swift + WindowHitTester.swift + ImageFileSaver.swift
  Controllers/SnipController.swift
  Controllers/SelectionOverlayController.swift
  Controllers/PinBoardController.swift
  Annotation/AnnotationModels.swift + AnnotationCompositor.swift
  UI/StatusMenuContent.swift + SettingsView.swift + AboutView.swift
  Assets.xcassets/
  Info.plist                 # LSUIElement = true
  EggplantShot.entitlements  # App Sandbox OFF
```

## Product behaviour to preserve

1. **Snip (F1)** → freeze displays (full-screen snapshot as overlay backdrop) → hover highlights the window under the cursor → click to lock (or drag to free-select) → refine (blue rect, circular handles, Snipaste-style icon toolbar) → Pin/Copy → floating pin with soft glow (blue when key, gray when not; drag; Esc / double-click closes).
2. **Snip and copy (⌘F1)** → same refine UX; Return primary is Copy.
3. Confirm / Return crops from the freeze snapshot (not a live recapture); then overlay tears down.
4. **Esc** during drag/refine cancels the snip. Esc on a pin closes that pin only.
5. Pins use `.statusBar` level (above ordinary windows; below snip overlay).
6. **Disable hotkeys** pauses the event tap (persisted).
7. Preferences via `SettingsLink` / `openSettings` (not `showSettingsWindow:`).
8. Without Accessibility, global hotkeys do nothing. Without Screen Recording, capture fails with a prompt.

## Next (not done yet)

→ Remaining annotate tools (arrow / pen / marker / mosaic / text / step), OCR, undo/redo, magnifier — see [`docs/selection-refine.md`](docs/selection-refine.md). Rectangle annotate is in. Split overlay only when annotation needs its own canvas.

## Prefer

- Small focused Swift diffs; keep AppKit overlay/pin logic in Controllers
- No App Sandbox unless there is a clear entitlement plan
- Match EggplantFred patterns for MenuBarExtra, permissions prompts, signing

## Git

- Identity: `uniquejava` / `uniquejava@gmail.com`
- Commit only when the user asks
