# Marks rendering: mosaic sampling and overlay redraw cost

How annotate marks get rendered, why mosaic needs to read pixels back, and the two bugs that
forced the current design. Written 2026-08-15, after three attempts — two of which are recorded
here specifically so nobody tries them again.

Companion docs: [`selection-refine.md`](selection-refine.md) (per-tool refine rules),
[`snip-document-architecture.md`](snip-document-architecture.md) (payloads / disk format).

---

## The two problems

**Mosaic over an existing mosaic went black.** On a dark freeze, smearing mosaic over pencil ink
worked, but smearing a *second* mosaic over the first one turned that area near-black instead of
showing blurred ink.

**The overlay froze.** With messy multi-colour pencil (handwritten 一/二/三/四/五) plus several
overlapping mosaic smears, drawing more pencil locked the overlay up — not "a bit slow", locked.

They look unrelated. They are the same root cause.

## Why marks render to a layer at all

`AnnotationDrawing.renderMarksLayer` draws every mark into one offscreen layer, which is then
composited over the freeze. Two reasons it can't just draw straight onto the freeze:

- **Eraser** uses `destinationOut`. It must punch *marks only*, never the freeze underneath.
- **Mosaic / magnifier** sample pixels. They need to know what is beneath them.

Marks are strictly vector data (P4 — see `AGENTS.md`). Nothing is baked into `baseImage` until
Pin / Copy / Save, so `,` / `.` can always restore the unannotated base.

The layer used to be a block-backed `NSImage(size:flipped:)`. That is the origin of the trouble:
**a block-backed image gives you no way to read back what you have already drawn.** So when the
loop reached a mosaic, the marks before it were already painted — but unreachable. Every attempt
below is a different way of working around that one limitation.

## Attempt 1 — sample the freeze only

The original implementation. `drawMosaic` blurred a crop of the freeze under the brush.

**Broke:** ink under the smear was covered by opaque freeze pixels rather than blurred. On a dark
freeze that reads as "all black". The mark you were trying to obscure vanished, and so did the
blur effect.

## Attempt 2 — re-draw prior marks from vectors into the crop

`renderMarksLayer` passed the preceding marks down as `[Annotation]`; `compositeCropWithPriorMarks`
built a crop-sized buffer of freeze + those marks via `drawMarksSimple`, then blurred that.

**Fixed:** the first smear over ink. That shipped and was correct as far as it went.

**Broke:** nested mosaics. `drawMarksSimple` deliberately dispatched nested mosaics through the
plain `draw()` path — freeze-only — to avoid recursion. So a second smear composited the *first*
smear as opaque freeze pixels, and the black was back.

## Attempt 3 — nest `renderMarksLayer` inside the crop

The obvious next move: let nested mosaics keep *their* priors by recursing.

**Fixed:** the visuals. A second smear looked right.

**Broke:** everything. The overlay froze on the repro above. The cost is combinatorial, not
linear — every live mouse-move rebuilt each nested mosaic, and each of those rebuilt *its* priors
(other mosaics, plus every pencil polyline) inside the crop. Dense pencil sampling multiplies it.

This was reverted. **Do not reintroduce it.** If a future change makes nesting look tempting, the
symptom to expect is a hard lock during pencil drawing, not a gradual slowdown.

## The insight

Every attempt above tries to *reconstruct* what is under the mosaic. But by the time the render
loop reaches mosaic #k, marks 1…k−1 are **already correctly painted in the buffer** — including
mosaic #1's blurred output. There is nothing to reconstruct. It only looked impossible because
`NSImage(size:flipped:)` offers no readback.

Own the bitmap, and the answer is a memcpy.

## The solution: `MarksCanvas`

`Annotation/MarksCanvas.swift` wraps a `CGBitmapContext` we allocate ourselves:

- Pushed as `NSGraphicsContext.current`, so **all existing AppKit drawing code is unchanged** —
  `NSBezierPath`, `NSImage.draw`, every per-tool draw function works as before.
