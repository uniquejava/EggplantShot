import AppKit
import CoreImage

// Magnifier lens draw.

extension AnnotationDrawing {
    static func drawMagnifier(
        kind: ShapeKind,
        source: CGRect,
        lens: CGRect,
        style: MagnifierStyle,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext?,
        canvas: MarksCanvas? = nil,
        showSourceBorder: Bool = true
    ) {
        let sourceDraw = source.offsetBy(dx: drawOrigin.x, dy: drawOrigin.y)
        let lensDraw = lens.offsetBy(dx: drawOrigin.x, dy: drawOrigin.y)
        guard sourceDraw.width >= 1, sourceDraw.height >= 1 else { return }

        // Draft: source only — solid palette stroke; lens + dashed source appear on mouse-up.
        guard lensDraw.width >= 1, lensDraw.height >= 1 else {
            style.color.setStroke()
            strokeMagnifierFrame(
                kind: kind,
                rect: sourceDraw,
                lineWidth: style.strokeWidth,
                dash: []
            )
            return
        }

        // Magnified content inside the lens (sample freeze/base, or freeze + marks under the source).
        if let sample {
            if style.includeAnnotations, let canvas {
                drawMagnifiedContentWithAnnotations(
                    kind: kind,
                    sourceLocal: source,
                    lensDraw: lensDraw,
                    sample: sample,
                    drawOrigin: drawOrigin,
                    canvas: canvas
                )
            } else {
                drawMagnifiedContent(
                    kind: kind,
                    sourceLocal: source,
                    lensDraw: lensDraw,
                    sample: sample,
                    drawOrigin: drawOrigin
                )
            }
        }

        // Source border: dashed contrast hairline inside the lens (not palette);
        // thick palette stroke where source sits outside the lens.
        // Nested sources may be hidden (declutter) when ≥2 magnifiers and tool inactive.
        if showSourceBorder {
            let dashColor = magnifierSourceDashColor(sourceLocal: source, sample: sample)
            drawMagnifierSourceBorder(
                kind: kind,
                source: sourceDraw,
                lens: lensDraw,
                style: style,
                dashColor: dashColor,
                solidColor: style.color
            )
        }

        style.color.setStroke()
        let inset = style.strokeWidth / 2
        let lensPath = magnifierPath(kind: kind, in: lensDraw.insetBy(dx: inset, dy: inset))
        lensPath.lineWidth = style.strokeWidth
        lensPath.lineJoinStyle = .miter
        lensPath.stroke()

        if showSourceBorder,
           let (a, b) = magnifierConnectorEndpoints(source: sourceDraw, lens: lensDraw) {
            let line = NSBezierPath()
            line.move(to: a)
            line.line(to: b)
            line.lineWidth = style.strokeWidth
            line.lineCapStyle = .round
            line.stroke()
        }
    }

    /// Contrast hairline for the nested source dash (black on light / white on dark).
    static func magnifierSourceDashColor(
        sourceLocal: CGRect,
        sample: MosaicSampleContext?
    ) -> NSColor {
        guard let sample else {
            return NSColor.black.withAlphaComponent(0.65)
        }
        let imagePoint = CGPoint(
            x: sourceLocal.midX + sample.selectionOriginInImage.x,
            y: sourceLocal.midY + sample.selectionOriginInImage.y
        )
        let luminance = ContrastChrome.averageLuminance(
            in: sample.image,
            aroundPointInImageSpace: imagePoint
        ) ?? 0.75
        return ContrastChrome.hairline(onLuminance: luminance)
    }

