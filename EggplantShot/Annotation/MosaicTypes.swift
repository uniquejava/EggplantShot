import AppKit

// Shared mosaic / marker / eraser draw modes and mosaic style.

enum MosaicDrawMode: Int, CaseIterable {
    case freehand = 0
    case rectangle = 1
    case ellipse = 2
}

/// Geometry for a mosaic mark (stroke polyline or region rect/oval).
enum MosaicGeometry: Equatable {
    case stroke(points: [CGPoint])
    case region(MosaicDrawMode, rect: CGRect) // `.rectangle` / `.ellipse` only
}

/// Mosaic stroke style (brush size for freehand + blur intensity). Stored on the mark; prefs mirror last-used.
struct MosaicStyle: Equatable {
    var brushWidth: CGFloat
    /// `CIGaussianBlur` radius (Snipaste intensity); clamped to `intensityRange`.
    var intensity: CGFloat

    static let intensityRange: ClosedRange<CGFloat> = 3...24
    /// Brush diameters in points (≈ cover 14 / 18 / 24 pt glyphs — not Snipaste’s @2x 28/34/42 labels).
    static let brushPresets: [CGFloat] = [14, 18, 24]
    /// Toolbar dot diameters (visual only; distinct sizes, not numbers).
    static let brushPreviewDiameters: [CGFloat] = [4, 6.5, 9]

    static let `default` = MosaicStyle(
        brushWidth: 18,
        intensity: 10
    )

    mutating func clamp() {
        intensity = min(max(intensity, Self.intensityRange.lowerBound), Self.intensityRange.upperBound)
        brushWidth = Self.nearestBrushPreset(brushWidth)
    }

    static func nearestBrushPreset(_ width: CGFloat) -> CGFloat {
        brushPresets.min(by: { abs($0 - width) < abs($1 - width) }) ?? 18
    }

    static func clampedIntensity(_ value: CGFloat) -> CGFloat {
        min(max(value, intensityRange.lowerBound), intensityRange.upperBound)
    }

    /// Maps Snipaste intensity 3…24 → gaussian radius in **points** (simple linear).
    static func blurRadiusPoints(forIntensity intensity: CGFloat) -> CGFloat {
        let t = (clampedIntensity(intensity) - intensityRange.lowerBound)
            / (intensityRange.upperBound - intensityRange.lowerBound)
        return 0.7 + t * 13.3 // ≈ 0.7 … 14
    }
}
