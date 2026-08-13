# Selection refine + toolbar

Status: **implemented** (Snipaste-style refine + icon toolbar + pin chrome + save).  
Annotate live: **shape**, **arrow**, **pencil**, **marker**, **mosaic**, **text**, **step** (+ in-session undo/redo). **OCR** copies selection text to the clipboard and dismisses (bubble-pop on success). Magnifier remains a stub.

Document / undo stacks / `,` / `.` / disk: [`snip-document-architecture.md`](snip-document-architecture.md) (P0–P4).

When a tool’s section grows past ~40–50 lines or a new tool lands, spin it out to `docs/annotate-<tool>.md` and leave a one-line link here. **Do not split yet.**

## Shared rules (all annotate tools)

- Annotate works on the **full freeze overlay**, not only inside the blue selection.
- Pin / Copy / Save **do not expand** the crop: outside marks are **clipped** from the baked image.
- Outside marks stay in `AnnotationDocument` so `,` / `.` can still show and drag them back into the rect.
- Confirm composites marks onto the crop, then tears down the overlay.
- Esc in refine (not editing text) cancels the whole snip.
- Delete removes the selected mark. Undo / redo: toolbar + ⌘Z / ⇧⌘Z.

## Refine shell

1. F1 / **Snip** → freeze each display → dim overlay → drag region (or click-lock window).
2. Mouse-up (large enough) → **refine** (no capture yet):
   - Blue selection + **8 circular** handles; interior moves; handles resize; size label `W × H`.
   - Toolbar: white rounded card (≈6pt), icon row + dividers, **right-aligned** under selection (≈4pt gap; flips above near bottom).
3. Actions: **Cancel (✕)** / **Pin** / **Save** / **Copy** / **OCR** (+ Esc / Return for primary).

### Snip vs Snip and copy

| Entry | Default primary (Return) | Notes |
|-------|--------------------------|--------|
| **Snip** / F1 | Pin | Copy still on toolbar |
| **Snip and copy** / ⌘F1 | Copy | Pin still on toolbar |

## Toolbar layout (Snipaste parity)

```
[ shape† | arrow | pen† | marker‖ | mosaic¶ | T‡ | step§ | magnifier | eraser ]
| [ OCR | undo | redo ]
| [ ✕ | pin | save | copy | … ]

† Shape: [ thin | med | thick | fill ] | [ rect | oval ] | [ line-style ▾ ] | [ preview 24 + palette 2×10 ]
  Arrow: [ thin | med | thick ] | [ start ▾≈32 | body ▾ | end ▾≈32 | caps Switch ] | [ preview 24 + palette 2×10 ]
  Pen: same card without fill / rect / oval
  Palette chips ≈11pt, gap ≈2pt
‖ Marker: [ · | ·· | ··· ] | [ rect region | oval region ] | [ preview 24 + palette 2×10 ]  (sizes 14/18/24 freehand; rect/oval = area highlight)
¶ Mosaic: [ · | ·· | ··· ] | [ rect region | oval region ] | [ preview | slider 3…24 | value ]  (sizes 14/18/24 freehand; rect/oval = area blur)
‡ Text: [ B | I | bg ] | [ size ▾ ] | [ preview 24 + palette 2×10 ]
§ Step: [ filled | outline | plain ] | [ size ▾ ] | [ preview 24 + palette 2×10 ]
  More stub / disabled
```

## Tools

### Shape

- Sub-toolbar: stroke widths / fill | rect ↔ oval | line-style (5 Snipaste dashes; disabled when filled) | color grid.
- Shift while dragging → square / circle.
- Hit zones: interior → draw nested (white ＋); border → move; handles → resize.
- Style / kind changes apply to selection (or next draw).

### Arrow

