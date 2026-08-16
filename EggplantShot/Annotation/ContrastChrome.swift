import AppKit

/// Shared luminance / contrast helpers for edit chrome (hairlines, text plate, halos).
enum ContrastChrome {
    static let threshold: CGFloat = 0.55
    /// Overlay dim outside the blue selection (~45% black).
    static let outsideSelectionFactor: CGFloat = 0.55

    static func luminance(of color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }

    static func isLight(_ color: NSColor) -> Bool {
        luminance(of: color) > threshold
    }

    /// Opaque black / white stroke for hairlines on a backdrop of the given luminance.
    static func hairline(onLuminance luminance: CGFloat) -> NSColor {
        luminance < threshold ? .white : .black
    }

    static func hairline(against color: NSColor) -> NSColor {
        hairline(onLuminance: luminance(of: color))
    }

    /// Dim freeze luminance when `point` sits outside the selection punch-through.
    static func adjustedLuminance(_ luminance: CGFloat, point: CGPoint, selectionRect: CGRect) -> CGFloat {
        guard !selectionRect.isNull, !selectionRect.contains(point) else { return luminance }
        return luminance * outsideSelectionFactor
    }

    /// Text edit / hover chrome: against the text plate when filled, else freeze luminance.
    static func textHairline(style: TextStyle, freezeLuminance: CGFloat) -> NSColor {
        if style.hasBackground {
            return hairline(against: textPlate(behind: style.color))
        }
        return hairline(onLuminance: freezeLuminance)
    }

    /// Light plate behind dark ink; dark plate behind light ink.
    static func textPlate(behind ink: NSColor) -> NSColor {
        isLight(ink)
            ? NSColor.black.withAlphaComponent(0.55)
            : NSColor.white.withAlphaComponent(0.85)
    }

    /// Soft outline behind bright / dark ink (crosshair etc.).
    static func halo(for ink: NSColor) -> NSColor {
        isLight(ink)
            ? NSColor.black.withAlphaComponent(0.35)
            : NSColor.white.withAlphaComponent(0.45)
    }

    /// Companion ink for chrome that must stay visible on a *light* backdrop. Tunable: it is the only
    /// visible part of the chrome on white, so it wants enough weight to read at one device pixel,
    /// while staying quiet enough to disappear against dark content.
    static let chromeHaloInk = NSColor.black.withAlphaComponent(0.7)

    /// Stroke `rect` as chrome that must never disappear against arbitrary content: the light line
    /// itself, plus a dark companion immediately **inside** it.
    ///
    /// Preferred over picking one colour by luminance (`hairline(onLuminance:)`) for anything
    /// frame-shaped. Sampling needs a point, and a frame has no single backdrop — its edges cross
    /// arbitrary pixels, and the obvious sample (the box centre) is often the mark's own text or
    /// plate rather than what sits under the line. This needs no sample at all: on dark content the
    /// halo vanishes and it reads as the plain light line it replaces; on light content the light
    /// line vanishes and the halo reads as a dark hairline; in between you get a subtle double line.
    ///
    /// Inward so `rect` stays the chrome's outer bound — handles keep the size they are hit-tested
    /// at, and nothing overdraws into a parent that might clip.
    static func strokeHaloedRect(_ rect: CGRect, lineWidth w: CGFloat, color: NSColor = .white) {
        guard rect.width > 0, rect.height > 0, w > 0 else { return }
        // Bands abut exactly: the light line covers [edge, edge + w], the halo [edge + w, edge + 2w].
        if rect.width > w * 3, rect.height > w * 3 {
            chromeHaloInk.setStroke()
            let halo = NSBezierPath(rect: rect.insetBy(dx: w * 1.5, dy: w * 1.5))
            halo.lineWidth = w
            halo.stroke()
        }
        color.setStroke()
        let line = NSBezierPath(rect: rect.insetBy(dx: w / 2, dy: w / 2))
        line.lineWidth = w
        line.stroke()
    }

    static func averageLuminance(of rep: NSBitmapImageRep) -> CGFloat? {
        var sum: CGFloat = 0
        var count: CGFloat = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                sum += luminance(of: color)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return sum / count
    }

    /// Sample ~4×4 pt around `point` in Cocoa image space (bottom-left origin).
    static func averageLuminance(in image: NSImage, aroundPointInImageSpace point: CGPoint) -> CGFloat? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scaleX = CGFloat(cg.width) / image.size.width
        let scaleY = CGFloat(cg.height) / image.size.height
        let sample = CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
        let pixel = CGRect(
            x: sample.minX * scaleX,
            y: (image.size.height - sample.maxY) * scaleY,
            width: sample.width * scaleX,
            height: sample.height * scaleY
        ).integral
        guard pixel.width >= 1, pixel.height >= 1,
              let cropped = cg.cropping(to: pixel)
        else { return nil }
        return averageLuminance(of: NSBitmapImageRep(cgImage: cropped))
    }
}
