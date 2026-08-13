# Selection refine + toolbar

Status: **implemented** (Snipaste-style refine + icon toolbar + pin chrome + save).  
Annotate live: **shape**, **pencil**, **text** (+ in-session undo/redo). Arrow / marker / mosaic / step / OCR / magnifier remain stubs.

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
3. Actions: **Cancel (✕)** / **Pin** / **Save** / **Copy** (+ Esc / Return for primary).

### Snip vs Snip and copy

| Entry | Default primary (Return) | Notes |
|-------|--------------------------|--------|
| **Snip** / F1 | Pin | Copy still on toolbar |
| **Snip and copy** / ⌘F1 | Copy | Pin still on toolbar |

## Toolbar layout (Snipaste parity)

```
[ shape† | arrow | pen† | marker | mosaic | T‡ | step | magnifier | eraser ]
| [ OCR | undo | redo ]
| [ ✕ | pin | save | copy | …§ ]

† Shape: [ thin | med | thick | fill ] | [ rect | oval ] | [ line-style ▾ ] | [ preview 24 + palette 2×10 ]
  Pen: same card without fill / rect / oval
  Palette chips ≈11pt, gap ≈2pt
‡ Text: [ B | I | bg ] | [ size ▾ ] | [ preview 24 + palette 2×10 ]
§ More stub / disabled
```

## Tools

### Shape

- Sub-toolbar: stroke widths / fill | rect ↔ oval | line-style (5 Snipaste dashes; disabled when filled) | color grid.
- Shift while dragging → square / circle.
- Hit zones: interior → draw nested (white ＋); border → move; handles → resize.
- Style / kind changes apply to selection (or next draw).

### Pencil

- Sub-toolbar: stroke + line-style + color (no fill / kind).
- Color reticle; mouse-down hides cursor. Freehand; Shift → straight any angle.
- No resize chrome; hit stroke to move. No auto-select after stroke.
- Deferred: if dense sampling (~0.15pt + 120Hz) lags or bloats history, simplify polyline on mouse-up (RDP).

### Text

- Sub-toolbar: Bold / Italic / background | font size | color (system UI font; no family / rotation yet).
- Click anywhere on freeze → place + inline edit (click = left edge + vertical center of the first line).
- **Edit chrome:** 1px hairline; white border + white caret on dark backdrops, black + black on light (not the palette color). Transparent fill unless bg toggle.
- Frame hugs glyphs with tiny padding (~2pt); **grows with text width** (including IME preedit before commit); soft-wrap only near screen edge. Empty editor is caret-wide (no trailing blank).
- **Hit / cursor:** inside, near the edge (or on the hairline) → move (open hand); deeper interior → I-beam + click to edit. Outside the frame is always place-new. Hover → 1px white dashed outline (clears on mouse-out). No resize handles.
- Esc ends edit only; Return = newline (not confirm). Empty on end-edit → drop mark.

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
- Save: [`ImageFileSaver.swift`](../EggplantShot/Capture/ImageFileSaver.swift)
- Pin: [`PinBoardController.swift`](../EggplantShot/Controllers/PinBoardController.swift)

## Acceptance checklist

- [x] Refine: blue rect + 8 handles; move / resize; size label; toolbar placement
- [x] Cancel / Esc; confirm crops then tears down; ⌘F1 primary = Copy
- [x] Pin soft glow + drag
- [x] Shape / pencil / text: draw·edit on full overlay; bake clips outside marks; document keeps them
- [x] Undo / redo; debug build succeeds
