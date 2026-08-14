import AppKit
import CoreImage

// Mosaic blur draw.

extension AnnotationDrawing {
    static func drawMosaic(
        geometry: MosaicGeometry,
        style: MosaicStyle,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext?,
        priorMarks: [Annotation] = []
    ) {
        let radius = MosaicStyle.blurRadiusPoints(forIntensity: style.intensity)

        switch geometry {
        case .stroke(let localPoints):
            guard !localPoints.isEmpty else { return }
            let brush = max(style.brushWidth, 1)
            guard let sample else {
                let offset = localPoints.map { CGPoint(x: $0.x + drawOrigin.x, y: $0.y + drawOrigin.y) }
                drawMosaicFallbackStroke(points: offset, brushWidth: brush)
                return
            }
            let pad = brush / 2 + radius * 2
            let hull = Annotation.bounds(of: localPoints).insetBy(dx: -pad, dy: -pad)
            drawBlurredMask(
                localMask: mosaicStrokeMask(localPoints: localPoints, brushWidth: brush),
                localHull: hull,
                radius: radius,
                drawOrigin: drawOrigin,
                sample: sample,
                priorMarks: priorMarks
            ) {
                let offset = localPoints.map { CGPoint(x: $0.x + drawOrigin.x, y: $0.y + drawOrigin.y) }
                drawMosaicFallbackStroke(points: offset, brushWidth: brush)
            }

        case .region(let mode, let localRect):
            guard localRect.width >= 1, localRect.height >= 1 else { return }
            guard let sample else {
                drawMosaicFallbackRegion(rect: localRect.offsetBy(dx: drawOrigin.x, dy: drawOrigin.y), mode: mode)
                return
            }
            let pad = radius * 2
            let hull = localRect.insetBy(dx: -pad, dy: -pad)
            let mask: NSBezierPath
            switch mode {
            case .ellipse:
                mask = NSBezierPath(ovalIn: localRect)
            case .rectangle, .freehand:
                mask = NSBezierPath(rect: localRect)
            }
            drawBlurredMask(
                localMask: mask,
                localHull: hull,
                radius: radius,
                drawOrigin: drawOrigin,
                sample: sample,
                priorMarks: priorMarks
            ) {
                drawMosaicFallbackRegion(
                    rect: localRect.offsetBy(dx: drawOrigin.x, dy: drawOrigin.y),
                    mode: mode
                )
            }
        }
    }

    static func drawBlurredMask(
        localMask: NSBezierPath,
        localHull: CGRect,
        radius: CGFloat,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext,
        priorMarks: [Annotation] = [],
        fallback: () -> Void
    ) {
        guard localHull.width >= 1, localHull.height >= 1 else { return }
        let imageBounds = CGRect(origin: .zero, size: sample.image.size)
        let sampleHull = localHull.offsetBy(
            dx: sample.selectionOriginInImage.x,
            dy: sample.selectionOriginInImage.y
        )
        let crop = sampleHull.intersection(imageBounds)
        guard crop.width >= 1, crop.height >= 1 else { return }

        let contributing = priorMarksOverlappingHull(priorMarks, hull: localHull)
        let source: NSImage
        let sourceCrop: CGRect
        if contributing.isEmpty {
            source = sample.image
            sourceCrop = crop
        } else {
            source = compositeCropWithPriorMarks(
                sample: sample,
                crop: crop,
                priorMarks: contributing
            )
            sourceCrop = CGRect(origin: .zero, size: crop.size)
        }
        guard let blurred = blurredCrop(from: source, crop: sourceCrop, radius: radius) else {
            fallback()
            return
        }

        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }

        let mask = localMask.copy() as? NSBezierPath ?? localMask
        let transform = AffineTransform(translationByX: drawOrigin.x, byY: drawOrigin.y)
        mask.transform(using: transform)
        mask.addClip()