    /// Source outline relative to the lens: contrast dashed inside, palette solid outside.
    static func drawMagnifierSourceBorder(
        kind: ShapeKind,
        source: CGRect,
        lens: CGRect,
        style: MagnifierStyle,
        dashColor: NSColor,
        solidColor: NSColor
    ) {
        guard let ctx = NSGraphicsContext.current else { return }
        let deviceScale = max(abs(ctx.cgContext.userSpaceToDeviceSpaceTransform.a), 1)
        let hairline = 1 / deviceScale
        let dash: [CGFloat] = [3, 2]
        let lensClip = magnifierPath(kind: kind, in: lens)

        // Portion inside (or on) the lens → very thin dashed contrast chrome.
        ctx.saveGraphicsState()
        lensClip.addClip()
        dashColor.setStroke()
        strokeMagnifierFrame(
            kind: kind,
            rect: source,
            lineWidth: hairline,
            dash: dash
        )
        ctx.restoreGraphicsState()

        // Portion outside the lens → thick solid palette stroke.
        ctx.saveGraphicsState()
        let pad = max(style.strokeWidth, 4) * 2 + 8
        let exteriorBounds = source.union(lens).insetBy(dx: -pad, dy: -pad)
        let exteriorClip = NSBezierPath(rect: exteriorBounds)
        exteriorClip.append(lensClip)
        exteriorClip.windingRule = .evenOdd
        exteriorClip.addClip()
        solidColor.setStroke()
        strokeMagnifierFrame(
            kind: kind,
            rect: source,
            lineWidth: style.strokeWidth,
            dash: []
        )
        ctx.restoreGraphicsState()
    }

    static func strokeMagnifierFrame(
        kind: ShapeKind,
        rect: CGRect,
        lineWidth: CGFloat,
        dash: [CGFloat]
    ) {
        let inset = lineWidth / 2
        let path = magnifierPath(kind: kind, in: rect.insetBy(dx: inset, dy: inset))
        path.lineWidth = lineWidth
        path.lineJoinStyle = .miter
        path.lineCapStyle = .butt
        if dash.isEmpty {
            path.setLineDash(nil, count: 0, phase: 0)
        } else {
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        path.stroke()
    }

    static func drawMagnifiedContent(
        kind: ShapeKind,
        sourceLocal: CGRect,
        lensDraw: CGRect,
        sample: MosaicSampleContext,
        drawOrigin: CGPoint
    ) {
        let imageBounds = CGRect(origin: .zero, size: sample.image.size)
        let sampleSource = sourceLocal.offsetBy(
            dx: sample.selectionOriginInImage.x,
            dy: sample.selectionOriginInImage.y
        )
        let crop = sampleSource.intersection(imageBounds)
        guard crop.width >= 1, crop.height >= 1 else { return }

        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }

        magnifierPath(kind: kind, in: lensDraw).addClip()

        // Map the full source rect into the lens (even if crop clipped the image edges).
        let srcDraw = sourceLocal.offsetBy(dx: drawOrigin.x, dy: drawOrigin.y)
        let sx = lensDraw.width / max(srcDraw.width, 0.01)
        let sy = lensDraw.height / max(srcDraw.height, 0.01)
        let cropInSource = CGRect(
            x: crop.minX - sample.selectionOriginInImage.x,
            y: crop.minY - sample.selectionOriginInImage.y,
            width: crop.width,
            height: crop.height
        )
        let dest = CGRect(
            x: lensDraw.minX + (cropInSource.minX - sourceLocal.minX) * sx,
            y: lensDraw.minY + (cropInSource.minY - sourceLocal.minY) * sy,
            width: cropInSource.width * sx,
            height: cropInSource.height * sy
        )
        sample.image.draw(in: dest, from: crop, operation: .copy, fraction: 1)
    }

