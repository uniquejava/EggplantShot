import AppKit

// Highlighter (marker) style.

struct MarkerStyle: Equatable {
    var brushWidth: CGFloat
    var color: NSColor

    /// Same brush diameters as mosaic (toolbar · / ·· / ···).
    static let brushPresets: [CGFloat] = MosaicStyle.brushPresets
    static let brushPreviewDiameters: [CGFloat] = MosaicStyle.brushPreviewDiameters
    /// Highlighter wash. Marks render on a transparent offscreen layer (so eraser can
    /// `destinationOut`); multiply against clear reads as opaque when composited, so
    /// always use sourceOver + alpha instead.
    static let highlightAlpha: CGFloat = 0.4

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

    /// Translucent paint color (sourceOver highlighter wash).
    var fillColor: NSColor {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        return NSColor(
            calibratedRed: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            alpha: Self.highlightAlpha
        )
    }
}