- CTM pre-scaled, so drawing happens in **points**, origin bottom-left, matching the overlay's
  `isFlipped == false`.
- `snapshotCrop(rect)` returns the marks drawn so far inside `rect`, copying **only that hull's
  rows** out of the backing store. A full-layer `context.makeImage()` per mosaic would memcpy the
  whole screen instead.
- `finishedImage()` wraps the finished buffer as an `NSImage` via a `CGDataProvider` that retains
  the canvas — sharing the pixels rather than copying them. The canvas must not be drawn into
  afterwards.

Mosaic then does: hull crop → `snapshotCrop` → composite over the freeze crop → `CIGaussianBlur`
→ clip to stroke/region. Nested mosaics work because the sample is *pixels already rendered*.
Magnifier `includeAnnotations` uses the same readback. No recursion anywhere.

### What that deleted

`compositeCropWithPriorMarks`, `priorMarksOverlappingHull`, `drawMarksSimple`, and the
`priorMarks: [Annotation]` parameter threaded through mosaic and magnifier. The `canvas` reference
replaces all of it.

## The second half: don't re-render every frame

Fixing sampling did not by itself fix the freeze, because the overlay re-rendered **every mark on
every mouse-move**. During a pencil drag the committed marks do not change at all — only the draft
grows — so that work was pure waste.

`SelectionOverlayNSView` now caches the rendered committed-marks layer, keyed by the committed
marks plus size / origin / scale / hidden-magnifier IDs / sample-image identity.

Drafts split by what they need:

| Draft tool | Where it draws | Why |
|---|---|---|
| pencil, shape, arrow, text, step | on top of the cached layer | just a stroke; nothing samples or erases |
| eraser | inside the layer | `destinationOut` must act on marks alone |
| mosaic, marker, magnifier | inside the layer | they sample what is under them |

So a pencil drag costs one cached blit plus one polyline, instead of a full layer render with a
blur per mosaic. Region drags for mosaic/marker/eraser still render per frame by design.

Two smaller wins in the same area:

- Freehand rejects samples closer than `pencilSampleSpacing`, so most moves in a fast scribble
  produce an identical stroke. `appendPencilOrShapeDraft` now compares payloads and skips the
  redraw entirely instead of re-rendering an unchanged picture.
- The playback-stamped freeze (`,` / `.`) is built eagerly and cached. It used to be a block-backed
  full-screen `NSImage` rebuilt per frame, which every mosaic then re-rasterized through
  `cgImage(forProposedRect:)`.
- `drawPencil` builds its path with `CGMutablePath.addLines(between:)` rather than a per-point
  Swift loop.

## Measurements

Both tables come from compiling the real `Annotation/` sources standalone (see *Reproducing the
measurements*), so "before" is the actual previous implementation, not a reconstruction.

### Correctness

Mean luminance where a second smear overlaps the first, dark freeze, bright ink underneath:

| | before | after |
|---|---|---|
| bare freeze | 0.0745 | 0.0745 |
| ink, no mosaic | 0.1559 | 0.1559 |
| 1 smear over ink | 0.3603 | 0.3612 |
| **2 smears, nested** | **0.2142** | **0.4228** |
| nested ÷ single | 0.59 | 1.17 |

Before, the nested smear collapsed toward bare freeze. After, it is comparable to a single smear —
both blur the same ink, which is the expected result.

### Cost

Isolated mosaic cost — render time with 3 smears minus the same scene without them — over N pencil
strokes of 150 points each, 1400×900:

| N strokes | no mosaic | +3 mosaics | mosaic cost |
|---|---|---|---|
| **before** 5 | 17.6 ms | 26.1 ms | 8.5 ms |
| **before** 20 | 24.2 ms | 34.5 ms | 10.3 ms |
| **before** 60 | 41.3 ms | 58.3 ms | 17.0 ms |
| **after** 5 | 22.2 ms | 28.4 ms | 6.2 ms |
| **after** 20 | 29.3 ms | 34.3 ms | 5.0 ms |
| **after** 60 | 45.1 ms | 51.9 ms | 6.8 ms |

