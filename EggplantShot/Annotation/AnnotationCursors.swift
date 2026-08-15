import AppKit

// Annotate hit-zone cursors.

enum AnnotationCursors {
    /// System four-arrow “move” cursor (thin; hotspot at center so it doesn’t cover the target).
    /// Loaded from HIServices — do not call private `NSCursor._moveCursor` (aborts on macOS 15+).
    static let move: NSCursor = hiServicesMoveCursor() ?? drawnMoveCursor()

    /// White “＋” used for selecting / shape-draw (custom-drawn, not system crosshair).
    static let whitePlus: NSCursor = {
        let size: CGFloat = 24
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let mid = NSPoint(x: rect.midX, y: rect.midY)
            let arm: CGFloat = 8
            let line = NSBezierPath()
            line.move(to: NSPoint(x: mid.x - arm, y: mid.y))
            line.line(to: NSPoint(x: mid.x + arm, y: mid.y))
            line.move(to: NSPoint(x: mid.x, y: mid.y - arm))
            line.line(to: NSPoint(x: mid.x, y: mid.y + arm))
            line.lineCapStyle = .round

            // Dark halo so it stays visible on light screenshots.
            line.lineWidth = 4
            NSColor.black.withAlphaComponent(0.55).setStroke()
            line.stroke()

            line.lineWidth = 2
            NSColor.white.setStroke()
            line.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }()

