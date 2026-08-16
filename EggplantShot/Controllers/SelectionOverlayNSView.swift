import AppKit

final class SelectionOverlayNSView: NSView {
    enum CursorMode {
        /// Idle / free-drag: AppKit owns the white ＋ via cursor rects.
        case selectingPlus
        /// Refine / annotate: controller sets the cursor from hit-testing.
        case controllerDriven
    }

    var selectionRect: CGRect = .null
    var showHandles = false
    var handleVisualSize: CGFloat = 8
    var annotations: [Annotation] = []
    var draftAnnotation: Annotation?
    var selectedAnnotation: Annotation?
    var annotationHandleSize: CGFloat = 7
    /// Historical crop drawn inside the selection (`,` / `.` playback).
    var playbackImage: NSImage?
    /// Skip drawing this mark while the inline editor is showing it.
    var editingAnnotationID: UUID?
    /// Snipaste-style hover: text corner badges while the pointer is over a text mark.
    var hoveredTextID: UUID?
    /// Snipaste-style hover: dashed outline over a non-selected rect / oval paint region
    /// (marker / mosaic / eraser).
    var hoveredPaintRegionID: UUID?
    /// While moving / resizing a selected marker region: solid hairline (Snipaste).
    var showSolidMarkerRegionBorder = false
    /// Hide Snipaste text corner badges while the text mark is being moved / resized.
    var hideTextCornerBadges = false
    /// Magnifier nested source frames to skip while decluttering (≥2 magnifiers, tool inactive).
    var hiddenMagnifierSourceIDs: Set<UUID> = []
    /// Pin-edit: annotate a pinned bitmap in place. Set to that bitmap and this view becomes a bare
    /// marks layer over the pin panel showing through — no freeze backdrop, dim, crop chrome or size
    /// badge — and effect tools sample the bitmap instead of the freeze.
    var pinEditImage: NSImage?
    var onCursorUpdate: (() -> Void)?
    var cursorMode: CursorMode = .selectingPlus {
        didSet {
            guard cursorMode != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    private let freezeImage: NSImage?
    private let accent = NSColor.systemBlue
    private var cursorTrackingArea: NSTrackingArea?

    private var isPinEdit: Bool { pinEditImage != nil }

    /// Extra reach outside the bitmap for handles / badges that straddle its edge. Shared with the
    /// controller's event routing so clicks and hit-tests agree on what a pin-edit session owns.
    static let pinEditHitSlop: CGFloat = 8

    /// Rendered committed-marks layer, reused while only the draft changes.
    /// A pencil drag would otherwise re-blur every mosaic on every mouse-move.
    private var cachedMarksLayer: NSImage?
    private var cachedMarksKey: MarksLayerKey?
    /// Freeze with history playback stamped in; rebuilt only when the inputs change, because
    /// each mosaic rasterizes this image and a block-backed `NSImage` would redo the whole screen.
    private var cachedStampedFreeze: NSImage?
    private var cachedStampedKey: StampedFreezeKey?

    /// Everything the committed layer's pixels depend on. Images are held strongly and compared
    /// by identity: a released `NSImage` could otherwise be replaced at the same address and let
    /// a stale layer survive.
    private struct MarksLayerKey: Equatable {
        let annotations: [Annotation]
        let size: CGSize
        let origin: CGPoint
        let scale: CGFloat
        let hiddenMagnifierSourceIDs: Set<UUID>
        let sampleImage: NSImage?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.sampleImage === rhs.sampleImage
                && lhs.size == rhs.size
                && lhs.origin == rhs.origin
                && lhs.scale == rhs.scale
                && lhs.hiddenMagnifierSourceIDs == rhs.hiddenMagnifierSourceIDs
                && lhs.annotations == rhs.annotations
        }
    }

    private struct StampedFreezeKey: Equatable {
        let playback: NSImage
        let selectionRect: CGRect

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.playback === rhs.playback && lhs.selectionRect == rhs.selectionRect
        }
    }

