# Selection refine + toolbar

Status: **implemented** (Snipaste-style refine + icon toolbar + pin chrome + save).  
Annotate live: **shape**, **arrow**, **pencil**, **marker**, **mosaic**, **text**, **step**, **magnifier**, **eraser** (+ in-session undo/redo). **OCR** copies selection text to the clipboard and dismisses (bubble-pop on success).

Document / undo stacks / `,` / `.` / disk: [`snip-document-architecture.md`](snip-document-architecture.md) (P0–P4).

When a tool’s section grows past ~40–50 lines or a new tool lands, spin it out to `docs/annotate-<tool>.md` and leave a one-line link here. **Do not split yet.**

## Shared rules (all annotate tools)

- Annotate works on the **full freeze overlay**, not only inside the blue selection.
- **Crop resize chrome stays** while any annotate tool is selected (8 handles on the blue export rect). Mark chrome wins on overlap; otherwise the **border strip** still resizes the crop. **Outside-edge expand is off** while a tool is armed (dimmed area is for annotate); it returns when the tool is toggled off / deselected. Interior of the crop still draws / places marks (does not move the selection). **Exception — no tool armed (`.none`):** there the crop's border band *and* the outside octants win **over** marks, so a mark drawn flush with a crop edge can never make that edge unresizable; grab such a mark with **V** instead, which never touches the crop.
- **No tool armed is still an editing mode.** With `.none` you cannot create marks, but every existing mark stays selectable / movable / resizable and its option row still shows. Marks are never read-only just because no tool is armed.
- Moving / resizing / expanding the blue crop **does not move marks on the freeze** — selection-local geometry is rebased by the origin delta (marks stay glued to image content; only the export rect changes).
- **Hold Space** → temporary drag-move of the blue crop (open hand → closed hand while dragging; release Space to return to the current tool). Interior drag without Space does **not** move the crop.
- Pin / Copy / Save **do not expand** the crop: outside marks are **clipped** from the baked image.
- Outside marks stay in `AnnotationDocument` so `,` / `.` can still show and drag them back into the rect.
- Confirm composites marks onto the crop, then tears down the overlay.
- Esc ladder (not editing text): abort in-progress drag → deselect mark → disarm tool → with marks, first Esc / Cancel shows “Press again to discard”, second Esc / Cancel discards. Deselect comes **before** disarm so the first press unwinds the most local *visible* state (the handles) rather than a tool tint; disarming no longer clears the selection, and the disarm rung stays as a buffer before the discard confirm.
- Delete removes the selected mark. Undo / redo: toolbar + ⌘Z / ⇧⌘Z.
- Refine tool / action hotkeys (armed after selection; ignored while editing text or mid-drag):
  **V** move · **A** arrow · **S** shape · **D** pen · **F** marker · **M** mosaic · **I** / **T** text · **N** number · **E** eraser · **P** pin · **O** OCR · **⌘S** save · **⌘C** copy.
  **R** / **G** / **B** → palette red / green / cyan (selected colored mark, else armed tool; no-op for mosaic / eraser).
  ASDF row mnemonics: **A**rrow · **S**hape · **D**raw · **F** like a brush (highlight). **I** = Insert (text). **T** = Text (Photoshop / Figma). **V** = move (Figma-style).