    /// Composite freeze crop + the marks already drawn over the source into a **source-sized**
    /// buffer, then scale it into the lens. Marks come from the canvas the lens is being drawn
    /// into, so this costs one crop readback rather than a re-draw of every prior mark.
    static func drawMagnifiedContentWithAnnotations(
        kind: ShapeKind,
        sourceLocal: CGRect,
        lensDraw: CGRect,
        sample: MosaicSampleContext,
        drawOrigin: CGPoint,
        canvas: MarksCanvas
    ) {
        let imageBounds = CGRect(origin: .zero, size: sample.image.size)
        let sampleSource = sourceLocal.offsetBy(
            dx: sample.selectionOriginInImage.x,
            dy: sample.selectionOriginInImage.y
        )
        let crop = sampleSource.intersection(imageBounds)
        guard crop.width >= 1, crop.height >= 1 else { return }

        let cropInContext = crop.offsetBy(
            dx: drawOrigin.x - sample.selectionOriginInImage.x,
            dy: drawOrigin.y - sample.selectionOriginInImage.y
        )
        let priorPixels = canvas.snapshotCrop(cropInContext)

        let composed = NSImage(size: crop.size, flipped: false) { _ in
            sample.image.draw(
                in: CGRect(origin: .zero, size: crop.size),
                from: crop,
                operation: .copy,
                fraction: 1
            )
            if let priorPixels, let cg = NSGraphicsContext.current?.cgContext {
                cg.draw(priorPixels, in: CGRect(origin: .zero, size: crop.size))
            }
            return true
        }

        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }

        magnifierPath(kind: kind, in: lensDraw).addClip()

        let srcDraw = sourceLocal.offsetBy(dx: drawOrigin.x, dy: drawOrigin.y)
        let sx = lensDraw.width / max(srcDraw.width, 0.01)
        let sy = lensDraw.height / max(srcDraw.height, 0.01)
        let cropInSource = CGRect(
            x: crop.minX - sample.selectionOriginInImage.x,
            y: crop.minY - sample.selectionOriginInImage.y,
            width: crop.width,
            height: crop.height
        )
        let dest = CGRect(
            x: lensDraw.minX + (cropInSource.minX - sourceLocal.minX) * sx,
            y: lensDraw.minY + (cropInSource.minY - sourceLocal.minY) * sy,
            width: cropInSource.width * sx,
            height: cropInSource.height * sy
        )
        composed.draw(in: dest, from: .zero, operation: .copy, fraction: 1)
    }

    static func magnifierPath(kind: ShapeKind, in rect: CGRect) -> NSBezierPath {
        switch kind {
        case .rectangle:
            return NSBezierPath(rect: rect)
        case .ellipse:
            return NSBezierPath(ovalIn: rect)
        }
    }

    /// Edge-to-edge connector only when source and lens are fully disjoint (no overlap / nesting).
    static func magnifierConnectorEndpoints(source: CGRect, lens: CGRect) -> (CGPoint, CGPoint)? {
        guard !source.intersects(lens) else { return nil }

        let sourceCenter = CGPoint(x: source.midX, y: source.midY)
        let lensCenter = CGPoint(x: lens.midX, y: lens.midY)
        let centerDist = hypot(lensCenter.x - sourceCenter.x, lensCenter.y - sourceCenter.y)
        guard centerDist > 1 else { return nil }

        let fromSource = boundaryPoint(of: source, toward: lensCenter) ?? sourceCenter
        let fromLens = boundaryPoint(of: lens, toward: sourceCenter) ?? lensCenter
        if hypot(fromLens.x - fromSource.x, fromLens.y - fromSource.y) < 2 {
            return nil
        }
        return (fromSource, fromLens)
    }

    static func boundaryPoint(of rect: CGRect, toward target: CGPoint) -> CGPoint? {
        let origin = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return nil }
        let hw = rect.width / 2
        let hh = rect.height / 2
        guard hw > 0, hh > 0 else { return nil }
        let tx = abs(dx) < 0.001 ? CGFloat.greatestFiniteMagnitude : hw / abs(dx)
        let ty = abs(dy) < 0.001 ? CGFloat.greatestFiniteMagnitude : hh / abs(dy)
        let t = min(tx, ty)
        return CGPoint(x: origin.x + dx * t, y: origin.y + dy * t)
    }

}
