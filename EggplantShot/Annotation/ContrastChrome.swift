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
