# AGENTS.md — EggplantShot

## What this is

Native **macOS 15+** Snipaste-style screenshot utility (MVP).

- Menu bar only (`LSUIElement`); Dock icon only while Preferences is open
- Global hotkeys via `CGEvent` tap (Accessibility required)
- Area capture → pin floating image, or copy to clipboard
- Screen Recording permission required for capture

Inspiration: Snipaste menu + pin workflow.

## Stack

| Layer | Tech |
|-------|------|
| UI | SwiftUI `MenuBarExtra` + AppKit overlays / pin panels |
| Hotkey | `CGEvent` tap (multi-binding) |
| Capture | ScreenCaptureKit (`SCScreenshotManager`) + crop |
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
  Capture/ScreenPermissions.swift + ScreenCapturer.swift + WindowHitTester.swift + ImageFileSaver.swift + ClipboardPaster.swift
  Controllers/SnipController.swift
  Controllers/SelectionOverlayController.swift + SelectionOverlay+*.swift (mouse / draft / hit-test / style / text / geometry / history / toolbar)
  Controllers/RefineToolbarController.swift + RefineToolbar+*.swift + RefineToolbarViews.swift + Tooltip / HoverChromeCard / PaletteSwatch / IntensitySlider
  Controllers/TextAnnotationEditor.swift
  Controllers/SelectionOverlayPanel.swift + SelectionOverlayNSView.swift
  Controllers/PinBoardController.swift + PinPanel.swift
  Annotation/  # Annotation(+Tool/Geometry) + Drawing(+Tool) + Coding(+Tool) + Document/Compositor + ContrastChrome
  History/SnipRecord.swift + SnipHistoryStore.swift
  UI/StatusMenuContent.swift + SettingsView.swift + AboutView.swift
  Assets.xcassets/
  Info.plist                 # LSUIElement = true
  EggplantShot.entitlements  # App Sandbox OFF
```

## Product behaviour to preserve

1. **Capture (F1)** → freeze displays (full-screen snapshot as overlay backdrop) → hover highlights the window under the cursor → click to lock (or drag to free-select) → refine (blue rect, circular handles, Snipaste-style icon toolbar) → Pin/Copy → floating pin with soft glow (blue when key, gray when not; drag; scroll wheel ±10% zoom with brief top-left % badge; Esc / double-click closes).
2. **Capture and copy (⌘F1)** → same freeze + hover/drag select; on window lock or drag mouse-up, crop + copy to clipboard immediately (no refine toolbar / annotate).
3. Confirm / Return uses the freeze crop (or history playback base); then overlay tears down. Successful Pin/Copy/Save also archives an editable `SnipRecord`.
4. **Esc** during drag/refine: abort gesture → disarm tool → deselect mark; with marks, first Esc shows a tip and second Esc discards (toolbar ✕ always discards). Esc on a pin closes that pin only.
5. Pins use `.statusBar` level (above ordinary windows; below capture overlay).
6. **Paste (F3)** → clipboard → floating pin (image; HEX/RGB color → swatch; plain/HTML text → text image; image file → image, second paste → path text). Ignored while capture overlay is active.
7. **Disable hotkeys** pauses the event tap (persisted).
8. Preferences via `SettingsLink` / `openSettings` (not `showSettingsWindow:`).
9. Without Accessibility, global hotkeys do nothing. Without Screen Recording, capture fails with a prompt.
10. During an active **Capture** (refine), **`,`** / **`.`** step through prior capture records (older / newer).

## Annotate extensibility (P4 — always)

New annotate tools **must** follow these without being asked. Details: [`docs/snip-document-architecture.md`](docs/snip-document-architecture.md).

1. Add an `AnnotationPayload` case + `Annotation+<tool>.swift` (inits/accessors) + `AnnotationCoding+<tool>.swift` (encode/decode) + draw + hit-test together; history / store / confirm paths stay unchanged. Also add cases in `Annotation+Geometry.swift` and the encode/decode switches in `AnnotationCoding.swift`.
2. Mutate marks **only** via `AnnotationHistory` (`commit` / `beginGesture`–`endGesture`) — never edit `marks` / `selectedID` from gesture code directly.
3. Store effects as **data** (strokes / regions / style), not destructive pixels on `baseImage`. Sample the freeze/base at draw / bake time (e.g. mosaic `CIGaussianBlur`).
4. Do **not** bake into `baseImage` until Pin / Copy / Save; `,` / `.` always restore unannotated base + vector document.
5. Disk: new `type` discriminator; unknown types skip on load. Bump `schemaVersion` only when the meta shape itself changes.

## Next (not done yet)

→ Annotate tools in: shape + arrow + pencil + marker + mosaic + text + step + magnifier + eraser + OCR + undo/redo + snip history (`,` / `.`, disk) + `AnnotationPayload`. See [`docs/selection-refine.md`](docs/selection-refine.md) (shared refine rules + per-tool notes; split to `annotate-*.md` only when a tool section grows).

→ Mosaic blur samples freeze/base only (not prior marks). Smearing over pencil/ink on a dark freeze paints opaque freeze pixels on top of the ink (looks “all black”). Need a cheap way to sample freeze **+ prior marks** without full-screen recomposite every tip — see deferred note under Mosaic in `docs/selection-refine.md`.


## Prefer

- Small focused Swift diffs; keep AppKit overlay/pin logic in Controllers
- No App Sandbox unless there is a clear entitlement plan
- Match EggplantFred patterns for MenuBarExtra, permissions prompts, signing

## Git

- Identity: `uniquejava` / `uniquejava@gmail.com`
- Commit only when the user asks
