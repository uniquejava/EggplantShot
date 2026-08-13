# Selection refine + toolbar

Status: **implemented** (Snipaste-style refine + icon toolbar + pin chrome + save).  
Annotate: **shape** (rect / ellipse) + **pencil** (freehand; Shift → straight any angle) + **in-session undo/redo**. Other annotate / OCR remain stubs.

Undo/redo, editable snip history (`,` / `.`), and on-disk records: see [`snip-document-architecture.md`](snip-document-architecture.md) (P0–P4 done).

## Behaviour

1. F1 / **Snip** → freeze each display → dim overlay on frozen backdrop → drag region.
2. On mouse-up (if large enough) → **refine mode** (no capture yet):
   - Blue selection rect + **8 circular** resize handles.
   - Drag inside rect to move; drag handles to resize.
   - Size label near the rect (`W × H`).
   - **Toolbar**: white rounded-rect (≈6pt corner radius), icon row with dividers, **right-aligned** to the selection, **≈4pt** gap below (flips above if near screen bottom).
3. Working toolbar actions: **Cancel (✕)** / **Pin** / **Save** / **Copy** (+ Esc / Return for primary).
4. **Shape annotate** (main toolbar rectangle button):
   - Opens a sub-toolbar with stroke / shape / line-style / color:
     1. **Stroke / fill** (items 1–4): thin / medium / thick outline, or fill. Mutually exclusive.
     2. **Shape kind** (items 5–6): rectangle ↔ ellipse. Mutually exclusive. Hold **Shift** while dragging for square / circle.
     3. **Border style** (item 7): dropdown — Snipaste 5 patterns: solid / long dash / short dash / long–short / long–short–short (disabled while fill is selected).
     4. **Color**: current swatch preview + 2×10 Snipaste-like preset grid.
   - Pointer zones on an existing mark:
     - **Interior** → white “＋” cursor; drag draws a new shape (nesting allowed); does **not** move.
     - **Border** → open-hand cursor; drag moves the mark.
     - **Handles** → resize cursors; drag adjusts size.
   - Stroke / fill / line style / color / kind changes apply to the selected mark (or the next one drawn).
   - Delete removes the selected mark.
   - Confirm composites annotations onto the capture before pin / copy / save.
5. **Pencil annotate** (main toolbar pencil button):
   - Same sub-toolbar **stroke / line-style / color** (fill + rect/oval hidden).
   - Hover: stroke-colored reticle (center dot + four thin arms). Mouse-down hides the cursor; only the ink tip shows.
   - Freehand polyline (dense live sampling + 120Hz tip poll). Hold **Shift** for a straight line that follows the tip at any angle.
   - No resize handles (keeps freehand uncluttered). Hit the stroke to move; Delete works if selected.
   - After mouse-up, the stroke is **not** auto-selected (ready to draw the next segment).
6. On confirm → crop final rect from freeze snapshot → tear down overlay → (optional annotate bake) → pin, clipboard, or save panel.
7. Esc in refine cancels the whole snip.

### Deferred (pencil)

- Live sampling is dense (~0.15pt + 120Hz poll) for follow-feel. If long strokes lag or history JSON bloats, **simplify the polyline on mouse-up** (e.g. Ramer–Douglas–Peucker) while keeping live sampling dense.

### Snip vs Snip and copy

| Entry | Default primary (Return) | Notes |
|-------|--------------------------|--------|
| **Snip** / F1 | Pin | Copy still on toolbar |
| **Snip and copy** / ⌘F1 | Copy | Pin still on toolbar |

## Pin chrome

- Soft outer glow ≈ CSS `box-shadow: 0 0 blur color` (`CALayer.shadowRadius`); **no hard border**.
- Active: blue glow; inactive: gray glow.
- Draggable (`performDrag`); Esc / double-click closes.
- Window level `.statusBar` (above normal apps; below snip overlay).

## Toolbar layout (parity with Snipaste)

```
[ shape† | arrow | pen† | marker | mosaic | T | step | magnifier | eraser ]
| [ OCR | undo | redo ]
| [ ✕ | pin | save | copy | …‡ ]

† Shape expands options: [ thin | med | thick | fill ] | [ rect | oval ] | [ line-style ▾ ] | [ preview 24 + palette 2×10 ]
  Pen reuses the same card without fill / rect / oval: [ thin | med | thick ] | [ line-style ▾ ] | [ palette ]
  Palette chips ≈11pt, gap ≈2pt (Snipaste-measured).
‡ More is stub / disabled today.
```

## Code

- Overlay + toolbar: [`SelectionOverlayController.swift`](../EggplantShot/Controllers/SelectionOverlayController.swift)
- Annotation model / bake / history: [`Annotation/`](../EggplantShot/Annotation/)
- Capture after confirm: [`SnipController.swift`](../EggplantShot/Controllers/SnipController.swift)
- Save panel: [`ImageFileSaver.swift`](../EggplantShot/Capture/ImageFileSaver.swift)
- Pin glow / drag: [`PinBoardController.swift`](../EggplantShot/Controllers/PinBoardController.swift)

## Acceptance checklist

- [x] Mouse-up after drag shows blue rect + 8 handles; no pin/clipboard yet
- [x] Handles resize; interior drag moves; size label updates
- [x] Toolbar under (or above) selection, right-aligned; Pin / Save / Copy / Cancel work
- [x] Esc cancels refine without capturing
- [x] Confirm crops from freeze snapshot, then tears down overlay
- [x] ⌘F1 entry; primary action matches mode
- [x] Pin soft glow + drag
- [x] Shape tool: stroke/fill + rect/oval + line-style dropdown + 2×10 palette; draw / move / resize, bake into capture
- [x] Pencil tool: stroke + line-style + palette; color reticle; freehand / Shift any-angle; move (no resize chrome); bake into capture
- [x] Undo / Redo toolbar + ⌘Z / ⇧⌘Z restore annotation document states
- [x] Debug build succeeds