- Sub-toolbar: stroke widths | start ▾ (~32pt) | body ▾ (shared line-style pill) | end ▾ (~32pt) | caps Switch | color grid.
- Cap chips show a **short stub + small tip** with padding (not full-width shafts). Menu rows use the same compact footprint (icon-only, no English labels).
- Start / end caps: plain, bar, circle, diamond, open chevron (default end; shaft to tip), filled triangle, hollow triangle. Body reuses `StrokeLineStyle` (5 dashes).
- **Switch** (Snipaste): stacked miniature — top = armed caps (current or last-arrowed), bottom = plain line. Active row dark / inactive light. Tap strips arrowheads ↔ restores last armed caps (does **not** force double-ended). Press nudges glyphs down; release restores. One divider before the palette (no double rule).
- Geometry: `AnnotationPayload.arrow(start:end:style:caps:)` in selection-local points. Drag start→end; Shift → 45° snap; auto-select after draw.
- Edit: filled start / hollow end square handles; drag shaft to move; no 8-handle resize chrome.
- Disk: `type: "arrow"` with `points: [start, end]`, `style`, `startCap` / `endCap` ints (stable raw values).

### Pencil

- Sub-toolbar: stroke + line-style + color (no fill / kind).
- Color reticle; mouse-down hides cursor. Freehand; Shift → straight any angle.
- No resize chrome; no auto-select after stroke. While pencil is armed, existing pencil strokes draw-through (keep reticle for edge tracing); hold **⌘** for temporary move (four-arrow + drag). Other annotate tools still hit-move pencil strokes.
- Deferred: if dense sampling (~0.15pt + 120Hz) lags or bloats history, simplify polyline on mouse-up (RDP).

### Marker

- Sub-toolbar: brush **14 / 18 / 24** (three sized dots → freehand smear) | **rect / oval region** (drag to highlight an area) | **color card** (preview 24 + palette 2×10) — same layout as mosaic, with color instead of blur intensity.
- Freehand: stroke sampling; Shift → straight; mouse-down hides cursor. No resize chrome / no auto-select after stroke.
- Region: drag like mosaic; Shift → square / circle; entire rect/oval is highlighted. **Edit chrome**: while drawing / moving / resizing → **1 device-pixel solid** contrast hairline; after mouse-up (selected idle) → **handles only** (no border); **mouseover** on a non-selected region → dashed contrast outline (like text hover). Hit mark to move; handles resize.
- Effect: **multiply** blend (Snipaste highlighter — keeps contrast on dark UIs; light glyphs tint brightly; black occludes). Near-white swatches fall back to sourceOver wash. **Vector** stroke/region data only (P4). Default color yellow.
- Toolbar icon: SF Symbol `paintbrush.pointed`.
- Disk: `type: "marker"` with `markerStyle` (brushWidth / color) plus either stroke `points` or region `kind` + `rect`.

### Mosaic

- Sub-toolbar: brush **14 / 18 / 24** (three sized dots → freehand smear) | **rect / oval region** (drag to blur an area) | intensity **3…24** with live blur preview left of the slider.
- Freehand: stroke sampling; Shift → straight; mouse-down hides cursor. No resize chrome / no auto-select after stroke.
- Region: drag like shape; Shift → square / circle; entire rect/oval is blurred. **Edit chrome** (not the thick shape stroke): **1 device-pixel hairline** — black on light freeze, white on dark; **solid while dragging**, **dashed after mouse-up** with **8 resize handles** (auto-select). Hit mark to move; handles resize.
- Effect: **gaussian blur** (`CIGaussianBlur`; full-res below intensity 8, half-res soft pass above) sampled from freeze/base at draw time — **vector stroke/region data only** (P4; never mutates `baseImage`). Intensity 3…24 maps to ~0.35…20 pt (ease-in so 3…5 stay readable); sample pad ≈ 3.5σ.
- No color palette.

### Text