- **Chrome contrast is `ContrastChrome`'s job, and it has two mechanisms — pick by shape.** *Sample the backdrop* (`hairline(onLuminance:)` / `textHairline`, black on light and white on dark, fed by `averageLuminance(in:aroundPointInImageSpace:)`) for chrome tied to **one point** — the text edit hairline + caret, the magnifier hairline, the step / region outlines. *Halo* (`strokeHaloedRect`) for anything **frame-shaped**: the light line plus a dark companion one line-width **inside** it, no sample at all. A frame has no single backdrop — its edges cross arbitrary pixels, and the obvious sample point (the box centre) is usually the mark's own text or plate rather than what sits under the line — so sampling can confidently pick the wrong colour for most of the frame. The halo is drawn *inward* so the rect stays the chrome's outer bound: handles keep the size they are hit-tested at, and nothing overdraws into a parent that clips. On dark content the halo vanishes and it reads as the plain white line; on light content the white line vanishes and the halo reads as a dark hairline (one device pixel at ~30% gray on white); in between, a subtle double line. Used by the **text hover / selected frame** and the **8 resize handles** + arrow endpoint handles, all of which were plain white and disappeared on white content.
- **Hit / move vs draw:** the two **non-drawing modes** — **Move (V)** and **no tool armed (`.none`)** — hit all marks for drag / resize by their whole **body** and create nothing; empty click deselects (`AnnotateTool.editsMarksOnly`). Paint tools (**pencil** / **marker** / **mosaic** / **eraser**) draw-through existing marks while **freehand** — switch to **V** to move, then back (e.g. **D**) to draw. **Exception — rect / oval paint modes:** a paint tool in region mode drags out an area like the shape tool, so existing **region** marks (marker / mosaic / eraser, any family) are grabable by their whole **body** — click-drag moves, handles resize — while brush **strokes** keep drawing through. Body rather than border-only because a region has no interior to nest-draw into; the trade is that a new region starting *inside* an existing one needs **V**, **Esc**, or a start point outside it. Selected mark **handles** still resize without switching. **Step** draws through foreign marks so you can stamp on a shape border; existing step badges stay hit-to-move (**⌘** still moves other marks). Other object tools (shape / arrow / text / magnifier) keep hit-to-move on their targets; paint-like marks still draw-through under those tools (move via **V**).
- **Option row follows the selection.** The sub-toolbar shows the **selected mark's** family when there is one, else the armed tool's (`selectedMarkFamily ?? tool` in `refreshSelectionChrome`). So you can select an old text mark while the pencil stays armed, restyle it, then keep drawing. The main-row icon tint always tracks the **armed** tool, not the selection. Both non-drawing modes own no options, so with nothing selected the card is hidden entirely.

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
¶ Mosaic: [ · | ·· | ··· ] | [ rect region | oval region ] | [ chip⇄ | slider | value ]  (sizes 14/18/24 freehand; rect/oval = area blur; chip toggles Blur/Pixelate, knob ●/■, slider = sigma 0.8…3.2 pt or block 2…16 pt)
‡ Text: [ B | I | bg ] | [ size ▾ ] | [ preview 24 + palette 2×10 ]
§ Step: [ filled | outline | plain ] | [ size ▾ ] | [ preview 24 + palette 2×10 ]
♯ Eraser: [ · | ·· | ··· ] | [ rect region | oval region ]  (same first 5 as mosaic; punches marks only)
  Magnifier: [ thin | med | thick ] | [ rect | oval ] | [ includeAnnotations ] | [ scale preview + slider 1…6 + value ] | [ preview 24 + palette 2×10 ]
  More stub / disabled