Mosaic cost was growing with mark count (8.5 → 17.0 ms) and is now flat (~5–7 ms). That is the
asymptotic claim, and it is what stops the combinatorial blowup.

### The regression, kept deliberately

The baseline got **~5 ms slower per render** (17.6 → 22.2 ms at N=5). This was investigated, not
assumed: the first suspect was the full-buffer `context.makeImage()` copy, so it was replaced with
the shared-buffer `finishedImage()` — and the number did not move.

The cost is inherent. The old lazy block-backed `NSImage` rasterized *directly into the destination
context*; a readable canvas needs its own buffer plus a blit out of it. That is the price of pixel
readback.

It is worth paying because it is now charged **once per change** instead of once per frame — the
layer cache (*Don't re-render every frame*) removes it from the common drag entirely. It is still
charged per frame on mosaic/marker/eraser region drags, where at low mark counts the net is
slightly worse than before (28.4 vs 26.1 ms) and at high mark counts clearly better
(51.9 vs 58.3 ms).

## Constraints for future work

Rules that are load-bearing. Breaking any of these reproduces a bug that has already been fixed
once.

- **Do not nest `renderMarksLayer`** inside a crop. See *Attempt 3*.
- **Do not re-derive prior marks from vectors** for sampling. Use `snapshotCrop`. See *Attempt 2*.
- **Do not full-screen recomposite** freeze + marks per brush tip.
- **No `lockFocus`** inside overlay or `NSImage` drawing handlers — it steals the current context.
  This is why the playback-stamped freeze uses a `MarksCanvas`; the first version of that cache
  used `lockFocusFlipped` and had to be rewritten.
- **Give the canvas the destination's colour space** — the screen's for the overlay, the base
  image's for a bake. The block-backed image used to inherit this for free. Hardcoding one
  round-trips P3 marks through sRGB and visibly dulls them.
- **Coordinate space**: overlay is `isFlipped == false`; `MarksCanvas` matches (bottom-left origin,
  points). Bitmap memory row 0 is the *top* scanline, so `snapshotCrop` flips when converting
  points → pixels. Get this wrong and crops come out vertically mirrored.
- **`finishedImage()` shares the buffer.** Never draw into a canvas after calling it.
- **Cache keys hold images strongly and compare by identity** (`===`). An `ObjectIdentifier` on an
  unretained `NSImage` can collide after dealloc/realloc and serve a stale layer.

Still deferred, unrelated to this work: the eraser's concentric-ring brush tip (it currently
reuses the mosaic outline).

## Reproducing the measurements

The `Annotation/` folder has no dependencies outside itself apart from `SnipRecord` and `L10n`,
so it compiles standalone — which is how both tables above were produced, and how the nested-mosaic
bug can be caught without launching the app.

```bash
# `main.swift` must be named that: top-level code is only allowed in a file with that name.
swiftc -O EggplantShot/Annotation/*.swift EggplantShot/History/SnipRecord.swift \
       /tmp/harness/main.swift -o /tmp/harness/run && /tmp/harness/run
```

The harness needs `enum L10n { static func tr(_ s: String) -> String { s } }` as a stub, and must
force rasterization — `AnnotationCompositor.composite` returns a **lazy** block-backed `NSImage`,
so without `.cgImage(forProposedRect:context:hints:)` it measures nothing and reports 0.0 ms.

To compare against an older implementation, extract it to a temp tree and compile that instead:

```bash
git archive <ref> EggplantShot/Annotation EggplantShot/History/SnipRecord.swift | tar -x -C /tmp/oldsrc
```

A caution learned the hard way: the first version of the correctness assertion used a threshold so
lenient that it **passed on the buggy code too**. Any regression test written here should be
confirmed to fail against the pre-fix implementation before it is trusted.
