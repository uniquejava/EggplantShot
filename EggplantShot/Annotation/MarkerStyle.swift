import AppKit

// Highlighter (marker) style.

struct MarkerStyle: Equatable {
    var brushWidth: CGFloat
    var color: NSColor

    /// Same brush diameters as mosaic (toolbar · / ·· / ···).
    static let brushPresets: [CGFloat] = MosaicStyle.brushPresets
    static let brushPreviewDiameters: [CGFloat] = MosaicStyle.brushPreviewDiameters
    /// Only used for near-white swatches (multiply is a no-op on white).
    static let whiteWashAlpha: CGFloat = 0.35

    static let `default` = MarkerStyle(
        brushWidth: 18,
        color: PaletteColor.yellow.color
    )

    mutating func clamp() {
        brushWidth = Self.nearestBrushPreset(brushWidth)
    }

    static func nearestBrushPreset(_ width: CGFloat) -> CGFloat {
        brushPresets.min(by: { abs($0 - width) < abs($1 - width) }) ?? 18
    }

    /// Relative luminance in generic RGB (0…1).
    private var luminance: CGFloat {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }

    /// Near-white palette chips cannot use multiply (result ≈ unchanged).
    var usesMultiplyBlend: Bool { luminance <= 0.92 }

    /// Paint color for the current blend path (opaque for multiply; washed for white sourceOver).
    var fillColor: NSColor {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        if usesMultiplyBlend {
            return NSColor(
                calibratedRed: rgb.redComponent,
                green: rgb.greenComponent,
                blue: rgb.blueComponent,
                alpha: 1
            )
        }
        return NSColor(
            calibratedRed: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            alpha: Self.whiteWashAlpha
        )
    }
}
