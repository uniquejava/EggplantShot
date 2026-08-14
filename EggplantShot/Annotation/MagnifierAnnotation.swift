import AppKit

// Magnifier style, prefs, and lens/source part.

enum MagnifierPart: Equatable {
    case source
    case lens
}

struct MagnifierStyle: Equatable {
    var strokeWidth: CGFloat
    var color: NSColor
    /// When true, sample freeze/base **plus prior marks** into the lens (excludes self).
    var includeAnnotations: Bool
    /// Authoritative zoom (`lens / source`). Only changed via the scale slider (not by frame resize).
    var scale: CGFloat

    static let scaleRange: ClosedRange<CGFloat> = 1...6

    static let `default` = MagnifierStyle(
        strokeWidth: StrokeWidthOption.thin.points,
        color: PaletteColor.red.color,
        includeAnnotations: false,
        scale: defaultScale
    )

    /// Default lens / source scale when creating a concentric pair.
    /// 2× matches common screenshot-magnifier defaults (clear double without over-zoom).
    static let defaultScale: CGFloat = 2

    mutating func clamp() {
        strokeWidth = StrokeWidthOption.matching(strokeWidth).points
        scale = Self.clampedScale(scale)
    }

    static func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
    }
}

/// Persisted last-used magnifier annotate prefs.
enum MagnifierAnnotationPrefs {
    private static let kindKey = "annotate.magnifier.kind"
    private static let strokeWidthKey = "annotate.magnifier.strokeWidth"
    private static let colorKey = "annotate.magnifier.palette"
    private static let includeKey = "annotate.magnifier.includeAnnotations"
    private static let scaleKey = "annotate.magnifier.scale"

    static func load() -> (kind: ShapeKind, style: MagnifierStyle) {
        let defaults = UserDefaults.standard
        var style = MagnifierStyle.default
        if defaults.object(forKey: strokeWidthKey) != nil {
            style.strokeWidth = CGFloat(defaults.double(forKey: strokeWidthKey))
        }
        if defaults.object(forKey: colorKey) != nil,
           let swatch = PaletteColor(rawValue: defaults.integer(forKey: colorKey)) {
            style.color = swatch.color
        }
        if defaults.object(forKey: includeKey) != nil {
            style.includeAnnotations = defaults.bool(forKey: includeKey)
        }
        if defaults.object(forKey: scaleKey) != nil {
            style.scale = MagnifierStyle.clampedScale(CGFloat(defaults.double(forKey: scaleKey)))
        }
        style.clamp()
        let kind: ShapeKind = defaults.integer(forKey: kindKey) == 1 ? .ellipse : .rectangle
        return (kind, style)
    }

    static func save(kind: ShapeKind, style: MagnifierStyle) {
        var clamped = style
        clamped.clamp()
        let defaults = UserDefaults.standard
        defaults.set(kind == .ellipse ? 1 : 0, forKey: kindKey)
        defaults.set(Double(clamped.strokeWidth), forKey: strokeWidthKey)
        defaults.set(PaletteColor.matching(clamped.color).rawValue, forKey: colorKey)
        defaults.set(clamped.includeAnnotations, forKey: includeKey)
        defaults.set(Double(clamped.scale), forKey: scaleKey)
    }
}

/// Extensible mark payload. New tools add cases here without forking history/store.
