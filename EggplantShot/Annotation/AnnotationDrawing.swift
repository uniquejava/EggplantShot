import AppKit
import CoreImage

// Annotation draw dispatch + shared helpers.

enum AnnotationDrawing {
    /// Backdrop used to sample pixels for mosaic / blur marks.
    struct MosaicSampleContext {
        let image: NSImage
        /// Image-space point corresponding to selection-local `(0, 0)`.
        let selectionOriginInImage: CGPoint
    }

    /// Draw `annotation` with selection-local geometry offset by `origin` (selection frame origin in context).
    static func draw(_ annotation: Annotation, origin: CGPoint, sample: MosaicSampleContext? = nil) {
        switch annotation.payload {
        case .shape(let kind, let localRect, let style):
            let rect = localRect.offsetBy(dx: origin.x, dy: origin.y)
            drawShape(kind: kind, style: style, in: rect)
        case .arrow(let start, let end, let style, let caps):
            let s = CGPoint(x: start.x + origin.x, y: start.y + origin.y)
            let e = CGPoint(x: end.x + origin.x, y: end.y + origin.y)
            drawArrow(start: s, end: e, style: style, caps: caps)
        case .pencil(let points, let style):
            let offset = points.map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
            drawPencil(points: offset, style: style)
        case .marker(let geometry, let style):
            drawMarker(geometry: geometry, style: style, drawOrigin: origin, sample: sample)
        case .mosaic(let geometry, let style):
            drawMosaic(
                geometry: geometry,
                style: style,
                drawOrigin: origin,
                sample: sample,
                canvas: nil
            )
        case .eraser(let geometry, let style):
            drawEraser(geometry: geometry, style: style, drawOrigin: origin)
        case .text(let string, let localRect, let style):
            let rect = localRect.offsetBy(dx: origin.x, dy: origin.y)
            drawText(string: string, style: style, in: rect)
        case .step(let number, let center, let style):
            let c = CGPoint(x: center.x + origin.x, y: center.y + origin.y)
            drawStep(number: number, center: c, style: style)
        case .magnifier(let kind, let source, let lens, let style):
            drawMagnifier(
                kind: kind,
                source: source,
                lens: lens,
                style: style,
                drawOrigin: origin,
                sample: sample,
                showSourceBorder: true
            )
        }
    }

    /// Legacy entry used when the caller already converted a shape rect to context space.
    static func draw(_ annotation: Annotation, in rect: CGRect) {
        switch annotation.payload {
        case .shape(let kind, _, let style):
            drawShape(kind: kind, style: style, in: rect)
        case .arrow, .pencil, .marker, .mosaic, .eraser, .text, .step, .magnifier:
            draw(annotation, origin: .zero)
        }
    }

    /// Renders marks onto a transparent layer so eraser `destinationOut` punches annotations only.
    ///
    /// Mosaic / marker / magnifier (`includeAnnotations`) need to know what sits underneath them.
    /// They read it back out of the `MarksCanvas` they are drawing into — the marks before them are
    /// already painted there — instead of re-deriving it from vectors. So a mosaic over an earlier
    /// mosaic sees that one's blurred pixels, a highlight over an arrow multiplies the arrow rather
    /// than covering it, and the cost per mark does not grow with the mark count.
    /// `hiddenMagnifierSourceIDs`: skip nested source borders (lens still draws) for declutter.
    static func renderMarksLayer(
        _ annotations: [Annotation],
        size: CGSize,
        origin: CGPoint = .zero,
        scale: CGFloat = 2,
        colorSpace: CGColorSpace? = nil,
        sample: MosaicSampleContext? = nil,
        hiddenMagnifierSourceIDs: Set<UUID> = []
    ) -> NSImage? {
        guard size.width > 0, size.height > 0, !annotations.isEmpty else { return nil }
        guard let canvas = MarksCanvas(size: size, scale: scale, colorSpace: colorSpace) else {
            return nil
        }
        canvas.draw {
            for annotation in annotations {
                switch annotation.payload {
                case .magnifier(let kind, let source, let lens, let style):
                    drawMagnifier(
                        kind: kind,
                        source: source,
                        lens: lens,
                        style: style,
                        drawOrigin: origin,
                        sample: sample,
                        canvas: style.includeAnnotations ? canvas : nil,
                        showSourceBorder: !hiddenMagnifierSourceIDs.contains(annotation.id)
                    )
                case .mosaic(let geometry, let style):
                    drawMosaic(
                        geometry: geometry,
                        style: style,
                        drawOrigin: origin,
                        sample: sample,
                        canvas: canvas
                    )
                case .marker(let geometry, let style):
                    // Same reason as mosaic: the marker's result is opaque, so it has to read the
                    // marks under it back out of the canvas or it would cover them.
                    drawMarker(
                        geometry: geometry,
                        style: style,
                        drawOrigin: origin,
                        sample: sample,
                        canvas: canvas
                    )
                default:
                    draw(annotation, origin: origin, sample: sample)
                }
            }
        }
        return canvas.finishedImage()
    }

    /// Nested source frames to hide when ≥2 magnifiers (declutter). `revealedIDs` stay visible.
    static func nestedMagnifierSourceIDsToHide(
        in annotations: [Annotation],
        revealedIDs: Set<UUID> = []
    ) -> Set<UUID> {
        let mags = annotations.filter(\.isMagnifier)
        guard mags.count >= 2 else { return [] }
        var hidden = Set<UUID>()
        for ann in mags {
            guard case .magnifier(let kind, let source, let lens, _) = ann.payload else { continue }
            guard isMagnifierSourceNestedInLens(kind: kind, source: source, lens: lens) else { continue }
            if revealedIDs.contains(ann.id) { continue }
            hidden.insert(ann.id)
        }
        return hidden
    }

    /// True when the source sample frame sits fully inside the lens (rect or oval).
    static func isMagnifierSourceNestedInLens(kind: ShapeKind, source: CGRect, lens: CGRect) -> Bool {
        guard source.width >= 1, source.height >= 1, lens.width >= 1, lens.height >= 1 else {
            return false
        }
        switch kind {
        case .rectangle:
            return lens.contains(source)
        case .ellipse:
            let corners = [
                CGPoint(x: source.minX, y: source.minY),
                CGPoint(x: source.maxX, y: source.minY),
                CGPoint(x: source.minX, y: source.maxY),
                CGPoint(x: source.maxX, y: source.maxY),
            ]
            return corners.allSatisfy { ellipseContains(lens, point: $0) }
        }
    }

    static func ellipseContains(_ oval: CGRect, point: CGPoint) -> Bool {
        let rx = oval.width / 2
        let ry = oval.height / 2
        guard rx > 0, ry > 0 else { return false }
        let nx = (point.x - oval.midX) / rx
        let ny = (point.y - oval.midY) / ry
        return nx * nx + ny * ny <= 1
    }

    static func containsEraser(_ annotations: [Annotation]) -> Bool {
        annotations.contains { $0.isEraser }
    }


    static func applyStroke(_ style: AnnotationStyle, to path: NSBezierPath) {
        path.lineWidth = style.strokeWidth
        path.lineJoinStyle = .miter
        // Butt caps keep dash segments as rectangles (Snipaste-style).
        path.lineCapStyle = .butt
        let dash = style.lineStyle.dashPattern(strokeWidth: style.strokeWidth)
        if dash.isEmpty {
            path.setLineDash(nil, count: 0, phase: 0)
        } else {
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
    }
}

