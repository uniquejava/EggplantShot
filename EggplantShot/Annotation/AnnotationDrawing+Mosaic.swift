import AppKit
import CoreImage

// Mosaic blur draw.

extension AnnotationDrawing {
    static func drawMosaic(
        geometry: MosaicGeometry,
        style: MosaicStyle,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext?,
        canvas: MarksCanvas? = nil
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
                canvas: canvas
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
                canvas: canvas
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
        canvas: MarksCanvas? = nil,
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

        let drawRect = crop.offsetBy(
            dx: drawOrigin.x - sample.selectionOriginInImage.x,
            dy: drawOrigin.y - sample.selectionOriginInImage.y
        )
        // Marks already drawn under this hull — including any earlier mosaic's blurred pixels.
        let priorPixels = canvas?.snapshotCrop(drawRect)
        guard let blurred = blurredCrop(
            from: sample.image,
            crop: crop,
            radius: radius,
            overlay: priorPixels
        ) else {
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

    /// Crop → optional composite with the marks already under it → `CIGaussianBlur`.
    static func blurredCrop(
        from image: NSImage,
        crop: CGRect,
        radius: CGFloat,
        overlay: CGImage? = nil
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

        // Blur what is actually visible here: freeze under the marks drawn over it.
        let source = overlay.flatMap { compositeUnder(cropped, overlay: $0) } ?? cropped

        let ci = CIImage(cgImage: source)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
        filter?.setValue(max(radius * pixelScale, 0.35), forKey: kCIInputRadiusKey)
        let extent = ci.extent
        guard let blurred = filter?.outputImage?.cropped(to: extent),
              let outCG = ciContext.createCGImage(blurred, from: extent)
        else { return nil }

        return NSImage(cgImage: outCG, size: crop.size)
    }

    /// `overlay` (marks, with alpha) over `base` (opaque freeze) at `base`'s pixel size.
    private static func compositeUnder(_ base: CGImage, overlay: CGImage) -> CGImage? {
        let w = base.width
        let h = base.height
        guard w > 0, h > 0 else { return nil }
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            // Stay in the freeze's own space so the blur input is not colour-shifted.
            space: base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(base, in: rect)
        ctx.draw(overlay, in: rect)
        return ctx.makeImage()
    }

}
