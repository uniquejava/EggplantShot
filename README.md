# EggplantShot

Native **macOS 15+** screenshot tool in the menu bar — Snipaste-style capture, annotate, pin, and paste.

[简体中文](./README_zh.md)

![EggplantShot refine toolbar with annotations](./docs/screenshot.png)

## Features

- **Capture** — freeze the screen, click a window or drag a region, refine, annotate, then pin / copy / save
- **Capture and copy** — select and copy immediately (no toolbar)
- **Annotate** — shape, arrow, pencil, marker, mosaic, text, step numbers, magnifier, eraser; undo / redo
- **OCR** — recognize **QR codes or text** from the selection → clipboard
- **Paste** — turn the clipboard into a floating pin (image, color swatch, or text sticky)
- **Pins** — stay on top, drag, scroll to zoom, hide/show all

## Hotkeys (defaults)

| Action | Shortcut |
|--------|----------|
| Capture | `F1` |
| Capture and copy | `⌘F1` |
| Paste (clipboard → pin) | `F3` |
| Hide / show all pins | `⇧F3` |

Hotkeys can be changed in Preferences. Menu bar → **Disable hotkeys** pauses them globally.

## Permissions

| Permission | Why |
|------------|-----|
| **Accessibility** | Global hotkeys |
| **Screen Recording** | Capture |

## Build & run

Requires macOS 15+ and Xcode 16+.

```bash
killall EggplantShot 2>/dev/null
xcodebuild -project EggplantShot.xcodeproj -scheme EggplantShot \
  -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/EggplantShot.app
```

Or: `open EggplantShot.xcodeproj`

Always use `-derivedDataPath build` and kill the running app first — otherwise you may launch a stale binary.

## Docs

- [User guide](./docs/user-guide.md)
- [AGENTS.md](./AGENTS.md) — architecture notes for contributors / agents