    /// Near-invisible cursor while pencil is stroking (Snipaste: reticle vanishes; only the ink shows).
    /// A fully transparent image often becomes a black blob under AppKit — keep a tiny alpha.
    static let hidden: NSCursor = {
        let image = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
            NSColor.white.withAlphaComponent(0.01).setFill()
            rect.fill()
            return true
        }
        return NSCursor(image: image, hotSpot: .zero)
    }()

    static var pencilCrosshairCache: (key: UInt64, cursor: NSCursor)?
    static var mosaicCrosshairCache: (key: Int, cursor: NSCursor)?
    static var eraserRingCache: (key: Int, cursor: NSCursor)?
    static var stepBadgeCache: (key: String, cursor: NSCursor)?

    /// Brush outline matching actual diameter (no artificial cap that hid size changes).
    static func mosaicCrosshair(brushWidth: CGFloat) -> NSCursor {
        let diameter = max(brushWidth, 8)
        let key = Int((diameter * 2).rounded()) // half-point precision
        if let cache = mosaicCrosshairCache, cache.key == key {
            return cache.cursor
        }
        let pad: CGFloat = 3
        let size = diameter + pad * 2
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let r = rect.insetBy(dx: pad + 0.5, dy: pad + 0.5)
            let path = NSBezierPath(ovalIn: r)
            // Soft dark ring + translucent white fill (Snipaste-like brush tip).
            NSColor.white.withAlphaComponent(0.45).setFill()
            path.fill()
            path.lineWidth = 1
            NSColor(calibratedWhite: 0.18, alpha: 0.88).setStroke()
            path.stroke()
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
        mosaicCrosshairCache = (key, cursor)
        return cursor
    }

    /// Eraser tip: concentric hairline rings at the actual diameter, **no fill** — the point of
    /// erasing is seeing the marks about to be punched out, and mosaic's translucent disc reads
    /// as laying ink down. Dark ring outside / light ring inside means one of the two always
    /// separates from the backdrop, so the tip stays legible on light and dark screenshots.
    static func eraserRing(brushWidth: CGFloat) -> NSCursor {
        let diameter = max(brushWidth, 8)
        let key = Int((diameter * 2).rounded()) // half-point precision
        if let cache = eraserRingCache, cache.key == key {
            return cache.cursor
        }
        let pad: CGFloat = 3
        let size = diameter + pad * 2
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // Outer path spans exactly `diameter` once the 1pt stroke is centred on it;
            // the inner ring sits flush against it (no gap) for a single 2pt contrast band.
            let outer = rect.insetBy(dx: pad + 0.5, dy: pad + 0.5)
            let outerRing = NSBezierPath(ovalIn: outer)
            outerRing.lineWidth = 1
            NSColor(calibratedWhite: 0.18, alpha: 0.88).setStroke()
            outerRing.stroke()

            let innerRing = NSBezierPath(ovalIn: outer.insetBy(dx: 1, dy: 1))
            innerRing.lineWidth = 1
            NSColor.white.withAlphaComponent(0.9).setStroke()
            innerRing.stroke()
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
        eraserRingCache = (key, cursor)
        return cursor
    }

    /// Live step badge under the pointer (next number + current style) — click to stamp.
    static func stepBadge(number: Int, style: StepStyle) -> NSCursor {
        var style = style
        style.clamp()
        let number = max(number, 1)
        let rgb = style.color.usingColorSpace(.genericRGB) ?? style.color
        let key = String(
            format: "%d-%d-%.1f-%.3f-%.3f-%.3f-%.2f",
            number,
            style.kind.rawValue,
            style.size,
            rgb.redComponent,
            rgb.greenComponent,
            rgb.blueComponent,
            rgb.alphaComponent
        )
        if let cache = stepBadgeCache, cache.key == key {
            return cache.cursor
        }
        let d = style.diameter
        let pad: CGFloat = 2
        let size = ceil(d + pad * 2)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            AnnotationDrawing.draw(
                Annotation(
                    number: number,
                    center: CGPoint(x: size / 2, y: size / 2),
                    stepStyle: style
                ),
                origin: .zero
            )
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
        stepBadgeCache = (key, cursor)
        return cursor
    }

    /// Snipaste-style pencil reticle: center dot + four short thin arms, tinted to stroke color.
    static func pencilCrosshair(color: NSColor) -> NSCursor {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        let key =
            (UInt64((rgb.redComponent * 255).rounded()) << 24)
            | (UInt64((rgb.greenComponent * 255).rounded()) << 16)
            | (UInt64((rgb.blueComponent * 255).rounded()) << 8)
            | UInt64((rgb.alphaComponent * 255).rounded())
        if let cache = pencilCrosshairCache, cache.key == key {
            return cache.cursor
        }
        let cursor = makePencilCrosshair(color: rgb)
        pencilCrosshairCache = (key, cursor)
        return cursor
    }

    static func makePencilCrosshair(color: NSColor) -> NSCursor {
        let size: CGFloat = 23
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let mid = NSPoint(x: rect.midX, y: rect.midY)
            // Gap from center to each arm; arm length — keep hairline thin.
            let gap: CGFloat = 3
            let arm: CGFloat = 5
            let ink = color

            let arms = NSBezierPath()
            arms.move(to: NSPoint(x: mid.x - gap - arm, y: mid.y))
            arms.line(to: NSPoint(x: mid.x - gap, y: mid.y))
            arms.move(to: NSPoint(x: mid.x + gap, y: mid.y))
            arms.line(to: NSPoint(x: mid.x + gap + arm, y: mid.y))
            arms.move(to: NSPoint(x: mid.x, y: mid.y - gap - arm))
            arms.line(to: NSPoint(x: mid.x, y: mid.y - gap))
            arms.move(to: NSPoint(x: mid.x, y: mid.y + gap))
            arms.line(to: NSPoint(x: mid.x, y: mid.y + gap + arm))
            arms.lineCapStyle = .butt
            arms.lineWidth = 1

            // Hairline halo so cyan-on-cyan (etc.) still reads.
            arms.lineWidth = 2
            ContrastChrome.halo(for: ink).setStroke()
            arms.stroke()
            arms.lineWidth = 1
            ink.setStroke()
            arms.stroke()

            let dotR: CGFloat = 1.1
            let dot = NSBezierPath(ovalIn: CGRect(
                x: mid.x - dotR,
                y: mid.y - dotR,
                width: dotR * 2,
                height: dotR * 2
            ))
            ContrastChrome.halo(for: ink).setFill()
            NSBezierPath(ovalIn: CGRect(
                x: mid.x - dotR - 0.6,
                y: mid.y - dotR - 0.6,
                width: (dotR + 0.6) * 2,
                height: (dotR + 0.6) * 2
            )).fill()
            ink.setFill()
            dot.fill()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }

    static func hiServicesMoveCursor() -> NSCursor? {
        let dir = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors/move"
        let info = NSDictionary(contentsOfFile: "\(dir)/info.plist")
        let hotx = (info?["hotx"] as? NSNumber)?.doubleValue ?? 9
        let hoty = (info?["hoty"] as? NSNumber)?.doubleValue ?? 9
        // Prefer PDF (vector); PNG is the 1x bitmap fallback Apple ships alongside it.
        let image =
            NSImage(contentsOfFile: "\(dir)/cursor.pdf")
            ?? NSImage(contentsOfFile: "\(dir)/cursor_1only_.png")
        guard let image else { return nil }
        // PDF page is 18×18pt with hotspot (9,9); keep natural size so hotspot stays centered.
        if abs(image.size.width - 18) > 0.5 || abs(image.size.height - 18) > 0.5 {
            image.size = NSSize(width: 18, height: 18)
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: hotx, y: hoty))
    }

    /// Drawn four-arrow fallback if HIServices assets are unavailable.
    static func drawnMoveCursor() -> NSCursor {
        let size: CGFloat = 20
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let mid = NSPoint(x: rect.midX, y: rect.midY)
            let arm: CGFloat = 7
            let head: CGFloat = 3

            let path = NSBezierPath()
            // Cross
            path.move(to: NSPoint(x: mid.x - arm, y: mid.y))
            path.line(to: NSPoint(x: mid.x + arm, y: mid.y))
            path.move(to: NSPoint(x: mid.x, y: mid.y - arm))
            path.line(to: NSPoint(x: mid.x, y: mid.y + arm))
            // Arrow heads
            path.move(to: NSPoint(x: mid.x - arm + head, y: mid.y - head))
            path.line(to: NSPoint(x: mid.x - arm, y: mid.y))
            path.line(to: NSPoint(x: mid.x - arm + head, y: mid.y + head))
            path.move(to: NSPoint(x: mid.x + arm - head, y: mid.y - head))
            path.line(to: NSPoint(x: mid.x + arm, y: mid.y))
            path.line(to: NSPoint(x: mid.x + arm - head, y: mid.y + head))
            path.move(to: NSPoint(x: mid.x - head, y: mid.y - arm + head))
            path.line(to: NSPoint(x: mid.x, y: mid.y - arm))
            path.line(to: NSPoint(x: mid.x + head, y: mid.y - arm + head))
            path.move(to: NSPoint(x: mid.x - head, y: mid.y + arm - head))
            path.line(to: NSPoint(x: mid.x, y: mid.y + arm))
            path.line(to: NSPoint(x: mid.x + head, y: mid.y + arm - head))
            path.lineCapStyle = .round
            path.lineJoinStyle = .miter

            path.lineWidth = 3
            NSColor.black.withAlphaComponent(0.55).setStroke()
            path.stroke()
            path.lineWidth = 1.5
            NSColor.white.setStroke()
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }
}
