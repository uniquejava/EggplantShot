import AppKit

// Text mark style + prefs.

struct TextStyle: Equatable {
    var color: NSColor
    var fontSize: CGFloat
    var isBold: Bool
    var isItalic: Bool
    /// Solid highlight behind glyphs (Snipaste “A in square”).
    var hasBackground: Bool

    static let `default` = TextStyle(
        color: PaletteColor.cyan.color,
        fontSize: 14,
        isBold: false,
        isItalic: false,
        hasBackground: false
    )

    static let fontSizeChoices: [CGFloat] = [8, 10, 12, 14, 16, 18, 24, 28, 36]
    /// Insertion-point width used only when the string is empty (matches 1px hairline at 2x).
    static let caretWidth: CGFloat = 0.5

    /// Tight wrap around glyphs (and the caret when empty).
    var textPadding: CGFloat { hasBackground ? 3 : 2 }

    /// System UI font with bold / italic traits.
    func makeFont() -> NSFont {
        var traits: NSFontTraitMask = []
        if isBold { traits.insert(.boldFontMask) }
        if isItalic { traits.insert(.italicFontMask) }
        let base = NSFont.systemFont(ofSize: fontSize)
        if traits.isEmpty { return base }
        let manager = NSFontManager.shared
        return manager.convert(base, toHaveTrait: traits)
    }

    func attributes() -> [NSAttributedString.Key: Any] {
        [
            .font: makeFont(),
            .foregroundColor: color,
        ]
    }
}

/// Persisted last-used text annotate prefs (separate from stroke prefs).
enum TextAnnotationPrefs {
    private static let colorKey = "annotate.text.palette"
    private static let fontSizeKey = "annotate.text.fontSize"
    private static let boldKey = "annotate.text.isBold"
    private static let italicKey = "annotate.text.isItalic"
    private static let backgroundKey = "annotate.text.hasBackground"

    static func load() -> TextStyle {
        let defaults = UserDefaults.standard
        var style = TextStyle.default
        if defaults.object(forKey: colorKey) != nil,
           let swatch = PaletteColor(rawValue: defaults.integer(forKey: colorKey)) {
            style.color = swatch.color
        }
        if defaults.object(forKey: fontSizeKey) != nil {
            style.fontSize = CGFloat(defaults.double(forKey: fontSizeKey))
        }
        style.isBold = defaults.bool(forKey: boldKey)
        style.isItalic = defaults.bool(forKey: italicKey)
        style.hasBackground = defaults.bool(forKey: backgroundKey)
        return style
    }

    static func save(_ style: TextStyle) {
        let defaults = UserDefaults.standard
        defaults.set(PaletteColor.matching(style.color).rawValue, forKey: colorKey)
        defaults.set(Double(style.fontSize), forKey: fontSizeKey)
        defaults.set(style.isBold, forKey: boldKey)
        defaults.set(style.isItalic, forKey: italicKey)
        defaults.set(style.hasBackground, forKey: backgroundKey)
    }
}

/// Chrome around a step / sequence number (Snipaste: filled · outline · plain).
