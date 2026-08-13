import AppKit
import CoreImage

// Marker (highlighter) draw.

extension AnnotationDrawing {
    static func drawMarker(
        geometry: MosaicGeometry,
        style: MarkerStyle,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext? = nil
    ) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }

        let fill = style.fillColor

        // Marks paint on a transparent offscreen layer (eraser needs destinationOut).
        // Multiply against clear reads as opaque when composited — so for multiply colors,
        // clip to the mark, stamp the freeze/base under the clip, then multiply.
        if style.usesMultiplyBlend, let sample {
            switch geometry {
            case .stroke(let localPoints):
                drawMultiplyStroke(
                    localPoints: localPoints,
                    brushWidth: style.brushWidth,
                    fill: fill,
                    drawOrigin: drawOrigin,
                    sample: sample,
                    context: ctx
                )
            case .region(let mode, let localRect):
                drawMultiplyRegion(
                    mode: mode,
                    localRect: localRect,
                    fill: fill,
                    drawOrigin: drawOrigin,
                    sample: sample,
                    context: ctx
                )
            }
            return
        }

        ctx.compositingOperation = style.usesMultiplyBlend ? .multiply : .sourceOver

        switch geometry {
        case .stroke(let localPoints):
            guard !localPoints.isEmpty else { return }
            let brush = max(style.brushWidth, 1)
            let offset = localPoints.map { CGPoint(x: $0.x + drawOrigin.x, y: $0.y + drawOrigin.y) }
            guard let first = offset.first else { return }
            let path = NSBezierPath()
            if offset.count == 1 {
                let r = brush / 2
                path.appendOval(in: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2))
                fill.setFill()
                path.fill()
                return
            }
            path.move(to: first)
            for p in offset.dropFirst() { path.line(to: p) }
            path.lineWidth = brush
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            fill.setStroke()
            path.stroke()

        case .region(let mode, let localRect):
            guard localRect.width >= 1, localRect.height >= 1 else { return }
            let rect = localRect.offsetBy(dx: drawOrigin.x, dy: drawOrigin.y)
            let path: NSBezierPath
            switch mode {
            case .ellipse:
                path = NSBezierPath(ovalIn: rect)
            case .rectangle, .freehand:
                path = NSBezierPath(rect: rect)
            }
            fill.setFill()
            path.fill()
        }
    }

    /// Stamp freeze/base into the current clip so multiply isn't against clear.
    static func drawSampleBackdrop(_ sample: MosaicSampleContext, drawOrigin: CGPoint) {
        let origin = CGPoint(
            x: drawOrigin.x - sample.selectionOriginInImage.x,
            y: drawOrigin.y - sample.selectionOriginInImage.y
        )
        sample.image.draw(
            in: CGRect(origin: origin, size: sample.image.size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
    }

    static func drawMultiplyStroke(
        localPoints: [CGPoint],
        brushWidth: CGFloat,
        fill: NSColor,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext,
        context: NSGraphicsContext
    ) {
        guard !localPoints.isEmpty else { return }
        let cg = context.cgContext
        let brush = max(brushWidth, 1)
        let offset = localPoints.map { CGPoint(x: $0.x + drawOrigin.x, y: $0.y + drawOrigin.y) }
        guard let first = offset.first else { return }

        cg.saveGState()
        defer { cg.restoreGState() }

        let path = CGMutablePath()
        if offset.count == 1 {
            let r = brush / 2
            path.addEllipse(in: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2))
            cg.addPath(path)
            cg.clip()
        } else {
            path.move(to: first)
            for p in offset.dropFirst() { path.addLine(to: p) }
            cg.addPath(path)
            cg.setLineWidth(brush)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.replacePathWithStrokedPath()
            cg.clip()
        }

        drawSampleBackdrop(sample, drawOrigin: drawOrigin)
        context.compositingOperation = .multiply
        fill.setFill()
        // Huge fill — only the clipped stroke region is painted.
        CGRect(x: -1_000_000, y: -1_000_000, width: 2_000_000, height: 2_000_000).fill()
    }

    static func drawMultiplyRegion(
        mode: MosaicDrawMode,
        localRect: CGRect,
        fill: NSColor,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext,
        context: NSGraphicsContext
    ) {
        guard localRect.width >= 1, localRect.height >= 1 else { return }
        let rect = localRect.offsetBy(dx: drawOrigin.x, dy: drawOrigin.y)
        let path: NSBezierPath
        switch mode {
        case .ellipse:
            path = NSBezierPath(ovalIn: rect)
        case .rectangle, .freehand:
            path = NSBezierPath(rect: rect)
        }

        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        path.addClip()
        drawSampleBackdrop(sample, drawOrigin: drawOrigin)
        context.compositingOperation = .multiply
        fill.setFill()
        path.fill()
    }
}