```

## Tools

### Move (V)

- Select / drag any mark; resize via handles when selected. Does **not** create marks.
- Empty click deselects. No sub-toolbar of its own — the row shown is the **selected mark's**.
- Shape **body** (rect / oval interior) is grabable in this mode; under the shape tool, interior still nest-draws and only the border moves.
- Prefer this for rearranging marks (paint tools no longer use **⌘** temporary move).
- **Versus no tool armed:** the two behave the same on marks (they share `editsMarksOnly`). The one difference is the crop — `.none` lets the border band and the dimmed outside area resize / expand it, while **V** never touches the crop, so V is the mode for grabbing a mark that sits on a crop edge. V is also the *discoverable* door: toolbar icon, tooltip, and the Figma-standard key.

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
- Region: drag like mosaic; Shift → square / circle; entire rect/oval is highlighted. **Edit chrome**: while drawing / moving / resizing → **1 device-pixel solid** contrast hairline; after mouse-up (selected idle) → **handles only** (no border); **mouseover** on a non-selected region → dashed contrast outline (like text hover), shown only when the region is actually grabable (**V** or a rect / oval paint mode). Under object tools: draw-through; move via **V**. Under a rect / oval paint mode: whole body moves, handles resize (Shared rules). Under a freehand brush: draw-through.
- Effect: **multiply** blend (Snipaste highlighter — dark → darker, light glyphs → bright tint). Marks paint on a transparent offscreen layer for eraser, so multiply first stamps the freeze/base under the clip, then tints. Near-white swatches fall back to sourceOver wash. **Vector** stroke/region data only (P4). Default color yellow.
- Toolbar icon: SF Symbol `paintbrush.pointed`.
- Disk: `type: "marker"` with `markerStyle` (brushWidth / color) plus either stroke `points` or region `kind` + `rect`.

### Mosaic

- Sub-toolbar: brush **14 / 18 / 24** (three sized dots → freehand smear) | **rect / oval region** (drag to obscure an area) | **preview chip = Blur/Pixelate toggle** | strength slider whose **knob shape shows the mode** and whose units change with it — sigma **0.8…3.2 pt** for Blur, block edge **2…16 pt** for Pixelate.
- Freehand: stroke sampling; Shift → straight; keep translucent brush tip while stroking. No resize chrome / no auto-select after stroke.
- Region: drag like shape; Shift → square / circle; entire rect/oval is obscured. **Edit chrome** (not the thick shape stroke): **1 device-pixel hairline** — black on light freeze, white on dark; **solid while dragging**, **dashed after mouse-up** with **8 resize handles** (auto-select). Hit mark to move; handles resize.
- Effect: **Blur** = gaussian smear (`CIGaussianBlur`, sigma 0.8…3.2 pt) or **Pixelate** = coarse colour squares (`CIPixellate`, block edge 2…16 pt) — see *Effect calibration* below. Either way it processes freeze/base **plus whatever marks are already under it**. Path: hull crop → read the marks drawn so far out of the `MarksCanvas` (`snapshotCrop`) → composite over the freeze crop → filter → clip to stroke/region. Because the sample is *pixels already rendered*, a mosaic over an earlier mosaic sees that one's output. **Vector** stroke/region data only (P4; never mutates `baseImage`).
- Hit: under object tools, mosaic marks draw-through (no move hand over obscured areas). Under a freehand brush, all marks draw-through. Under a **rect / oval paint mode**, region marks are grabable by the body — move / resize without leaving the tool (Shared rules), with a dashed hover outline on the non-selected one under the pointer (same chrome as marker regions). Move via **V** (region handles still work when selected).
- No color palette.

**Dual-use, one tool.** Blur and Pixelate share geometry, brush presets, sampling, hit-testing,
chrome and the `.mosaic` payload — only the Core Image filter differs, so a second main-toolbar
icon would duplicate the whole surface for one filter swap. The effect lives on `MosaicStyle`
(`effect: blur | pixelate`, disk field `effect`, records without it decode to blur) and rides the
existing `mosaicStyleChanged` event, which means switching effect while a mosaic mark is selected
converts that mark — same as changing its strength. Last-used effect persists in
`annotate.mosaic.effect`.

**The switch is the preview chip, and the knob is the readout** — Snipaste's design (its tooltip
reads "Toggle mosaic/blur"), adopted after an explicit Blur/Pixelate chip pair was built first.
Clicking the chip flips the effect; the chip already renders the armed effect (soft halo vs blocks),
so the control *is* its own state display, and the slider knob draws a **circle for Blur, a rounded
square for Pixelate** so the mode stays visible at the point your eye is during a drag. Dropping the
two chips and their divider takes ~54 pt off what was the widest sub-toolbar in the app.

The cost is that a preview-looking chip is a click target you have to discover. Mitigated by making
it an `NSButton` rather than a view with a `mouseDown`: `HoverChromeCard` walks up to the nearest
button, so the chip inherits the same **accent underline on hover** and the same custom tooltip as
every real button in the row — the affordance it lacks in appearance it gets on hover. `knobIsSquare`
defaults to circle because `MosaicIntensitySlider` is shared with magnifier scale, which has no mode.

The chip glyph is a **thin dark annulus** (8 of 64 sample px) filling the 24 pt slot, so it reads like
Snipaste's ring rather than a blob. Its two effects need *opposite* fudge factors, both verified by
rendering the glyph headlessly across the intensity range: blur is exaggerated **1.6×** because a 3 pt
sigma shrinks to under a point at this size, while pixelate is scaled **0.7×** — blocks-across is
`64 / block`, a function of the sample rather than the drawn size, so at 1.2 (let alone 1.6) the top
of the range collapsed into one flat square. 0.7 holds ~6 blocks at maximum, which still reads as a
lattice.

**The slider carries the real filter parameter, one value per effect** — `blurSigma` and
`blockSize`, both in points, each with its own range, step and default. It does not carry an abstract
"intensity".

Snipaste's 3…24 scale was inherited early, and it fits neither effect. 21 integer steps across sigma
0.8…3.2 pt is **0.114 pt per step — a quarter of a device pixel at 2×**, so most adjacent settings
were indistinguishable and roughly two thirds of the slider did nothing you could see. (Snipaste's
own reason for 3…24 is undocumented; the likeliest explanation is a mosaic block size in pixels,
which its pixel-denominated brush labels support, inherited by blur when the slider was reused. That
is inference, not a citation.) Naming the quantity fixes both halves: the label reads what the filter
will actually do, and a block edge in points is the same thing Photoshop calls Mosaic **"Cell Size"**
and ShareX calls **"Pixel size"**.

| | range | step | stops | per step @2× | default |
|---|---|---|---|---|---|
| Blur sigma | 0.8…3.2 pt | 0.4 pt | 7 | 0.8 px | **1.6** |
| Pixelate block | 2…16 pt | 1 pt | 15 | 2.0 px | **6** |

Each effect keeps its own value, so toggling Blur → Pixelate → Blur restores the blur strength you
had. Both are **absolute** — never scaled by brush width — so a value means the same thing at 14 pt
and 24 pt, matching Photoshop's blur tool. `strength` on `MosaicStyle` is the accessor that routes to
whichever one the armed effect reads, and it snaps on write; `clamp()` deliberately does **not** snap
(see the migration note below).

*Blur.* `CIGaussianBlur.inputRadius` **is sigma**, and a thin stroke smears over roughly ±2…3 sigma,
so sigma has to stay small or a pencil line turns into a blob. Measured on a 2 pt stroke against a
dark freeze:

| sigma | thickening | fine detail left |
|---|---|---|
| 0.8 | 1.7× | 21% |
| 1.2 | 2.1× | 5% |
| **1.6 (default)** | **2.8×** | **0.1%** |
| 2.0 | 3.7× | 0% |
| 2.8 | 4.6× | 0% |
| 3.2 | 5.2× | 0% |

Two things this range is chosen to avoid. Sigma above ~3 pt **blooms past the brush** and gets
clipped to it, so perceived thickness starts tracking the brush width instead of the setting — an
earlier 0.7…14 pt range saturated almost immediately, wasting most of the slider and making a 14 pt
and a 24 pt brush read as different strengths (5.9× vs 7.8× at the same setting). And detail is
already gone by ~1.5 pt, which is why the default sits just past it — an old default of ~5 pt was
roughly 3× more blur than obscuring needs, and all of that excess went into fattening strokes.

*Pixelate.* Block edge 2…16 pt, rounded to whole device pixels so the lattice lands on pixel
boundaries. The failure mode is the mirror image of blur bloom: blocks *larger* than the brush can't
tile it, so a stroke narrower than ~3 blocks reads as a flat smudge instead of a mosaic. Drawing
wider or switching to region mode is the fix — clamping the block to the brush would break the
"same value, same result at every brush" rule.

| block | blocks across a 14 pt brush | typical read |
|---|---|---|
| 2 pt | 7 | light texture |
| **6 pt (default)** | **2** | **chunky; past what body text survives** |
| 11 pt | 1.3 | region-only |
| 16 pt | <1 | coarse enough to bury a face in a large region |

**Migrating off `intensity`.** Records and prefs written before this stored the abstract 3…24 value
and derived both quantities at draw time. Disk gains optional `blurSigma` / `blockSize`; when they are
absent, decode runs the legacy `intensity` back through the *old* curves
(`blurSigma(forLegacyIntensity:)` / `blockSize(forLegacyIntensity:)`), so a reopened snip renders
byte-identically instead of shifting. This is why `clamp()` range-clamps but does **not** snap to the
step grid — snapping a legacy value would move it by up to half a step (intensity 15 → sigma 2.1714,
which would land on 2.0, a 0.17 pt change on every old mark). Snapping lives on the input path only:
the `strength` setter and `MosaicIntensitySlider.step`. Prefs read the retired
`annotate.mosaic.intensity` once to seed `annotate.mosaic.blurSigma` / `.blockSize`, then delete it.
No `schemaVersion` bump — the new fields are additive and unknown keys are ignored.

**Blocks are left hard-edged** — Pixelate is the lattice and nothing else. Hull bleed is one whole
block, so the outermost cells average against real neighbours instead of missing ones. (An adjustable`ratio × block` gaussian after `CIPixellate` was built and then removed: it is a second look control
on a tool that already has one, and the sharp lattice is the effect people expect.) Blur mode is
untouched by any of this.

**The block lattice is anchored in image space**, not per crop. `CIPixellate` builds its grid
around `inputCenter`, which is relative to the image handed to it — here a hull crop whose origin
moves with every stroke — so left at a constant, each mark would quantise to its own offset grid
and two overlapping pixelate strokes would seam where the lattices disagree (the second stroke
re-reads the first's pixels out of the marks layer). `pixelateGridAnchor` cancels the crop's
absolute pixel origin, mod one block, which makes the phase a function of absolute position alone;
*which* part of a cell `inputCenter` names is deliberately not relied on. Verified headlessly: two
crops offset by (13, 19) px render bit-identically, against completely different values when the
anchor is left constant.

**Not security-grade redaction at any setting, in either mode.** Blurred *and* pixelated text is
recoverable (Hill et al., *On the (In)effectiveness of Mosaicing and Blurring as Tools for Document
Redaction*, PoPETs 2016 — 24 pt text recovered through a 45 px blur). Solid fill is the only safe
way to hide sensitive content.

Sampling design (mosaic / magnifier): marks render into a `MarksCanvas` (an owned bitmap), and a
mosaic reads the hull it is about to process back out of it — so a mosaic over an earlier mosaic
sees that one's pixels, and nothing re-derives prior marks from vectors. The overlay caches the
committed layer so a pencil drag does not re-render every mosaic per frame. Full write-up, the two
rejected approaches, measurements, and the rules that must not be broken:
[`marks-rendering.md`](marks-rendering.md).

**Undo mechanics (audited — all tools).** Every repeating input is now coalesced, and the rule is
uniform: *if a gesture is open, everything folds into it.*

- **Mark move / resize / arrow endpoint** — `beginGesture` at mouse-down, `mutateLive` per tick,
  `endGesture` at mouse-up. Always was correct.
- **Freehand stroke** (pencil / mosaic / marker / eraser) — the draft lives *outside* the document and
  is committed once at mouse-up, so a 500-point stroke is one step.
- **Value sliders** (mosaic strength / magnifier scale) — **was broken**: they fire their action per
  tick, so one sweep pushed 7 (blur) / 15 (pixelate) / dozens (scale, continuous) steps, and a
  there-and-back drag left a pile instead of nothing. Fixed by bracketing the drag:
  `MosaicIntensitySlider.onDragBegan` / `onDragEnded` → `valueDragBegan` / `valueDragEnded` →
  `beginToolbarValueDrag` / `endToolbarValueDrag`. Debouncing ticks would have been the wrong fix — it
  lags the mark under the cursor and still can't collapse a there-and-back drag to zero.
- **Text scroll-wheel size** — same bracket: first notch `beginGesture`, each step `commit`s into it,
  then `endGesture` on ~350 ms idle (`textWheelGestureIdle`) or, sooner, on the next **key-down /
  mouse-down / Esc / toolbar hover / `,` `.` history step / teardown**. Deliberately *not* `mouseMoved`
  or `mouseUp` — those fire mid-scroll and would split one burst into many steps. Do not debounce the
  ticks.
- **Place a text + type into it** — **was two steps** (⌘Z left a stray empty mark and needed a second
  press). `endTextEditing` now `amendLastStep`s into the placement step — one step, zero if the text was
  left empty. Gated on the one-shot `textAwaitingFirstEditID` token **and** `lastStepIntroduced(id)`:
  the state check alone would go true again after "delete the mark, ⌘Z the delete", folding a much
  later edit into the placement step.
- **Discrete clicks** (color, brush size, kind, effect toggle, region mode, caps) — one `commit` each,
  unchanged.
- **Key auto-repeat** — the palette letters (**R** / **G** / **B**) survive a held key only because
  re-applying a color is idempotent and `commit` no-ops when the marks don't change. The tool letters
  are *not* idempotent, so the letter-hotkey block now checks `isARepeat` (holding **V** used to
  arm/disarm the tool ~15×/sec). Don't rely on idempotence for anything added there.
- **An open gesture owns the keyboard** — while `annotationHistory.isGestureOpen` the keyDown monitor
  swallows everything but Esc. ⌘Z mid-drag used to swap the document out from under the gesture (drag
  baked in with no undo step, phantom snapshot on the redo stack) and ⌘S / ⌘C / Return finalized the
  snip on a half-finished edit. Crop drags don't open a gesture, so they keep their keys.
- **Mouse-up is never swallowed mid-drag** — the toolbar pass-through in both monitors now requires
  `dragKind == nil`. Releasing a mark drag over the toolbar used to strand `dragKind` and leave the
  gesture open, which fused the abandoned edit into the next drag's step.

Stack semantics live in [`snip-document-architecture.md`](snip-document-architecture.md) — including the
one that trips people up: **selection is never an undo step**, so `marksDiffer` (marks only) decides.

### Eraser

- Sub-toolbar: same first **5** icons as mosaic — brush **14 / 18 / 24** | **rect / oval region** (no intensity / color).
- Freehand: stroke sampling; Shift → straight; keep the ring brush tip while stroking (concentric hairline rings at the real diameter, no fill — a filled tip would hide the marks being punched out). No resize chrome / no auto-select after stroke.
- Region: drag like mosaic; Shift → square / circle; auto-select with 1px contrast hairline (solid→dashed) + 8 resize handles.
- Effect: punches **annotation marks only** (`destinationOut` on a marks layer composited over the freeze/base) — never erases image pixels (P4). Order matters: later marks redraw on top of earlier erasures.
- Hit: under object tools, eraser marks draw-through (no move hand over erased areas). Under a freehand brush, all marks draw-through. Under a **rect / oval paint mode**, region marks are grabable by the body, with a dashed hover outline on the non-selected one under the pointer (Shared rules). Move via **V**.
- Disk: `type: "eraser"` with `eraserStyle` (brushWidth) plus either stroke `points` or region `kind` + `rect`.

### Text

- Sub-toolbar: Bold / Italic / background | font size | color (system UI font; no family / rotation yet).
- Click anywhere on freeze → place + inline edit (click = left edge + vertical center of the first line).
- **I** (Insert) / **T** (Text) arms the text tool and, when not toggling off / not over the toolbar, places + edits at the cursor. Toolbar tap still arms only (click to place).
- **Edit chrome:** 1px hairline; white border + white caret on dark backdrops, black + black on light (not the palette color). Transparent fill unless bg toggle.
- Frame hugs glyphs with tiny padding (~2pt); **grows with text width** (including IME preedit before commit); soft-wrap only near screen edge. Empty editor is caret-wide (no trailing blank) — and the caret itself scales with `fontSize`, so that width is font-dependent.
- **Hit / cursor:** blank overlay (selection or dimmed) → I-beam for place-new; near text edge / hairline (+~2pt outside) → four-arrow move; deeper interior → I-beam + click to edit. Toolbar only → arrow. While editing: border drag **live-moves** the chrome without ending edit; interior still types. Cursor is re-applied after caret blink so AppKit cannot reset to the system arrow while the pointer is still. **Hover** (including while editing) or **selected** (not editing) → **haloed** white frame (see Shared rules — it was plain white and vanished on white content) + **4 corner badges** (white rim + blue face + slight round; Snipaste): top-left / bottom-left / bottom-right = diagonal resize (aspect-lock + scale `fontSize`, then **re-fit** the box so glyphs aren’t clipped; the corner scale is the drag **projected onto the anchor→corner diagonal** — picking whichever axis deviated more flips at the crossover when one axis grows while the other shrinks, which swung `fontSize` ~17 pt for 2 pt of mouse movement); **top-right = close (X)** removes the mark. On a tiny / empty box, badges are **pushed outward** from the corners so they don’t overlap (frame size unchanged). Badges are **hidden while moving / resizing**. Badges while editing paint above the field editor.
- **Box sizing is shrink-wrap** (CSS-like): `fontSize` + padding decide the content size, `Annotation.fittingTextSize` / `AnnotationTextView.fittingSize` compute it, and the frame is set from that — the width/height are never authored directly. Both paddings **scale with the font**: `textHorizontalPadding` = `max(textPadding, caretWidth)` and `textVerticalPadding` = `max(textPadding * 2, fontSize * 0.12)`, where `textPadding` is the flat 2pt (3pt with background). Horizontal has to scale because the caret is drawn **after** the last glyph, so the trailing padding is the only room it has — at 144pt a flat 2pt left the caret hanging ~11pt past the right border. Only *fitting* uses either value: `drawText` **centres** the glyph block on both axes in whatever rect it is handed, so a mark saved before the paddings grew still renders rather than clipping or re-wrapping. Centring is exactly right for both eras — the slack is 0 for an old tight rect and precisely the new padding for a new one (verified 14→144pt, short and wrapping strings: horizontal shift is **+0.00** at every size). Vertically it is not free: an old mark's text shifts **down by ≤2pt**; see the comment in `AnnotationDrawing+Text.swift`. Unlike CSS the computed size is then **frozen into `rect`** and persisted, so the model and the field editor must agree. They share the arithmetic via **`TextBoxMetrics`** (paddings, `minHeight`, `emptyWidth`, `size(glyphWidth:glyphHeight:)`, `wrappedSize`, `needsWrap`) and differ *only* in how they measure glyphs — the model measures an `NSAttributedString`, the editor asks its own layout manager so IME preedit counts before commit. They previously duplicated the arithmetic and had already drifted (the editor floored glyph width at `caretWidth`, the model did not; each recomputed `minHeight` separately). `TextBoxMetrics.unboundedExtent` also names the `10_000` measuring sentinel. The one deliberate asymmetry left: `drawText` insets by the flat `textPadding` and *centres*, rather than insetting by `textHorizontalPadding` — that is what keeps pre-existing marks renderable, and the two only agree because centring absorbs the difference. The field editor's **text container is the box's inner width**, never `maxW`: TextKit gives every line fragment ending in a newline a selection rect spanning the *whole container*, so an oversized container made ⌘A on multi-line text paint the first line's highlight out to the screen edge (only the last line hugs its glyphs, which is why single-line boxes never showed it). Sizing the container to the fitted width cannot wrap prematurely — `fittingSize` measures unbounded and `ceil`s, so the container is always ≥ the used width (verified: line count at the fitted width matches the unbounded measurement).
- **Scroll wheel** resizes the editing mark, else the text under the pointer, else the selected text: ±2 pt per notch (`fontSize` **6…144**, in true points — 144 pt is ~10% of frame height on a 1440 pt display, a headline callout that survives being downscaled in chat; clamped on wheel / corner-resize / prefs-load but **not** on decode, so a saved snip keeps its stored size), box re-fits from the top-left. Trackpad accumulates ~2 pt of travel per step (shorter than pin zoom — type steps are small), **at most 2 steps per event** with the remainder carried to the next event, and momentum/inertia events are ignored. Both halves matter: a fast flick arrives as a single event carrying the whole gesture's travel (`scrollingDeltaY` ≈ 40), so draining it with an unbounded loop spent it all at once (10 steps → +20 pt, i.e. 40 → 60 from one notch) — but *zeroing* the accumulator instead of keeping the remainder throws away most of a Magic Mouse gesture's travel and the control feels dead. Cap the steps, keep the remainder. A burst is one undo step (`beginGesture` on the first notch, `endGesture` on ~350 ms idle or the next key-down / mouse-down / Esc — see the coalescing note above). Toolbar size / Bold / Italic / background also re-fit from the top-left.
- **Corner resize never closes the editor.** A corner badge drag on the mark being edited drives `fontSize` and lets the field editor re-fit — the same chain the wheel uses (`applyTextStyle` → `applyTextStyleToEditor` → `resizeTextEditorToFit` → read `editingTextGlobalRect()` back into `rect`) — anchored via `applyTextStyle(editingAnchor:)` on the corner **opposite** the handle, so the un-dragged corner stays put (the toolbar and wheel keep the default top-left anchor). This is what makes "set the size, then type" work: a **blank** mark resizes too, the caret being the feedback — it is *not* a fixed hairline, its width tracks `fontSize` (`TextStyle.caretWidth`, ~size/11 regular and ~size/7 bold, fitted to the system font's measured stem ink) so you can see the weight you are about to type at. An empty box is `caretWidth + textHorizontalPadding * 2` wide with the caret **centred in it**, so the caret occupies the middle third once it outgrows the flat text padding. Both parts matter: TextKit reports the caret at the *text origin*, so centring a thick caret on that rect put its left half outside the frame and left dead space on the right. Empty-box width therefore grows with the font — ~5.3pt at 14pt type, ~19.6pt at 72pt, 24pt at the 144pt ceiling. Caret thickness is capped at `caretWidthMax` = 8pt (the true stem of ~88pt type): past that a caret reads as a selection block, and the cap keeps large boxes from growing fat side padding too. The cap is **aesthetic only** — `textHorizontalPadding` reserves the room and `placeHairlineCaret` clamps the caret inside `bounds` regardless, which is load-bearing rather than belt-and-braces: above 88pt the padding equals the caret exactly, so without the clamp the caret's last device pixel would paint over the frame line. The live path takes its scale **straight from the drag projection, not from `resizedRectKeepingAspect`** — that helper's rect floors (`minAnnotation` = 4) pin a blank box's 4.5pt width as soon as scale drops below 0.889, which freezes the aspect-locked height and capped a whole drag at ~11% shrink (72 → 64, release, 64 → 57, release …). Only `fontSize` needs bounding here because the box is derived from it. The projection is used **`abs`**, so one press sweeps the full range: drag inward past the anchor, the scale crosses zero and its magnitude grows again — max → min → max in a single gesture (~90px each way for an empty box at 72pt), stepless, Snipaste-style. Previously mouse-down called `endTextEditing(commit: true)` first, which *drops* a blank mark — the re-hit-test then saw bare overlay and queued a click-to-place, so the mark appeared to teleport onto the badge. A badge press that never passes `textClickDragThreshold` changes nothing (`endGesture` discards the empty step) and blinks the badges once. Prefs are saved on mouse-up only, never per tick.
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
- Holds the unannotated base + an `AnnotationDocument`, and shows the composite. Right-click gives
  Copy image / Save image as… / Copy plain text (or Extract text and copy) / Show toolbar / Stay on
  Top / Shadow / Close.

## Pin-edit (right-click → Show toolbar)

The same refine surface, re-hosted over a pinned bitmap. Differences from a capture session, all
gated on `SelectionOverlayController.pinEdit`:

| | Capture | Pin-edit |
|---|---|---|
| Host | one full-screen panel per display, freeze backdrop + dim | one transparent lid over the bitmap (+ ~200pt margin for the text editor), margins click-through |
| Chrome | blue crop rect, 8 crop handles, size badge | none — marks and their own chrome only; ink clipped to the bitmap |
| Effect sampling | freeze (with playback stamped in) | the pinned bitmap at `.zero` origin, same context `AnnotationCompositor` bakes with |
| Crop | resize / move / Space-drag / outside-octant expand | all off (`refineResizeHandle` returns nil) |
| `,` / `.` | history playback | inert (that controller has no `historyStore`) |
| Zoom | n/a | pin snaps to 100%; the wheel belongs to the tools |
| Confirm | Pin / Copy / Save create the artefact, Esc ladder ends in discard | ✓ / Esc **apply and keep the pin**; ✕ discards the session; Copy / Save / OCR bake and **close** the pin |
| Level | `.screenSaver`, toolbar `+1` | lid `.statusBar + 1`, toolbar `.statusBar + 2` |
| Activation | `NSApp.activate` | never — the lid takes key without pulling the app forward |

Marks stay data on the pin, so a session can be re-opened and the same marks edited again; marks
made during the original capture come across with it.

## Code

- Overlay controller: [`SelectionOverlayController.swift`](../EggplantShot/Controllers/SelectionOverlayController.swift)
- Overlay panels: [`SelectionOverlayPanel.swift`](../EggplantShot/Controllers/SelectionOverlayPanel.swift)
- Pin-edit session: [`SelectionOverlay+PinEdit.swift`](../EggplantShot/Controllers/SelectionOverlay+PinEdit.swift)
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
- [x] Pin-edit: Show toolbar docks the toolbar at the pin; draw / edit / undo in place; ✓ / Esc keep
      the pin, ✕ discards, Copy / Save / OCR close it; re-opening resumes the same marks
- [x] Undo / redo; debug build succeeds
