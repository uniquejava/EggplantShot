import AppKit

// MARK: - Overlay panels

final class SelectionPanel: NSPanel {
    let screenFrame: CGRect
    private let overlayView: SelectionOverlayNSView
    /// AppKit asks views to update the cursor; we forward so the controller can re-apply.
    var onCursorUpdate: (() -> Void)? {
        get { overlayView.onCursorUpdate }
        set { overlayView.onCursorUpdate = newValue }
    }

    init(screen: NSScreen, freezeImage: NSImage?) {
        self.screenFrame = screen.frame
        self.overlayView = SelectionOverlayNSView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            freezeImage: freezeImage
        )

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        // Opaque when frozen so live desktop cannot show through.
        isOpaque = freezeImage != nil
        backgroundColor = freezeImage != nil ? .black : .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = overlayView
    }

    func setSelection(
        _ globalRect: CGRect,
        showHandles: Bool,
        handleVisualSize: CGFloat,
        annotations: [Annotation],
        draftAnnotation: Annotation?,
        selectedAnnotation: Annotation?,
        annotationHandleSize: CGFloat,
        playbackImage: NSImage?,
        editingAnnotationID: UUID?,
        hoveredTextID: UUID?
    ) {
        let local: CGRect
        if globalRect.isNull {
            local = .null
        } else {
            local = CGRect(
                x: globalRect.origin.x - screenFrame.origin.x,
                y: globalRect.origin.y - screenFrame.origin.y,
                width: globalRect.width,
                height: globalRect.height
            )
        }
        overlayView.selectionRect = local
        overlayView.showHandles = showHandles
        overlayView.handleVisualSize = handleVisualSize
        overlayView.annotations = annotations
        overlayView.draftAnnotation = draftAnnotation
        overlayView.selectedAnnotation = selectedAnnotation
        overlayView.annotationHandleSize = annotationHandleSize
        overlayView.playbackImage = playbackImage
        overlayView.editingAnnotationID = editingAnnotationID
        overlayView.hoveredTextID = hoveredTextID
        overlayView.needsDisplay = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SelectionOverlayNSView: NSView {
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
    var onCursorUpdate: (() -> Void)?

    private let freezeImage: NSImage?
    private let accent = NSColor.systemBlue

    init(frame frameRect: NSRect, freezeImage: NSImage?) {
        self.freezeImage = freezeImage
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override var isOpaque: Bool { freezeImage != nil }

    override func resetCursorRects() {}
    override func cursorUpdate(with event: NSEvent) {
        onCursorUpdate?()
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
        for ann in annotations {
            if ann.id == editingAnnotationID { continue }
            AnnotationDrawing.draw(ann, origin: origin, sample: sample)
        }
        if let draft = draftAnnotation {
            AnnotationDrawing.draw(draft, origin: origin, sample: sample)
            // Mosaic region drag: solid 1px contrast hairline (edit chrome only).
            if case .mosaic(.region(let mode, let rect), _) = draft.payload {
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                drawMosaicRegionChrome(in: r, mode: mode, dashed: false)
            }
        }

        if let selected = selectedAnnotation,
           !selected.isPencil,
           !selected.isMosaicStroke,
           !selected.isText,
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
                drawMosaicRegionChrome(in: r, mode: mode, dashed: true)
                AnnotationDrawing.drawHandles(in: r, size: annotationHandleSize, accent: accent)
            } else {
                let r = selected.boundingRect.offsetBy(dx: origin.x, dy: origin.y)
                AnnotationDrawing.drawHandles(in: r, size: annotationHandleSize, accent: accent)
            }
        }

        if let hid = hoveredTextID,
           hid != editingAnnotationID,
           let hovered = annotations.first(where: { $0.id == hid }),
           hovered.isText {
            let r = hovered.boundingRect.offsetBy(dx: origin.x, dy: origin.y)
            drawTextHoverOutline(in: r, style: hovered.textStyle)
        }
    }

    /// Snipaste mosaic region: 1 device-pixel hairline; black on light / white on dark.
    /// Solid while dragging; dashed once committed & selected.
    private func drawMosaicRegionChrome(in rect: CGRect, mode: MosaicDrawMode, dashed: Bool) {
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
