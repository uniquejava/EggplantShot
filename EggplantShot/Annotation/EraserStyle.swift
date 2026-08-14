import AppKit

// Eraser brush style (marks only).

struct EraserStyle: Equatable {
    var brushWidth: CGFloat

    static let brushPresets: [CGFloat] = MosaicStyle.brushPresets
    static let brushPreviewDiameters: [CGFloat] = MosaicStyle.brushPreviewDiameters

    static let `default` = EraserStyle(brushWidth: brushPresets[0])

    mutating func clamp() {
        brushWidth = Self.nearestBrushPreset(brushWidth)
    }

    static func nearestBrushPreset(_ width: CGFloat) -> CGFloat {
        brushPresets.min(by: { abs($0 - width) < abs($1 - width) }) ?? brushPresets[0]
    }
}

/// Arrowhead / end-cap styles (Snipaste start / end dropdown).
/// Raw values are stable for disk prefs; `menuCases` order matches the menu.