        let drawRect = crop.offsetBy(
            dx: drawOrigin.x - sample.selectionOriginInImage.x,
            dy: drawOrigin.y - sample.selectionOriginInImage.y
        )
        blurred.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    static func drawMosaicFallbackStroke(points: [CGPoint], brushWidth: CGFloat) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        if points.count == 1 {
            let r = brushWidth / 2
            path.appendOval(in: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2))
            NSColor.black.withAlphaComponent(0.18).setFill()
            path.fill()
            return
        }
        path.move(to: first)
        for p in points.dropFirst() { path.line(to: p) }
        path.lineWidth = brushWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        NSColor.black.withAlphaComponent(0.18).setStroke()
        path.stroke()
    }

    static func drawMosaicFallbackRegion(rect: CGRect, mode: MosaicDrawMode) {
        let path: NSBezierPath
        switch mode {
        case .ellipse:
            path = NSBezierPath(ovalIn: rect)
        case .rectangle, .freehand:
            path = NSBezierPath(rect: rect)
        }
        NSColor.black.withAlphaComponent(0.18).setFill()
        path.fill()
    }

    static func mosaicStrokeMask(localPoints: [CGPoint], brushWidth: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = localPoints.first else { return path }
        if localPoints.count == 1 {
            let r = brushWidth / 2
            path.appendOval(in: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2))
            return path
        }
        path.move(to: first)
        for p in localPoints.dropFirst() { path.line(to: p) }
        let stroked = path.cgPath.copy(
            strokingWithWidth: brushWidth,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        )
        return NSBezierPath(cgPath: stroked)
    }

    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Extra pad so stroke width / badges just outside the blur hull still contribute.
    private static let mosaicPriorCullPad: CGFloat = 40

    static func priorMarksOverlappingHull(_ prior: [Annotation], hull: CGRect) -> [Annotation] {
        let cull = hull.insetBy(dx: -mosaicPriorCullPad, dy: -mosaicPriorCullPad)
        return prior.filter { $0.boundingRect.intersects(cull) }
    }

    /// Freeze crop + prior marks (`drawMarksSimple`, not a nested `renderMarksLayer`).
    /// Nested mosaics stay freeze-only to avoid recursive rebuilds. Marks go in a transparency
    /// layer so eraser `destinationOut` punches annotations only.
    static func compositeCropWithPriorMarks(
        sample: MosaicSampleContext,
        crop: CGRect,
        priorMarks: [Annotation]
    ) -> NSImage {
        NSImage(size: crop.size, flipped: false) { _ in
            sample.image.draw(
                in: CGRect(origin: .zero, size: crop.size),
                from: crop,
                operation: .copy,
                fraction: 1
            )
            let markOrigin = CGPoint(
                x: sample.selectionOriginInImage.x - crop.minX,
                y: sample.selectionOriginInImage.y - crop.minY
            )
            if let cg = NSGraphicsContext.current?.cgContext {
                cg.beginTransparencyLayer(auxiliaryInfo: nil)
                drawMarksSimple(priorMarks, origin: markOrigin, sample: sample)
                cg.endTransparencyLayer()
            }
            return true
        }
    }

    /// Crop → `CIGaussianBlur` → image.
    static func blurredCrop(
        from image: NSImage,
        crop: CGRect,
        radius: CGFloat
    ) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let pixelScale = (scaleX + scaleY) / 2
        let pixelCrop = CGRect(
            x: crop.minX * scaleX,
            y: (image.size.height - crop.maxY) * scaleY,
            width: crop.width * scaleX,
            height: crop.height * scaleY
        ).integral
        guard pixelCrop.width >= 1, pixelCrop.height >= 1,
              let cropped = cgImage.cropping(to: pixelCrop)
        else { return nil }

        let ci = CIImage(cgImage: cropped)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
        filter?.setValue(max(radius * pixelScale, 0.35), forKey: kCIInputRadiusKey)
        let extent = ci.extent
        guard let blurred = filter?.outputImage?.cropped(to: extent),
              let outCG = ciContext.createCGImage(blurred, from: extent)
        else { return nil }

        return NSImage(cgImage: outCG, size: crop.size)
    }

}