- Sub-toolbar: Bold / Italic / background | font size | color (system UI font; no family / rotation yet).
- Click anywhere on freeze → place + inline edit (click = left edge + vertical center of the first line).
- **Edit chrome:** 1px hairline; white border + white caret on dark backdrops, black + black on light (not the palette color). Transparent fill unless bg toggle.
- Frame hugs glyphs with tiny padding (~2pt); **grows with text width** (including IME preedit before commit); soft-wrap only near screen edge. Empty editor is caret-wide (no trailing blank).
- **Hit / cursor:** blank overlay (selection or dimmed) → I-beam for place-new; near text edge / hairline (+~2pt outside) → four-arrow move; deeper interior → I-beam + click to edit. Toolbar only → arrow. While editing: border drag **live-moves** the chrome without ending edit; interior still types. Cursor is re-applied after caret blink so AppKit cannot reset to the system arrow while the pointer is still. Hover → 1px contrast dashed outline (black on light freeze, white on dark; clears on mouse-out). No resize handles.
- Esc ends edit only; Return = newline (not confirm). Empty on end-edit → drop mark.

### OCR

- Toolbar **Recognize Text** (`doc.text.viewfinder`): Vision OCR on the **unannotated** selection crop (zh-Hans / zh-Hant / en-US).
- Dismisses the overlay immediately after crop (no result UI). On non-empty text → pasteboard + short bubble-pop sound (`Resources/ocr-success.wav`). Empty / failure → silent, clipboard unchanged.
- Does **not** append to snip history.

### Step

- Sub-toolbar: **filled** / **outline** / **plain** chrome | size ▾ | color grid.
- Defaults: **filled**, size **4**, cyan (last-used prefs override).
- Cursor is a live badge of the **next** number (current style) — click stamps at the hotspot; cursor then advances.
- Place: click anywhere on freeze → `max(existing)+1` (or `1`); auto-select; drag to move. No resize handles; no inline edit.
- Styles: filled = color disk + white digit; outline = color ring + color digit; plain = color digit only (toolbar chip uses a dashed plate so it still reads as a button).
- Size levels map to diameter (`10 + size×3.2` pt). Style / size / color apply to selection (or next place).
- Edit chrome: dashed contrast square around the badge (Snipaste).
- Disk: `type: "step"` with `number`, `points: [center]`, `stepStyle` (`kind` / `size` / `color`).
- P4: vector payload only; mutate via `AnnotationHistory`; unknown types skip on load.

## Pin chrome

- Soft glow (`CALayer.shadowRadius`); no hard border. Active blue / inactive gray.
- Drag; Esc / double-click closes. Level `.statusBar` (above apps; below snip overlay).

## Code

- Overlay controller: [`SelectionOverlayController.swift`](../EggplantShot/Controllers/SelectionOverlayController.swift)
- Overlay panels: [`SelectionOverlayPanel.swift`](../EggplantShot/Controllers/SelectionOverlayPanel.swift)
- Toolbar (+ palette): [`RefineToolbarController.swift`](../EggplantShot/Controllers/RefineToolbarController.swift)
- Text field editor: [`TextAnnotationEditor.swift`](../EggplantShot/Controllers/TextAnnotationEditor.swift)
- Model / bake / history: [`Annotation/`](../EggplantShot/Annotation/)
- Confirm: [`SnipController.swift`](../EggplantShot/Controllers/SnipController.swift)
- OCR: [`TextRecognizer.swift`](../EggplantShot/Capture/TextRecognizer.swift) + [`FeedbackSound.swift`](../EggplantShot/Capture/FeedbackSound.swift)
- Save: [`ImageFileSaver.swift`](../EggplantShot/Capture/ImageFileSaver.swift)
- Pin: [`PinBoardController.swift`](../EggplantShot/Controllers/PinBoardController.swift)

## Acceptance checklist

- [x] Refine: blue rect + 8 handles; move / resize; size label; toolbar placement
- [x] Cancel / Esc; confirm crops then tears down; ⌘F1 primary = Copy
- [x] Pin soft glow + drag
- [x] Shape / arrow / pencil / marker / mosaic / text / step: draw·edit on full overlay; bake clips outside marks; document keeps them
- [x] OCR: recognize selection → clipboard + bubble-pop; dismiss overlay; no result UI
- [x] Undo / redo; debug build succeeds
