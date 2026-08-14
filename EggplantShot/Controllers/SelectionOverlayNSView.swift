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
    /// Snipaste-style hover: dashed outline while the pointer is over a text mark.
    var hoveredTextID: UUID?
    /// Snipaste-style hover: dashed outline over a non-selected marker region.
    var hoveredMarkerRegionID: UUID?
    /// While moving / resizing a selected marker region: solid hairline (Snipaste).
    var showSolidMarkerRegionBorder = false
    /// Magnifier nested source frames to skip while decluttering (≥2 magnifiers, tool inactive).
    var hiddenMagnifierSourceIDs: Set<UUID> = []
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

    override func draw(_ dirtyRect: NSRect) {
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
            NSGraphicsContext.current?.compositingOperation = .clear
            selectionRect.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
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
        // Fullscreen annotate: marks may sit outside the blue selection — no clip.
        // Offscreen layer so eraser destinationOut punches marks only, not the freeze.
        var marks: [Annotation] = []
        marks.reserveCapacity(annotations.count + 1)
        for ann in annotations where ann.id != editingAnnotationID {
            marks.append(ann)
        }
        if let draft = draftAnnotation {
            marks.append(draft)
        }
        if let layer = AnnotationDrawing.renderMarksLayer(
            marks,
            size: bounds.size,
            origin: origin,
            sample: sample,
            hiddenMagnifierSourceIDs: hiddenMagnifierSourceIDs
        ) {
            layer.draw(
                in: bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
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
                    size: annotationHandleSize,
                    accent: accent
                )
            } else if case .mosaic(.region(let mode, let rect), _) = selected.payload {
                // After release: dashed hairline + resize handles.
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                drawRegionChrome(in: r, mode: mode, dashed: true)
                AnnotationDrawing.drawHandles(in: r, size: annotationHandleSize, accent: accent)
            } else if case .eraser(.region(let mode, let rect), _) = selected.payload {
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                drawRegionChrome(in: r, mode: mode, dashed: true)
                AnnotationDrawing.drawHandles(in: r, size: annotationHandleSize, accent: accent)
            } else if case .marker(.region(let mode, let rect), _) = selected.payload {
                // Snipaste marker: handles only when idle; solid border while moving / resizing.
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                if showSolidMarkerRegionBorder {
                    drawRegionChrome(in: r, mode: mode, dashed: false)
                }
                AnnotationDrawing.drawHandles(in: r, size: annotationHandleSize, accent: accent)
            } else if case .magnifier(_, _, let lens, _) = selected.payload {
                // Source is move-only; lens handles resize both frames at fixed scale.
                let lensR = lens.offsetBy(dx: origin.x, dy: origin.y)
                AnnotationDrawing.drawHandles(in: lensR, size: annotationHandleSize, accent: accent)
            } else {
                let r = selected.boundingRect.offsetBy(dx: origin.x, dy: origin.y)
                AnnotationDrawing.drawHandles(in: r, size: annotationHandleSize, accent: accent)
            }
        }

        if let selected = selectedAnnotation,
           selected.isStep,
           selected.id != editingAnnotationID {
            let r = selected.boundingRect.offsetBy(dx: origin.x, dy: origin.y)
            drawStepSelectionOutline(in: r)
        }

        if let hid = hoveredTextID,
           hid != editingAnnotationID,
           let hovered = annotations.first(where: { $0.id == hid }),
           hovered.isText {
            let r = hovered.boundingRect.offsetBy(dx: origin.x, dy: origin.y)
            drawTextHoverOutline(in: r, style: hovered.textStyle)
        }

        if let hid = hoveredMarkerRegionID,
           hid != selectedAnnotation?.id,
           let hovered = annotations.first(where: { $0.id == hid }),
           case .marker(.region(let mode, let rect), _) = hovered.payload {
            let r = rect.offsetBy(dx: origin.x, dy: origin.y)
            drawRegionChrome(in: r, mode: mode, dashed: true)
        }
    }

    /// Snipaste mosaic / marker region: 1 device-pixel hairline; black on light / white on dark.
    /// Mosaic: solid while dragging, dashed when selected. Marker: solid while drawing / moving / resizing;
    /// idle selected = handles only; non-selected hover = dashed.
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

    /// 1px dashed hover frame; black on light / white on dark (matches edit chrome).
    private func drawTextHoverOutline(in rect: CGRect, style: TextStyle) {
        let scale = window?.backingScaleFactor ?? 2
        let w = 1 / max(scale, 1)
        let point = CGPoint(x: rect.midX, y: rect.midY)
        let sampled = freezeImage.flatMap {
            ContrastChrome.averageLuminance(in: $0, aroundPointInImageSpace: point)
        } ?? 0.2
        ContrastChrome.textHairline(
            style: style,
            freezeLuminance: ContrastChrome.adjustedLuminance(
                sampled,
                point: point,
                selectionRect: selectionRect
            )
        ).setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: w / 2, dy: w / 2))
        path.lineWidth = w
        let dash: [CGFloat] = [3, 2]
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.stroke()
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

    /// Freeze backdrop, with history playback stamped into the selection when present.
    private func mosaicSampleContext() -> AnnotationDrawing.MosaicSampleContext? {
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
        let stamped = NSImage(size: freezeImage.size, flipped: false) { _ in
            freezeImage.draw(
                in: CGRect(origin: .zero, size: freezeImage.size),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
            playbackImage.draw(
                in: self.selectionRect,
                from: CGRect(origin: .zero, size: playbackImage.size),
                operation: .copy,
                fraction: 1
            )
            return true
        }
        return AnnotationDrawing.MosaicSampleContext(
            image: stamped,
            selectionOriginInImage: origin
        )
    }
}
