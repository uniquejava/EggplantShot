# Selection refine + toolbar

Status: **implemented** (Snipaste-style refine + icon toolbar + pin chrome).  
Deferred: annotate / save / OCR / undo etc. are **UI stubs only** (greyed out).

## Behaviour

1. F1 / **Snip** → dim overlay → drag region.
2. On mouse-up (if large enough) → **refine mode** (no capture yet):
   - Blue selection rect + **8 circular** resize handles.
   - Drag inside rect to move; drag handles to resize.
   - Size label near the rect (`W × H`).
   - **Toolbar**: white rounded-rect (≈6pt corner radius), icon row with dividers, **right-aligned** to the selection, **≈4pt** gap below (flips above if near screen bottom).
3. Working toolbar actions: **Cancel (✕)** / **Pin** / **Save** / **Copy** (+ Esc / Return for primary).
4. On confirm → tear down overlay → capture final rect → pin, clipboard, or save panel.
5. Esc in refine cancels the whole snip.

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
[ shape | arrow | pen | marker | mosaic | T | step | magnifier | eraser ]
| [ OCR | undo | redo ]
| [ ✕ | pin | save | copy | …† ]
```

† More is stub / disabled today.

## Code

- Overlay + toolbar: [`SelectionOverlayController.swift`](../EggplantShot/Controllers/SelectionOverlayController.swift)
- Capture after confirm: [`SnipController.swift`](../EggplantShot/Controllers/SnipController.swift)
- Save panel: [`ImageFileSaver.swift`](../EggplantShot/Capture/ImageFileSaver.swift)
- Pin glow / drag: [`PinBoardController.swift`](../EggplantShot/Controllers/PinBoardController.swift)

## Acceptance checklist

- [x] Mouse-up after drag shows blue rect + 8 handles; no pin/clipboard yet
- [x] Handles resize; interior drag moves; size label updates
- [x] Toolbar under (or above) selection, right-aligned; Pin / Save / Copy / Cancel work
- [x] Esc cancels refine without capturing
- [x] Confirm tears down overlay, then captures final rect
- [x] ⌘F1 entry; primary action matches mode
- [x] Pin soft glow + drag
- [x] Debug build succeeds