    init(frame frameRect: NSRect, freezeImage: NSImage?) {
        self.freezeImage = freezeImage
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override var isOpaque: Bool { freezeImage != nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [
                .activeAlways,
                .inVisibleRect,
                .cursorUpdate,
                .mouseEnteredAndExited,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func resetCursorRects() {
        guard cursorMode == .selectingPlus else { return }
        addCursorRect(bounds, cursor: AnnotationCursors.whitePlus)
    }

    override func cursorUpdate(with event: NSEvent) {
        switch cursorMode {
        case .selectingPlus:
            // Let AppKit apply the cursor rect we registered.
            super.cursorUpdate(with: event)
        case .controllerDriven:
            onCursorUpdate?()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        // Multi-display: only the key window’s cursor rects apply.
        window?.makeKeyAndOrderFront(nil)
    }

    /// Pin-edit: only the bitmap (plus handle slop) and any live text editor are ours. Everything
    /// else in the lid's margins falls through, so other apps stay clickable while a pin is edited.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isPinEdit else { return super.hitTest(point) }
        if let hit = super.hitTest(point), hit !== self {
            return hit
        }
        let reachable = selectionRect.insetBy(dx: -Self.pinEditHitSlop, dy: -Self.pinEditHitSlop)
        return reachable.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        // Pin-edit: the pin panel underneath is the backdrop, so draw marks and nothing else.
        if isPinEdit {
            guard !selectionRect.isNull, selectionRect.width > 0, selectionRect.height > 0 else { return }
            drawAnnotations()
            return
        }

        // Freeze backdrop (Snipaste-style). Without it, fall back to punch-through dim.
        if let freezeImage {
            freezeImage.draw(
                in: bounds,
                from: CGRect(origin: .zero, size: freezeImage.size),
                operation: .copy,
                fraction: 1
            )
        }

        let dimPath = NSBezierPath(rect: bounds)
        if !selectionRect.isNull, selectionRect.width > 0, selectionRect.height > 0 {
            dimPath.append(NSBezierPath(rect: selectionRect))
            dimPath.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.45).setFill()
        dimPath.fill()

        guard !selectionRect.isNull, selectionRect.width > 0, selectionRect.height > 0 else { return }

        // Legacy path when freeze capture failed: clear the hole to the live desktop.
        if freezeImage == nil {
            // `fill(using:)`, not `fill()`: bare NSRectFill always composites `copy`, so it would
            // stamp the dim color set above into the hole instead of clearing it.
            selectionRect.fill(using: .clear)
        }

        // History playback: paint archived base inside the selection (rest of screen stays freeze).
        if let playbackImage {
            playbackImage.draw(
                in: selectionRect,
                from: CGRect(origin: .zero, size: playbackImage.size),
                operation: .copy,
                fraction: 1
            )
        }

        let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1.5
        accent.setStroke()
        border.stroke()

        drawAnnotations()

        if showHandles {
            drawSelectionHandles()
        }

        let w = Int(selectionRect.width.rounded())
        let h = Int(selectionRect.height.rounded())
        let label = "\(w) × \(h)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        var labelOrigin = CGPoint(
            x: selectionRect.minX,
            y: selectionRect.maxY + 8
        )
        if labelOrigin.y + size.height + 4 > bounds.maxY {
            labelOrigin.y = selectionRect.minY - size.height - 8
        }
        let bg = CGRect(origin: labelOrigin, size: size).insetBy(dx: -6, dy: -3)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        label.draw(at: labelOrigin, withAttributes: attrs)
    }

    private func drawAnnotations() {
        let origin = selectionRect.origin
        let sample = mosaicSampleContext()
        let scale = window?.backingScaleFactor ?? 2
        let space = window?.screen?.colorSpace?.cgColorSpace
        // Fullscreen annotate: marks may sit outside the blue selection — no clip.
        // Offscreen layer so eraser destinationOut punches marks only, not the freeze.
        var committed: [Annotation] = []
        committed.reserveCapacity(annotations.count)
        for ann in annotations where ann.id != editingAnnotationID {
            committed.append(ann)
        }

        // A draft that erases or samples has to be inside the layer; anything else is just a
        // stroke on top, which lets the committed layer stay cached for the whole drag.
        let draftNeedsLayer = draftAnnotation.map(Self.draftBelongsInLayer) ?? false
        let layer: NSImage?
        if let draft = draftAnnotation, draftNeedsLayer {
            layer = AnnotationDrawing.renderMarksLayer(
                committed + [draft],
                size: bounds.size,
                origin: origin,
                scale: scale,
                colorSpace: space,
                sample: sample,
                hiddenMagnifierSourceIDs: hiddenMagnifierSourceIDs
            )
        } else {
            layer = committedMarksLayer(
                committed,
                origin: origin,
                scale: scale,
                colorSpace: space,
                sample: sample
            )
        }
        withInkClip {
            if let layer {
                layer.draw(
                    in: bounds,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }
            if let draft = draftAnnotation, !draftNeedsLayer {
                AnnotationDrawing.draw(draft, origin: origin, sample: sample)
            }
        }

        if let draft = draftAnnotation {
            // Mosaic / marker / eraser region drag: solid 1px contrast hairline (edit chrome only).
            if case .mosaic(.region(let mode, let rect), _) = draft.payload {
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                drawRegionChrome(in: r, mode: mode, dashed: false)
            } else if case .marker(.region(let mode, let rect), _) = draft.payload {
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                drawRegionChrome(in: r, mode: mode, dashed: false)
            } else if case .eraser(.region(let mode, let rect), _) = draft.payload {
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                drawRegionChrome(in: r, mode: mode, dashed: false)
            }
        }

        if let selected = selectedAnnotation,
           !selected.isPencil,
           !selected.isMosaicStroke,
           !selected.isMarkerStroke,
           !selected.isEraserStroke,
           !selected.isText,
           !selected.isStep,
           selected.id != editingAnnotationID {
            if case .arrow(let start, let end, _, _) = selected.payload {
                let s = CGPoint(x: start.x + origin.x, y: start.y + origin.y)
                let e = CGPoint(x: end.x + origin.x, y: end.y + origin.y)
                AnnotationDrawing.drawArrowEndpointHandles(
                    start: s,
                    end: e,
                    size: annotationHandleSize
                )
            } else if case .mosaic(.region(let mode, let rect), _) = selected.payload {
                // After release: dashed hairline + resize handles.
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                drawRegionChrome(in: r, mode: mode, dashed: true)
                AnnotationDrawing.drawHandles(in: r, size: annotationHandleSize)
            } else if case .eraser(.region(let mode, let rect), _) = selected.payload {
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                drawRegionChrome(in: r, mode: mode, dashed: true)
                AnnotationDrawing.drawHandles(in: r, size: annotationHandleSize)
            } else if case .marker(.region(let mode, let rect), _) = selected.payload {
                // Snipaste marker: handles only when idle; solid border while moving / resizing.
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                if showSolidMarkerRegionBorder {
                    drawRegionChrome(in: r, mode: mode, dashed: false)
                }
                AnnotationDrawing.drawHandles(in: r, size: annotationHandleSize)
            } else if case .magnifier(_, _, let lens, _) = selected.payload {
                // Source is move-only; lens handles resize both frames at fixed scale.
                let lensR = lens.offsetBy(dx: origin.x, dy: origin.y)
                AnnotationDrawing.drawHandles(in: lensR, size: annotationHandleSize)
            } else {
                let r = selected.boundingRect.offsetBy(dx: origin.x, dy: origin.y)
                AnnotationDrawing.drawHandles(in: r, size: annotationHandleSize)
            }
        }

        if let selected = selectedAnnotation,
           selected.isStep,
           selected.id != editingAnnotationID {
            let r = selected.boundingRect.offsetBy(dx: origin.x, dy: origin.y)
            drawStepSelectionOutline(in: r)
        }

        // Snipaste text: white frame + 4 blue corner badges on hover or selection (not editing).
        if let textChrome = textResizeChromeAnnotation() {
            let r = textChrome.boundingRect.offsetBy(dx: origin.x, dy: origin.y)
            let scale = window?.backingScaleFactor ?? 2
            AnnotationDrawing.drawTextResizeChrome(in: r, lineWidth: 1 / max(scale, 1))
        }

        if let hid = hoveredPaintRegionID,
           hid != selectedAnnotation?.id,
           let hovered = annotations.first(where: { $0.id == hid }),
           let region = hovered.paintRegion {
            let r = region.rect.offsetBy(dx: origin.x, dy: origin.y)
            drawRegionChrome(in: r, mode: region.mode, dashed: true)
        }
    }

    /// Pin-edit ink is clipped to the bitmap: a mark running past the edge is cropped when it bakes,
    /// so it has to look cropped while drawing too. Chrome (handles / badges) stays unclipped so the
    /// grips on an edge-hugging mark are still reachable.
    private func withInkClip(_ body: () -> Void) {
        guard isPinEdit else {
            body()
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selectionRect).addClip()
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Hover or selection (not editing) → Snipaste 4-corner text chrome.
    /// Hidden while that text mark is mid move / resize.
    private func textResizeChromeAnnotation() -> Annotation? {
        guard !hideTextCornerBadges else { return nil }
        if let selected = selectedAnnotation,
           selected.isText,
           selected.id != editingAnnotationID {
            return selected
        }
        if let hid = hoveredTextID,
           hid != editingAnnotationID,
           let hovered = annotations.first(where: { $0.id == hid }),
           hovered.isText {
            return hovered
        }
        return nil
    }

    /// Snipaste mosaic / marker / eraser region: 1 device-pixel hairline; black on light / white on dark.
    /// Mosaic / eraser: solid while dragging, dashed when selected. Marker: solid while drawing / moving /
    /// resizing; idle selected = handles only. Any non-selected region under the pointer = dashed hover
    /// (only while it is actually grabable — see `paintRegionID`).
    private func drawRegionChrome(in rect: CGRect, mode: MosaicDrawMode, dashed: Bool) {
        guard rect.width >= 1, rect.height >= 1 else { return }
        let scale = window?.backingScaleFactor ?? 2
        let w = 1 / max(scale, 1)
        contrastChromeColor(around: CGPoint(x: rect.midX, y: rect.midY)).setStroke()
        let path: NSBezierPath
        switch mode {
        case .ellipse:
            path = NSBezierPath(ovalIn: rect.insetBy(dx: w / 2, dy: w / 2))
        case .rectangle, .freehand:
            path = NSBezierPath(rect: rect.insetBy(dx: w / 2, dy: w / 2))
        }
        path.lineWidth = w
        if dashed {
            let dash: [CGFloat] = [3, 2]
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        path.stroke()
    }

    /// Sample freeze under `point` (view / image space); fall back to white on unknown dark.
    private func contrastChromeColor(around point: CGPoint) -> NSColor {
        // Pin-edit samples the pinned bitmap, whose image space starts at the bitmap's origin, and
        // skips the outside-selection dimming factor — there is no dim layer over a pin.
        if let pinEditImage {
            let inImage = CGPoint(x: point.x - selectionRect.minX, y: point.y - selectionRect.minY)
            let sampled = ContrastChrome.averageLuminance(
                in: pinEditImage,
                aroundPointInImageSpace: inImage
            ) ?? 0.2
            return ContrastChrome.hairline(onLuminance: sampled)
        }
        let sampled = freezeImage.flatMap {
            ContrastChrome.averageLuminance(in: $0, aroundPointInImageSpace: point)
        } ?? 0.2
        return ContrastChrome.hairline(
            onLuminance: ContrastChrome.adjustedLuminance(
                sampled,
                point: point,
                selectionRect: selectionRect
            )
        )
    }

    /// Snipaste step selection: dashed contrast square around the badge.
    private func drawStepSelectionOutline(in rect: CGRect) {
        let pad: CGFloat = 3
        let frame = rect.insetBy(dx: -pad, dy: -pad)
        let scale = window?.backingScaleFactor ?? 2
        let w = 1 / max(scale, 1)
        contrastChromeColor(around: CGPoint(x: frame.midX, y: frame.midY)).setStroke()
        let path = NSBezierPath(rect: frame.insetBy(dx: w / 2, dy: w / 2))
        path.lineWidth = w
        let dash: [CGFloat] = [3, 2]
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.stroke()
    }

    private func drawSelectionHandles() {
        let centers: [CGPoint] = [
            CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.midX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.minX, y: selectionRect.midY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.midY),
            CGPoint(x: selectionRect.minX, y: selectionRect.minY),
            CGPoint(x: selectionRect.midX, y: selectionRect.minY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.minY),
        ]
        let s = handleVisualSize
        for c in centers {
            let r = CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: r).fill()
            accent.setStroke()
            let stroke = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
            stroke.lineWidth = 1.5
            stroke.stroke()
        }
    }

    /// Drafts that must render inside the marks layer: eraser needs `destinationOut` against the
    /// marks alone, and mosaic / marker / magnifier sample what is already drawn under them.
    private static func draftBelongsInLayer(_ draft: Annotation) -> Bool {
        switch draft.payload {
        case .eraser, .mosaic, .marker, .magnifier:
            return true
        case .shape, .arrow, .pencil, .text, .step:
            return false
        }
    }

    /// Cached render of the committed marks. Only re-renders when something it draws changes.
    private func committedMarksLayer(
        _ committed: [Annotation],
        origin: CGPoint,
        scale: CGFloat,
        colorSpace: CGColorSpace?,
        sample: AnnotationDrawing.MosaicSampleContext?
    ) -> NSImage? {
        guard !committed.isEmpty else {
            cachedMarksLayer = nil
            cachedMarksKey = nil
            return nil
        }
        let key = MarksLayerKey(
            annotations: committed,
            size: bounds.size,
            origin: origin,
            scale: scale,
            hiddenMagnifierSourceIDs: hiddenMagnifierSourceIDs,
            sampleImage: sample?.image
        )
        if key == cachedMarksKey, let cachedMarksLayer {
            return cachedMarksLayer
        }
        let layer = AnnotationDrawing.renderMarksLayer(
            committed,
            size: bounds.size,
            origin: origin,
            scale: scale,
            colorSpace: colorSpace,
            sample: sample,
            hiddenMagnifierSourceIDs: hiddenMagnifierSourceIDs
        )
        cachedMarksLayer = layer
        cachedMarksKey = layer == nil ? nil : key
        return layer
    }

    /// Freeze backdrop, with history playback stamped into the selection when present.
    private func mosaicSampleContext() -> AnnotationDrawing.MosaicSampleContext? {
        // Pin-edit: the pinned bitmap *is* the backdrop, and mark geometry is already relative to
        // its bottom-left — same shape `AnnotationCompositor` builds when it bakes.
        if let pinEditImage {
            return AnnotationDrawing.MosaicSampleContext(
                image: pinEditImage,
                selectionOriginInImage: .zero
            )
        }
        guard let freezeImage else { return nil }
        let origin = selectionRect.origin
        guard let playbackImage,
              !selectionRect.isNull,
              selectionRect.width > 0,
              selectionRect.height > 0
        else {
            return AnnotationDrawing.MosaicSampleContext(
                image: freezeImage,
                selectionOriginInImage: origin
            )
        }
        return AnnotationDrawing.MosaicSampleContext(
            image: stampedFreeze(freezeImage, playback: playbackImage),
            selectionOriginInImage: origin
        )
    }

    /// Flattened eagerly and cached: mosaic reads this through `cgImage(forProposedRect:)`, and a
    /// block-backed `NSImage` would re-rasterize the full screen for every mosaic, every frame.
    /// Drawn into an owned bitmap — `lockFocus` here would steal the window's context mid-`draw`.
    private func stampedFreeze(_ freeze: NSImage, playback: NSImage) -> NSImage {
        let key = StampedFreezeKey(
            playback: playback,
            selectionRect: selectionRect
        )
        if key == cachedStampedKey, let cachedStampedFreeze {
            return cachedStampedFreeze
        }
        // Keep the freeze's own pixel density so the blur samples full-resolution pixels.
        let freezePixels = freeze.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let freezeScale = freezePixels.map { CGFloat($0.width) / freeze.size.width } ?? 2
        guard let canvas = MarksCanvas(
            size: freeze.size,
            scale: max(freezeScale, 1),
            colorSpace: freezePixels?.colorSpace
        ) else {
            return freeze
        }
        canvas.draw {
            freeze.draw(
                in: CGRect(origin: .zero, size: freeze.size),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
            playback.draw(
                in: selectionRect,
                from: CGRect(origin: .zero, size: playback.size),
                operation: .copy,
                fraction: 1
            )
        }
        guard let stamped = canvas.finishedImage() else { return freeze }
        cachedStampedFreeze = stamped
        cachedStampedKey = key
        return stamped
    }
}
