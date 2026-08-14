# Selection refine + toolbar

Status: **implemented** (Snipaste-style refine + icon toolbar + pin chrome + save).  
Annotate live: **shape**, **arrow**, **pencil**, **marker**, **mosaic**, **text**, **step**, **magnifier**, **eraser** (+ in-session undo/redo). **OCR** copies selection text to the clipboard and dismisses (bubble-pop on success).

Document / undo stacks / `,` / `.` / disk: [`snip-document-architecture.md`](snip-document-architecture.md) (P0–P4).

When a tool’s section grows past ~40–50 lines or a new tool lands, spin it out to `docs/annotate-<tool>.md` and leave a one-line link here. **Do not split yet.**

## Shared rules (all annotate tools)

- Annotate works on the **full freeze overlay**, not only inside the blue selection.
- **Crop resize chrome stays** while any annotate tool is selected (8 handles on the blue export rect). Mark chrome wins on overlap; otherwise the **border strip** still resizes the crop. **Outside-edge expand is off** while a tool is armed (dimmed area is for annotate); it returns when the tool is toggled off / deselected. Interior of the crop still draws / places marks (does not move the selection).
- Moving / resizing / expanding the blue crop **does not move marks on the freeze** — selection-local geometry is rebased by the origin delta (marks stay glued to image content; only the export rect changes).
- **Hold Space** → temporary drag-move of the blue crop (open hand → closed hand while dragging; release Space to return to the current tool). Interior drag without Space does **not** move the crop.
- Pin / Copy / Save **do not expand** the crop: outside marks are **clipped** from the baked image.
- Outside marks stay in `AnnotationDocument` so `,` / `.` can still show and drag them back into the rect.
- Confirm composites marks onto the crop, then tears down the overlay.
- Esc ladder (not editing text): abort in-progress drag → disarm tool → deselect mark → with marks, first Esc shows “Press Esc again to discard”, second Esc discards (toolbar **✕** still immediate).
- Delete removes the selected mark. Undo / redo: toolbar + ⌘Z / ⇧⌘Z.
- Refine tool / action hotkeys (armed after selection; ignored while editing text or mid-drag):
  **V** move · **A** shape · **S** arrow · **D** pen · **F** marker · **M** mosaic · **I** text · **N** number · **E** eraser · **P** pin · **O** OCR · **⌘S** save · **⌘C** copy.
  **R** / **G** / **B** → palette red / green / cyan (selected colored mark, else armed tool; no-op for mosaic / eraser).
  ASDF row mnemonics: **A** ≈ ⌘A “select with a rect” · **S** ≈ S-curve arrow · **D**raw · **F** like a brush (highlight). **I** = Insert (text). **V** = move (Figma-style).
- **Hit / move vs draw:** **Move (V)** hits all marks for drag / resize (no draw); empty click deselects. Paint tools (**pencil** / **marker** / **mosaic** / **eraser**) always draw-through existing marks — switch to **V** to move, then back (e.g. **D**) to draw. Selected mark **handles** still resize without switching. **Step** draws through foreign marks so you can stamp on a shape border; existing step badges stay hit-to-move (**⌘** still moves other marks). Other object tools (shape / arrow / text / magnifier) keep hit-to-move on their targets; paint-like marks still draw-through under those tools (move via **V**).

## Refine shell

1. F1 / **Capture** → freeze each display → dim overlay → drag region (or click-lock window).
2. Mouse-up (large enough) → **refine** (no export yet):
   - Blue selection + **8 circular** handles; handles / border resize; size label `W × H`. Interior does **not** drag-move the crop unless **Space** is held (crop move is rare and not undoable). Outside click expands.
   - Toolbar: white rounded card (≈6pt), icon row + dividers, **right-aligned** under selection (≈4pt gap; flips above near bottom).
3. Actions: **Cancel (✕)** / **Pin** / **Save** / **Copy** / **OCR** (+ Esc / Return for primary).

### Capture vs Capture and copy

| Entry | After window lock / drag complete | Notes |
|-------|-----------------------------------|--------|
| **Capture** / F1 | Refine + toolbar; Return → Pin | Annotate / resize before Pin/Copy/Save |
| **Capture and copy** / ⌘F1 | Crop + copy immediately | No toolbar, no annotate; Esc still cancels while selecting |

