import AppKit
import CoreImage

// Marker (highlighter) draw.

extension AnnotationDrawing {
    static func drawMarker(
        geometry: MosaicGeometry,
        style: MarkerStyle,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext? = nil,
        canvas: MarksCanvas? = nil
    ) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }

        let fill = style.fillColor

        // Marks paint on a transparent offscreen layer (eraser needs destinationOut).
        // Multiply against clear reads as opaque when composited — so for multiply colors,
        // build the mark's mask, multiply the backdrop by the paint in an opaque offscreen, then
        // composite that result through the mask (same shape as mosaic's `drawSampledMask`).
        if style.usesMultiplyBlend, let sample {
            let mask: NSBezierPath
            switch geometry {
            case .stroke(let localPoints):
                guard !localPoints.isEmpty else { return }
                mask = strokeOutlineMask(
                    localPoints: localPoints,
                    brushWidth: max(style.brushWidth, 1)
                )
            case .region(let mode, let localRect):
                guard localRect.width >= 1, localRect.height >= 1 else { return }
                mask = regionMask(mode: mode, localRect: localRect)
            }
            drawMultiplyMark(
                localMask: mask,
                fill: fill,
                drawOrigin: drawOrigin,
                sample: sample,
                canvas: canvas,
                context: ctx
            )
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
            fill.setFill()
            regionMask(mode: mode, localRect: rect).fill()
        }
    }

    static func regionMask(mode: MosaicDrawMode, localRect: CGRect) -> NSBezierPath {
        switch mode {
        case .ellipse:
            return NSBezierPath(ovalIn: localRect)
        case .rectangle, .freehand:
            return NSBezierPath(rect: localRect)
        }
    }

    /// Composite `backdrop × fill` through `localMask`, antialiasing the edge exactly once.
    ///
    /// The mark's soft edge has to come from this one masked `sourceOver`. Clipping first and
    /// multiplying into the layer instead puts partial alpha in the destination, and CoreGraphics'
    /// premultiplied multiply then adds a `src × (1 - dst_alpha)` term — undiluted paint fringing
    /// every antialiased edge. A freehand stroke is almost entirely edge, so it glowed; a
    /// pixel-aligned rectangle had the same flaw with no edge pixels to reveal it.
    ///
    /// `canvas` is the layer being drawn into. Reading the marks already under the hull back out of
    /// it and multiplying those too is what keeps a highlight from covering earlier annotations —
    /// the result drawn here is opaque, so without it the mark would occlude them.
    static func drawMultiplyMark(
        localMask: NSBezierPath,
        fill: NSColor,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext,
        canvas: MarksCanvas?,
        context: NSGraphicsContext
    ) {
        let localHull = localMask.bounds
        guard localHull.width >= 1, localHull.height >= 1 else { return }

        let sampleHull = localHull.offsetBy(
            dx: sample.selectionOriginInImage.x,
            dy: sample.selectionOriginInImage.y
        )
        let crop = sampleHull.intersection(CGRect(origin: .zero, size: sample.image.size))
        guard crop.width >= 1, crop.height >= 1 else { return }
        guard let aligned = alignedCrop(from: sample.image, crop: crop) else { return }

        let drawRect = aligned.pointRect.offsetBy(
            dx: drawOrigin.x - sample.selectionOriginInImage.x,
            dy: drawOrigin.y - sample.selectionOriginInImage.y
        )
        // Marks already drawn under this hull — including an earlier highlight's output.
        let priorPixels = canvas?.snapshotCrop(drawRect)
        guard let result = multipliedBackdrop(
            aligned: aligned,
            color: fill,
            overlay: priorPixels
        ) else { return }

        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        let mask = localMask.copy() as? NSBezierPath ?? localMask
        mask.transform(using: AffineTransform(translationByX: drawOrigin.x, byY: drawOrigin.y))
        mask.addClip()
        result.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    struct AlignedCrop {
        let cgImage: CGImage
        let pixelCrop: CGRect
        /// Point rect the aligned pixels actually cover — not the requested crop.
        let pointRect: CGRect
    }

    /// Whole-pixel crop covering `crop`, so the result lands 1:1 on the destination instead of
    /// being resampled a fraction of a pixel — which would ghost the backdrop's own text
    /// antialiasing against the real thing beneath it.
    static func alignedCrop(from image: NSImage, crop: CGRect) -> AlignedCrop? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        guard scaleX > 0, scaleY > 0 else { return nil }
        let pixelCrop = CGRect(
            x: crop.minX * scaleX,
            y: (image.size.height - crop.maxY) * scaleY,
            width: crop.width * scaleX,
            height: crop.height * scaleY
        ).integral
        guard pixelCrop.width >= 1, pixelCrop.height >= 1 else { return nil }
        let pointRect = CGRect(
            x: pixelCrop.minX / scaleX,
            y: image.size.height - pixelCrop.maxY / scaleY,
            width: pixelCrop.width / scaleX,
            height: pixelCrop.height / scaleY
        )
        return AlignedCrop(cgImage: cgImage, pixelCrop: pixelCrop, pointRect: pointRect)
    }

    /// Backdrop (with `overlay`'s marks composited under it) multiplied by `color`, opaque.
    ///
    /// Opaque is the point: every pixel here has alpha 1, so multiply is exact and cannot fringe.
    static func multipliedBackdrop(
        aligned: AlignedCrop,
        color: NSColor,
        overlay: CGImage?
    ) -> NSImage? {
        guard let cropped = aligned.cgImage.cropping(to: aligned.pixelCrop) else { return nil }
        // Multiply what is actually visible here: freeze with the marks drawn over it.
        let base = overlay.flatMap { compositeUnder(cropped, overlay: $0) } ?? cropped

        // `noneSkipFirst` — an alpha-less destination, so `dst_alpha` is 1 by construction.
        guard let ctx = CGContext(
            data: nil,
            width: base.width,
            height: base.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: aligned.cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        ctx.draw(base, in: full)
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(color.cgColor)
        ctx.fill(full)
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: aligned.pointRect.size)
    }
}
