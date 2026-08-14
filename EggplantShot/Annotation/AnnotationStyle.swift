import AppKit

// Shared stroke style, palette, and shape kind.

struct AnnotationStyle: Equatable {
    var strokeWidth: CGFloat
    var strokeColor: NSColor
    /// Filled body (sub-toolbar item 4). Mutually exclusive with stroke-width picks.
    /// Ignored by pencil (always stroked).
    var isFilled: Bool
    /// Outline dash pattern (sub-toolbar item 7). Ignored when filled.
    var lineStyle: StrokeLineStyle

    static let `default` = AnnotationStyle(
        strokeWidth: StrokeWidthOption.medium.points,
        strokeColor: PaletteColor.cyan.color,
        isFilled: false,
        lineStyle: .solid
    )
}

/// Persisted last-used annotate prefs (stroke / fill / line style / color / shape kind).
enum StrokeLineStyle: Int, CaseIterable {
    /// 1. Continuous solid stroke.
    case solid
    /// 2. Long rectangular dashes.
    case longDash
    /// 3. Short rectangular bars.
    case shortDash
    /// 4. Long–short alternating.
    case longShort
    /// 5. Long–short–short alternating.
    case longShortShort

    var toolTip: String {
        switch self {
        case .solid: return "Solid"
        case .longDash: return "Long dash"
        case .shortDash: return "Short dash"
        case .longShort: return "Dash-dot"
        case .longShortShort: return "Dash-dot-dot"
        }
    }

    /// Dash pattern for `NSBezierPath.setLineDash` (empty = solid).
    /// Lengths scale with stroke width so bars stay rectangular and readable.
    func dashPattern(strokeWidth: CGFloat) -> [CGFloat] {
        let w = max(strokeWidth, 1)
        switch self {
        case .solid:
            return []
        case .longDash:
            return [w * 4.5, w * 2.2]
        case .shortDash:
            return [w * 1.35, w * 1.6]
        case .longShort:
            return [w * 4.5, w * 1.8, w * 1.35, w * 1.8]
        case .longShortShort:
            return [w * 4.5, w * 1.8, w * 1.35, w * 1.8, w * 1.35, w * 1.8]
        }
    }
}

/// Outline widths for the first three sub-toolbar dots (fill is separate).
enum StrokeWidthOption: Int, CaseIterable {
    case thin
    case medium
    case thick

    var points: CGFloat {
        switch self {
        case .thin: return 2
        case .medium: return 3.5
        case .thick: return 5
        }
    }

    /// Dot diameter shown in the sub-toolbar (keep visually light).
    var previewDiameter: CGFloat {
        switch self {
        case .thin: return 3
        case .medium: return 4.5
        case .thick: return 6
        }
    }

    var toolTip: String {
        switch self {
        case .thin: return "Thin"
        case .medium: return "Medium"
        case .thick: return "Thick"
        }
    }

    static func matching(_ width: CGFloat) -> StrokeWidthOption {
        allCases.min(by: { abs($0.points - width) < abs($1.points - width) }) ?? .medium
    }
}

/// Fixed Snipaste-like quick palette (2×10).
enum PaletteColor: Int, CaseIterable {
    // Row 1 — darker / saturated
    case black, darkGray, maroon, red, orange
    case yellow, green, cyan, blue, purple
    // Row 2 — light / pastel
    case white, lightGray, brown, pink, amber
    case cream, lime, sky, slateBlue, lavender

    var color: NSColor {
        switch self {
        case .black: return NSColor(calibratedWhite: 0.0, alpha: 1)
        case .darkGray: return NSColor(calibratedWhite: 0.50, alpha: 1)
        case .maroon: return NSColor(calibratedRed: 0.53, green: 0.0, blue: 0.08, alpha: 1)
        case .red: return NSColor(calibratedRed: 0.93, green: 0.11, blue: 0.14, alpha: 1)
        case .orange: return NSColor(calibratedRed: 1.0, green: 0.50, blue: 0.15, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.0, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.13, green: 0.69, blue: 0.30, alpha: 1)
        case .cyan: return NSColor(calibratedRed: 0.0, green: 0.64, blue: 0.91, alpha: 1)
        case .blue: return NSColor(calibratedRed: 0.25, green: 0.28, blue: 0.80, alpha: 1)
        case .purple: return NSColor(calibratedRed: 0.64, green: 0.29, blue: 0.64, alpha: 1)
        case .white: return NSColor(calibratedWhite: 1, alpha: 1)
        case .lightGray: return NSColor(calibratedWhite: 0.76, alpha: 1)
        case .brown: return NSColor(calibratedRed: 0.73, green: 0.48, blue: 0.34, alpha: 1)
        case .pink: return NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.79, alpha: 1)
        case .amber: return NSColor(calibratedRed: 1.0, green: 0.79, blue: 0.05, alpha: 1)
        case .cream: return NSColor(calibratedRed: 0.94, green: 0.89, blue: 0.69, alpha: 1)
        case .lime: return NSColor(calibratedRed: 0.71, green: 0.90, blue: 0.11, alpha: 1)
        case .sky: return NSColor(calibratedRed: 0.60, green: 0.85, blue: 0.92, alpha: 1)
        case .slateBlue: return NSColor(calibratedRed: 0.44, green: 0.57, blue: 0.75, alpha: 1)
        case .lavender: return NSColor(calibratedRed: 0.78, green: 0.75, blue: 0.91, alpha: 1)
        }
    }

    static func matching(_ color: NSColor) -> PaletteColor {
        let target = color.usingColorSpace(.genericRGB) ?? color
        return allCases.min(by: { a, b in
            distance(a.color, target) < distance(b.color, target)
        }) ?? .cyan
    }

    private static func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let aa = a.usingColorSpace(.genericRGB) ?? a
        let bb = b.usingColorSpace(.genericRGB) ?? b
        let dr = aa.redComponent - bb.redComponent
        let dg = aa.greenComponent - bb.greenComponent
        let db = aa.blueComponent - bb.blueComponent
        return dr * dr + dg * dg + db * db
    }
}

/// Shape kinds for the rectangle annotate tool (rect ↔ oval).
enum ShapeKind: Equatable {
    case rectangle
    case ellipse
}

/// Typography / fill used by the text annotate tool.
