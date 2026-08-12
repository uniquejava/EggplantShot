# EggplantShot

Native **macOS 14+** Snipaste-style screenshot tool — menu bar only, SwiftUI + AppKit.

## Docs

| Doc | Contents |
|-----|----------|
| [AGENTS.md](./AGENTS.md) | Architecture & agent notes |
| [docs/selection-refine.md](./docs/selection-refine.md) | Selection refine: blue rect, handles, toolbar |

## Requirements

- macOS 14 or later
- Xcode 15+ (sign with Apple Development team `M5J7K9HVYB`)
- **Accessibility** for global hotkeys (`CGEvent` tap)
- **Screen Recording** for capture

## Run

```bash
open EggplantShot.xcodeproj
# or
xcodebuild -scheme EggplantShot -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/EggplantShot.app
```

On first launch, grant Accessibility and Screen Recording when prompted.

## Features (MVP)

- Menu bar extra (LSUIElement) with Snipaste-like menu
- **Snip** / **F1** — area select → refine (handles + Snipaste-style toolbar) → pin with soft glow
- **Snip and copy** / **⌘F1** — same refine UX; primary action copies to clipboard
- Pinned images: drag, Esc / double-click to close, stay above other windows
- **Hide/Show all images** / **⇧F3**
- Disable hotkeys
- Preferences: permission status + hotkey list

## Project layout

- `EggplantShot/EggplantShotApp.swift` — `@main`, MenuBarExtra, AppState
- `EggplantShot/Hotkey/` — multi-binding `CGEvent` tap
- `EggplantShot/Capture/` — permissions + `CGDisplayCreateImage` crop
- `EggplantShot/Controllers/` — selection overlay, pin board, snip orchestration
- `EggplantShot/UI/` — status menu, preferences