## Toolbar layout (Snipaste parity)

```
[ move(V) | shape† | arrow | pen† | marker‖ | mosaic¶ | T‡ | step§ | magnifier | eraser♯ ]
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
♯ Eraser: [ · | ·· | ··· ] | [ rect region | oval region ]  (same first 5 as mosaic; punches marks only)
  Magnifier: [ thin | med | thick ] | [ rect | oval ] | [ includeAnnotations ] | [ scale preview + slider 1…6 + value ] | [ preview 24 + palette 2×10 ]
  More stub / disabled
```

## Tools

### Move (V)

- Select / drag any mark; resize via handles when selected. Does **not** create marks.
- Empty click deselects. No sub-toolbar.
- Shape **body** (rect / oval interior) is grabable in this mode; under the shape tool, interior still nest-draws and only the border moves.
- Prefer this for rearranging marks (paint tools no longer use **⌘** temporary move).

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
- Edit: hollow white square endpoint handles; drag shaft to move; no 8-handle resize chrome.
- Disk: `type: "arrow"` with `points: [start, end]`, `style`, `startCap` / `endCap` ints (stable raw values).

### Pencil

- Sub-toolbar: stroke + line-style + color (no fill / kind).
- Color reticle; mouse-down hides cursor. Freehand; Shift → straight any angle.
- No resize chrome; no auto-select after stroke. Under object tools, pencil strokes draw-through (keep reticle). Under paint tools, all marks draw-through — move via **V** (see Shared rules).
- Live sampling on mouse-drag only (~2pt spacing; no 120Hz tip poll); **mouse-up** runs RDP simplify so many strokes don’t bloat history / mosaic re-samples.

### Marker

- Sub-toolbar: brush **14 / 18 / 24** (three sized dots → freehand smear) | **rect / oval region** (drag to highlight an area) | **color card** (preview 24 + palette 2×10) — same layout as mosaic, with color instead of blur intensity.
- Freehand: stroke sampling; Shift → straight; keep translucent brush tip while stroking. No resize chrome / no auto-select after stroke.
- Region: drag like mosaic; Shift → square / circle; entire rect/oval is highlighted. **Edit chrome**: while drawing / moving / resizing → **1 device-pixel solid** contrast hairline; after mouse-up (selected idle) → **handles only** (no border); **mouseover** on a non-selected region → dashed contrast outline (like text hover). Under object tools: hit mark to move; handles resize. Under paint tools: draw-through (Shared rules); move via **V**.
- Effect: **multiply** blend (Snipaste highlighter — dark → darker, light glyphs → bright tint). Marks paint on a transparent offscreen layer for eraser, so multiply first stamps the freeze/base under the clip, then tints. Near-white swatches fall back to sourceOver wash. **Vector** stroke/region data only (P4). Default color yellow.
- Toolbar icon: SF Symbol `paintbrush.pointed`.
- Disk: `type: "marker"` with `markerStyle` (brushWidth / color) plus either stroke `points` or region `kind` + `rect`.

### Mosaic

- Sub-toolbar: brush **14 / 18 / 24** (three sized dots → freehand smear) | **rect / oval region** (drag to blur an area) | intensity **3…24** with live blur preview left of the slider.
- Freehand: stroke sampling; Shift → straight; keep translucent brush tip while stroking. No resize chrome / no auto-select after stroke.
- Region: drag like shape; Shift → square / circle; entire rect/oval is blurred. **Edit chrome** (not the thick shape stroke): **1 device-pixel hairline** — black on light freeze, white on dark; **solid while dragging**, **dashed after mouse-up** with **8 resize handles** (auto-select). Hit mark to move; handles resize.
- Effect: **gaussian blur** of freeze/base **plus whatever marks are already under it** (`CIGaussianBlur`; linear intensity 3…24 → sigma ~0.8…3.2 pt — see *Blur calibration* below). Path: hull crop → read the marks drawn so far out of the `MarksCanvas` (`snapshotCrop`) → composite over the freeze crop → blur → clip to stroke/region. Because the sample is *pixels already rendered*, a mosaic over an earlier mosaic sees that one's blurred output. **Vector** stroke/region data only (P4; never mutates `baseImage`).
- Hit: under object tools, mosaic marks draw-through (no move hand over blurred areas). Under paint tools, all marks draw-through (Shared rules). Move via **V** (region handles still work when selected).
- No color palette.

