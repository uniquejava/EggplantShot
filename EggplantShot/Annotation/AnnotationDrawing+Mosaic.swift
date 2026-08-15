import AppKit
import CoreImage

// Mosaic draw — gaussian blur smear or pixel-block mosaic, per `style.effect`.

extension AnnotationDrawing {
    static func drawMosaic(
        geometry: MosaicGeometry,
        style: MosaicStyle,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext?,
        canvas: MarksCanvas? = nil
    ) {
        let bleed = mosaicBleedPoints(for: style)

        switch geometry {
        case .stroke(let localPoints):
            guard !localPoints.isEmpty else { return }
            let brush = max(style.brushWidth, 1)
            guard let sample else {
                let offset = localPoints.map { CGPoint(x: $0.x + drawOrigin.x, y: $0.y + drawOrigin.y) }
                drawMosaicFallbackStroke(points: offset, brushWidth: brush)
                return
            }
            let pad = brush / 2 + bleed
            let hull = Annotation.bounds(of: localPoints).insetBy(dx: -pad, dy: -pad)
            drawSampledMask(
                localMask: mosaicStrokeMask(localPoints: localPoints, brushWidth: brush),
                localHull: hull,
                style: style,
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
            let hull = localRect.insetBy(dx: -bleed, dy: -bleed)
            let mask: NSBezierPath
            switch mode {
            case .ellipse:
                mask = NSBezierPath(ovalIn: localRect)
            case .rectangle, .freehand:
                mask = NSBezierPath(rect: localRect)
            }
            drawSampledMask(
                localMask: mask,
                localHull: hull,
                style: style,
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

    /// Hull padding beyond the mask, so the effect has source pixels to reach for: a gaussian
    /// needs ±2σ, a block lattice needs one whole block.
    static func mosaicBleedPoints(for style: MosaicStyle) -> CGFloat {
        switch style.effect {
        case .blur:
            return MosaicStyle.blurRadiusPoints(forIntensity: style.intensity) * 2
        case .pixelate:
            // One whole block, so the outermost lattice cell is complete rather than averaging
            // against missing neighbours.
            return MosaicStyle.blockSizePoints(forIntensity: style.intensity)
        }
    }

    static func drawSampledMask(
        localMask: NSBezierPath,
        localHull: CGRect,
        style: MosaicStyle,
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
        // Marks already drawn under this hull — including any earlier mosaic's output.
        let priorPixels = canvas?.snapshotCrop(drawRect)
        guard let processed = processedCrop(
            from: sample.image,
            crop: crop,
            style: style,
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

        processed.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
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

    /// Crop → optional composite with the marks already under it → `style.effect`'s filter.
    static func processedCrop(
        from image: NSImage,
        crop: CGRect,
        style: MosaicStyle,
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

        // Process what is actually visible here: freeze under the marks drawn over it.
        let source = overlay.flatMap { compositeUnder(cropped, overlay: $0) } ?? cropped

        let ci = CIImage(cgImage: source)
        let extent = ci.extent
        let output: CIImage?
        switch style.effect {
        case .blur:
            let radius = MosaicStyle.blurRadiusPoints(forIntensity: style.intensity)
            let filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
            filter?.setValue(max(radius * pixelScale, 0.35), forKey: kCIInputRadiusKey)
            output = filter?.outputImage
        case .pixelate:
            // Whole device pixels, so block edges stay crisp instead of landing mid-pixel.
            let block = max(
                (MosaicStyle.blockSizePoints(forIntensity: style.intensity) * pixelScale).rounded(),
                2
            )
            let pixellate = CIFilter(name: "CIPixellate")
            pixellate?.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
            pixellate?.setValue(block, forKey: kCIInputScaleKey)
            pixellate?.setValue(
                CIVector(cgPoint: pixelateGridAnchor(
                    pixelCrop: pixelCrop,
                    imagePixelHeight: cgImage.height,
                    block: block
                )),
                forKey: kCIInputCenterKey
            )
            output = pixellate?.outputImage
        }
        guard let processed = output?.cropped(to: extent),
              let outCG = ciContext.createCGImage(processed, from: extent)
        else { return nil }

        return NSImage(cgImage: outCG, size: crop.size)
    }

    /// Crop-local point that pins the block lattice to one image-wide grid.
    ///
    /// `CIPixellate` builds its lattice around `inputCenter`, which is relative to the image it is
    /// handed — here a crop whose origin moves with every stroke. Left at a constant, each mark
    /// would quantise to its own offset grid, so two overlapping pixelate strokes (the second one
    /// re-reading the first's pixels out of the marks layer) would seam where the two lattices
    /// disagree instead of resolving to the same squares.
    ///
    /// Cancelling the crop's absolute origin, mod one block, makes the lattice phase a function of
    /// absolute image position alone. Which *part* of a cell `inputCenter` names doesn't matter —
    /// only that every crop derives the same phase. Verified by rendering the same absolute pixels
    /// through two crops offset by a non-multiple of the block and diffing them.
    static func pixelateGridAnchor(
        pixelCrop: CGRect,
        imagePixelHeight: Int,
        block: CGFloat
    ) -> CGPoint {
        // `pixelCrop` is top-down; the cropped image `CIImage` sees starts at its bottom-left.
        let originX = pixelCrop.minX
        let originY = CGFloat(imagePixelHeight) - pixelCrop.maxY
        return CGPoint(
            x: nonNegativeRemainder(-originX, block),
            y: nonNegativeRemainder(-originY, block)
        )
    }

    private static func nonNegativeRemainder(_ value: CGFloat, _ modulus: CGFloat) -> CGFloat {
        guard modulus > 0 else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder < 0 ? remainder + modulus : remainder
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
