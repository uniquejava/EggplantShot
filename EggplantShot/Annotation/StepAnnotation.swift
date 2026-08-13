import AppKit

// Step / number badge style + prefs.

enum StepChromeKind: Int, CaseIterable {
    /// Solid color disk, white digit.
    case filled = 0
    /// Color ring + color digit (transparent fill).
    case outline = 1
    /// Color digit only (no circle).
    case plain = 2
}

/// Style for the step / numbering annotate tool.
struct StepStyle: Equatable {
    var kind: StepChromeKind
    /// Discrete size level (toolbar dropdown); maps to diameter via `diameter`.
    var size: CGFloat
    var color: NSColor

    static let `default` = StepStyle(
        kind: .filled,
        size: 4,
        color: PaletteColor.cyan.color
    )

    /// Snipaste-like size picker values.
    static let sizeChoices: [CGFloat] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 24]

    /// Visual diameter in points (size 5 ≈ 26pt).
    var diameter: CGFloat {
        10 + Self.nearestSize(size) * 3.2
    }

    /// Bold digit font sized to fit inside the disk / plain glyph.
    func makeFont() -> NSFont {
        let pointSize = max(diameter * 0.55, 8)
        return NSFont.systemFont(ofSize: pointSize, weight: .bold)
    }

    mutating func clamp() {
        size = Self.nearestSize(size)
    }

    static func nearestSize(_ value: CGFloat) -> CGFloat {
        sizeChoices.min(by: { abs($0 - value) < abs($1 - value) }) ?? 5
    }

    /// Axis-aligned bounds centered on `center` (selection-local).
    func bounds(around center: CGPoint) -> CGRect {
        let d = diameter
        switch kind {
        case .filled, .outline:
            return CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        case .plain:
            // Slightly tighter than the disk so the digit isn’t oversized empty chrome.
            let w = d * 0.72
            let h = d * 0.85
            return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        }
    }
}

/// Persisted last-used step annotate prefs.
enum StepAnnotationPrefs {
    private static let kindKey = "annotate.step.kind"
    private static let sizeKey = "annotate.step.size"
    private static let colorKey = "annotate.step.palette"

    static func load() -> StepStyle {
        let defaults = UserDefaults.standard
        var style = StepStyle.default
        if defaults.object(forKey: kindKey) != nil {
            style.kind = StepChromeKind(rawValue: defaults.integer(forKey: kindKey)) ?? .filled
        }
        if defaults.object(forKey: sizeKey) != nil {
            style.size = StepStyle.nearestSize(CGFloat(defaults.double(forKey: sizeKey)))
        }
        if defaults.object(forKey: colorKey) != nil,
           let swatch = PaletteColor(rawValue: defaults.integer(forKey: colorKey)) {
            style.color = swatch.color
        }
        return style
    }

    static func save(_ style: StepStyle) {
        var clamped = style
        clamped.clamp()
        let defaults = UserDefaults.standard
        defaults.set(clamped.kind.rawValue, forKey: kindKey)
        defaults.set(Double(clamped.size), forKey: sizeKey)
        defaults.set(PaletteColor.matching(clamped.color).rawValue, forKey: colorKey)
    }
}

/// Style for the magnifier annotate tool (frames + connector + sample mode).