**Blur calibration.** `CIGaussianBlur.inputRadius` **is sigma**, and a thin stroke smears over
roughly ±2…3 sigma — so sigma has to stay small or a pencil line turns into a blob. Intensity
3…24 maps linearly to sigma **0.8…3.2 pt**, absolute (not scaled by brush width, matching
Photoshop's blur tool). Measured on a 2 pt stroke against a dark freeze:

| intensity | sigma | thickening | fine detail left |
|---|---|---|---|
| 3 | 0.80 pt | 1.7× | 21% |
| 6 | 1.14 pt | 2.1× | 5% |
| **10 (default)** | **1.60 pt** | **2.8×** | **0.1%** |
| 15 | 2.17 pt | 3.7× | 0% |
| 20 | 2.74 pt | 4.6× | 0% |
| 24 | 3.20 pt | 5.2× | 0% |

Two things this range is chosen to avoid. Sigma above ~3 pt **blooms past the brush** and gets
clipped to it, so perceived thickness starts tracking the brush width instead of the intensity —
the old 0.7…14 pt range saturated by intensity ~6, wasting most of the slider and making a 14 pt
and a 24 pt brush read as different strengths (5.9× vs 7.8× at the same setting). And detail is
already gone by ~1.5 pt, so the old default of ~5 pt was roughly 3× more blur than obscuring
needs — all of that excess went into fattening strokes.

**Not security-grade redaction at any setting.** Blurred and pixelated text is recoverable
(Hill et al., *On the (In)effectiveness of Mosaicing and Blurring as Tools for Document
Redaction*, PoPETs 2016 — 24 pt text recovered through a 45 px blur). Solid fill is the only safe
way to hide sensitive content.

Sampling design (mosaic / magnifier): marks render into a `MarksCanvas` (an owned bitmap), and a
mosaic reads the hull it is about to blur back out of it — so a mosaic over an earlier mosaic sees
that one's blurred pixels, and nothing re-derives prior marks from vectors. The overlay caches the
committed layer so a pencil drag does not re-blur every mosaic per frame. Full write-up, the two
rejected approaches, measurements, and the rules that must not be broken:
[`marks-rendering.md`](marks-rendering.md).

**Still deferred:** eraser concentric-ring brush tip (reuses the mosaic outline).

### Eraser

- Sub-toolbar: same first **5** icons as mosaic — brush **14 / 18 / 24** | **rect / oval region** (no intensity / color).
- Freehand: stroke sampling; Shift → straight; keep translucent brush tip while stroking (tip temporarily reuses mosaic brush outline; concentric-ring tip deferred). No resize chrome / no auto-select after stroke.
- Region: drag like mosaic; Shift → square / circle; auto-select with 1px contrast hairline (solid→dashed) + 8 resize handles.
- Effect: punches **annotation marks only** (`destinationOut` on a marks layer composited over the freeze/base) — never erases image pixels (P4). Order matters: later marks redraw on top of earlier erasures.
- Hit: under object tools, eraser marks draw-through (no move hand over erased areas). Under paint tools, all marks draw-through (Shared rules). Move via **V**.
- Disk: `type: "eraser"` with `eraserStyle` (brushWidth) plus either stroke `points` or region `kind` + `rect`.

### Text

- Sub-toolbar: Bold / Italic / background | font size | color (system UI font; no family / rotation yet).
- Click anywhere on freeze → place + inline edit (click = left edge + vertical center of the first line).
- **I** (Insert) arms the text tool and, when not toggling off / not over the toolbar, places + edits at the cursor. Toolbar tap still arms only (click to place).
- **Edit chrome:** 1px hairline; white border + white caret on dark backdrops, black + black on light (not the palette color). Transparent fill unless bg toggle.
- Frame hugs glyphs with tiny padding (~2pt); **grows with text width** (including IME preedit before commit); soft-wrap only near screen edge. Empty editor is caret-wide (no trailing blank).
- **Hit / cursor:** blank overlay (selection or dimmed) → I-beam for place-new; near text edge / hairline (+~2pt outside) → four-arrow move; deeper interior → I-beam + click to edit. Toolbar only → arrow. While editing: border drag **live-moves** the chrome without ending edit; interior still types. Cursor is re-applied after caret blink so AppKit cannot reset to the system arrow while the pointer is still. Hover → 1px contrast dashed outline (black on light freeze, white on dark; clears on mouse-out). No resize handles.
- Esc ends edit only; Return = newline (not confirm). Empty on end-edit → drop mark.

### Step

- Sub-toolbar: **filled** / **outline** / **plain** chrome | size ▾ | color grid.
- Defaults: **filled**, size **4**, cyan (last-used prefs override).
- Cursor is a live badge of the **next** number (current style) — click stamps at the hotspot; cursor then advances.
- Place: click anywhere on freeze → `max(existing)+1` (or `1`); auto-select; drag to move. No resize handles; no inline edit. Stamps through foreign marks (shape borders, etc.); hover an existing step to move it; **⌘** moves other marks.
- Styles: filled = color disk + white digit; outline = color ring + color digit; plain = color digit only (toolbar chip uses a dashed plate so it still reads as a button).
- Size levels map to diameter (`10 + size×3.2` pt). Style / size / color apply to selection (or next place).
- Edit chrome: dashed contrast square around the badge (Snipaste).
- Disk: `type: "step"` with `number`, `points: [center]`, `stepStyle` (`kind` / `size` / `color`).
- P4: vector payload only; mutate via `AnnotationHistory`; unknown types skip on load.

### Magnifier

- Drag defines the **source** sample rect with a **solid palette** stroke (no lens yet); on mouse-up, a concentric **lens** appears at the current **scale** (default **2×**) and the source outline switches to the nested **dashed** style. Shift → square/circle source.
- Zoom is **only** via the **scale slider** (1.00…6.00, two decimals): resizes the lens about its center; source size stays put. **Lens resize** changes selection area only — source scales proportionally about its center so zoom stays fixed. **Source is move-only** (no resize handles). Move each frame independently.
- Connector links nearest edges **only when source and lens are fully disjoint**; any overlap / nesting → no line.
- **Source border vs lens:** portion of the source outline **inside** the lens → **1 device-pixel dashed** contrast hairline (black on light / white on dark — **not** palette ink); portion **outside** → thick solid palette stroke (`strokeWidth`). Fully nested → all dashed contrast; fully outside → all thick palette; crossing → hybrid per segment. Lens always thick solid palette.
- **Declutter (≥2 magnifiers):** nested source frames (小框 inside 大框) are **hidden** by default; hovering a lens **or selecting that mark** reveals its source. Draft / active move·resize keeps its source visible. Pin/Copy/Save bake matches the idle (hidden) look.
- Sub-toolbar: stroke widths | rect ↔ oval | **include annotations** toggle (`rectangle.on.rectangle`, default **off**) | **scale** (solid preview dot + slider + value) | color grid.
- `includeAnnotations == false`: sample freeze/base only. `true`: sample freeze/base + marks drawn **before** this magnifier (excludes self; **source-crop composite** only — not full-display; P4 vector data, no bake into `baseImage`).
- Auto-select after create; 8-handle chrome on **lens only**.
- Disk: `type: "magnifier"` with `kind`, `rect` (source), `lensRect`, `magnifierStyle` (`strokeWidth` / `color` / `includeAnnotations` / optional `scale`).

### OCR

- Toolbar **Recognize Text** (`doc.text.viewfinder`): Vision OCR on the **unannotated** selection crop (zh-Hans / zh-Hant / en-US).
- Dismisses the overlay immediately after crop (no result UI). On non-empty text → pasteboard + short bubble-pop sound (`Resources/ocr-success.wav`). Empty / failure → silent, clipboard unchanged.
- Does **not** append to snip history.

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
- [x] Cancel / Esc; confirm crops then tears down; ⌘F1 Capture and copy = immediate copy (no refine)
- [x] Pin soft glow + drag
- [x] Shape / arrow / pencil / marker / mosaic / text / step / magnifier / eraser: draw·edit on full overlay; bake clips outside marks; document keeps them
- [x] OCR: recognize selection → clipboard + bubble-pop; dismiss overlay; no result UI
- [x] Undo / redo; debug build succeeds
