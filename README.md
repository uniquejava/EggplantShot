# EggplantShot

Native **macOS 15+** Snipaste-style screenshot tool — menu bar only, SwiftUI + AppKit.

## Docs

| Doc | Contents |
|-----|----------|
| [AGENTS.md](./AGENTS.md) | Architecture & agent notes |
| [docs/selection-refine.md](./docs/selection-refine.md) | Selection refine: blue rect, handles, toolbar |

## Requirements

- macOS 15 or later
- Xcode 16+ (sign with Apple Development team `M5J7K9HVYB`)
- **Accessibility** for global hotkeys (`CGEvent` tap)
- **Screen Recording** for capture

## Run

Stable Debug path is `build/` (gitignored). Always use `-derivedDataPath build`, and kill the running menu-bar instance before reopen — otherwise you may still be on an old binary.

```bash
killall EggplantShot 2>/dev/null
xcodebuild -project EggplantShot.xcodeproj -scheme EggplantShot \
  -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/EggplantShot.app
```

Or open the project in Xcode: `open EggplantShot.xcodeproj`

On first launch, grant Accessibility and Screen Recording when prompted.

## Features (MVP)

- Menu bar extra (LSUIElement) with Snipaste-like menu
- **Capture** / **F1** — area select → refine (handles + Snipaste-style toolbar) → optional annotate → pin with soft glow
- **Capture and copy** / **⌘F1** — area select → copy to clipboard immediately (no refine / annotate)
- **Shape annotate** — stroke widths / fill / rect·ellipse / line style / color sub-toolbar; draw, move, resize; baked into pin/copy/save
- **Text annotate** — click-to-place + inline edit; Bold / Italic / background / size / color; move / resize; baked into pin/copy/save
- **OCR** — Recognize Text on the toolbar: copy selection text to clipboard, bubble-pop sound, dismiss (no result UI)
- **Paste** / **F3** — clipboard → floating pin (image / color HEX·RGB / text·HTML / image file)
- Pinned images: drag, Esc / double-click to close, stay above other windows
- **Hide/Show all images** / **⇧F3**
- Disable hotkeys
- Preferences: permission status + hotkey list

## Project layout

- `EggplantShot/EggplantShotApp.swift` — `@main`, MenuBarExtra, AppState
- `EggplantShot/Hotkey/` — multi-binding `CGEvent` tap
- `EggplantShot/Capture/` — permissions + ScreenCaptureKit freeze/crop
- `EggplantShot/Controllers/` — selection overlay, pin board, snip orchestration
- `EggplantShot/UI/` — status menu, preferences
