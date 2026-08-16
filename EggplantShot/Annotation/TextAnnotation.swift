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

    /// Spans the whole clamp range on purpose — this used to stop at 36, half of `fontSizeMax`, so the
    /// menu could not reach sizes the wheel could. It is also the fast path to the big end: the wheel's
    /// 2 pt notch would need ~65 of them to climb from the 14 pt default to the ceiling.
    static let fontSizeChoices: [CGFloat] = [8, 10, 12, 14, 16, 18, 24, 28, 36, 48, 64, 96, 144]
    /// Wheel / corner-resize / prefs range, in **points**. `AnnotationCompositor` composites in point
    /// space at the capture's pixel density, so a mark covers the same fraction of the frame on screen
    /// as in the exported PNG — the number here is a true point size, not a scaled index.
    /// 6 pt is the smallest still-legible label (1 pt was invisible, and a caret-wide box is what made
    /// corner-drag leverage hair-trigger). 144 pt is a headline callout — ~10% of frame height on a
    /// 1440 pt display, ~15% on a laptop — big enough to survive the downscaling a screenshot gets when
    /// pasted into chat; the previous 72 pt ceiling was only ~5%, about a quarter of Snipaste's reach.
    /// Applies to **input** paths only; decode keeps a saved snip's stored size verbatim so old snips
    /// render identically.
    static let fontSizeMin: CGFloat = 6
    static let fontSizeMax: CGFloat = 144
    /// Thinnest the caret ever draws — 1px hairline at 2x, the floor for very small type.
    static let caretWidthFloor: CGFloat = 0.5
    /// Thickest it ever draws. Past this a caret stops reading as a caret and starts looking like a
    /// selection block; 8 pt is the true stem of ~88 pt regular type, so the preview stays exact
    /// across most of the range and is merely "thick" above it. Aesthetic only — `textHorizontalPadding`
    /// is what reserves room inside the box and `placeHairlineCaret` clamps as a backstop, so no
    /// correctness rests on this number.
    static let caretWidthMax: CGFloat = 8

    /// Caret thickness that reads like the text's own stem, so an empty box previews the weight
    /// you are about to type at rather than showing a hairline at every size. Divisors are fitted to
    /// the system font's measured stem ink (`l` rasterised at 4x): ~size/11 regular, ~size/7 bold.
    /// Static so the field editor can derive the same value straight from its own `NSFont`.
    static func caretWidth(forFontSize size: CGFloat, isBold: Bool) -> CGFloat {
        min(caretWidthMax, max(caretWidthFloor, size / (isBold ? 7 : 11)))
    }

    var caretWidth: CGFloat { Self.caretWidth(forFontSize: fontSize, isBold: isBold) }

    /// Clamp into the supported range, dropping NaN / infinity to the default.
    /// Every path that can produce a `fontSize` — wheel, corner resize, prefs — goes through this.
    static func clampFontSize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return TextStyle.default.fontSize }
        return min(fontSizeMax, max(fontSizeMin, value))
    }

    /// Snap to a whole point, then step. Used by scroll-wheel resize.
    mutating func nudgeFontSize(by steps: Int) {
        guard steps != 0 else { return }
        let base = fontSize.rounded()
        fontSize = Self.clampFontSize(base + CGFloat(steps))
    }

    /// Tight wrap around glyphs. Font-independent, and the inset `drawText` actually uses.
    var textPadding: CGFloat { hasBackground ? 3 : 2 }

    /// Horizontal breathing room at *fitting* time, scaled with the caret for the same reason
    /// `textVerticalPadding` scales with the font. The caret is drawn **after** the last glyph, so the
    /// only room it has is the trailing padding: a flat 2 pt left a 144 pt caret hanging ~11 pt past
    /// the right border. Reserving `caretWidth` on each side also means the caret in an *empty* box
    /// occupies the middle third, which is what `emptyBoxWidth` wants.
    var textHorizontalPadding: CGFloat { max(textPadding, caretWidth) }

    /// Width of an empty text box: the caret plus its own padding, so the caret can sit centred.
    var emptyBoxWidth: CGFloat { caretWidth + textHorizontalPadding * 2 }

    /// Vertical breathing room. `textPadding`'s 2pt reads cramped — glyphs and the caret sit almost
    /// on the frame — so the box gets more room top and bottom, scaled gently with the font.
    /// Only the *fitting* uses this (and `textHorizontalPadding`); `drawText` **centres** the glyph
    /// block in whatever rect it is given, so marks saved before either padding existed still fit
    /// rather than clipping or re-wrapping (they shift down by ≤2pt — see `drawText`).
    var textVerticalPadding: CGFloat { max(textPadding * 2, fontSize * 0.12) }

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

/// The box-sizing arithmetic shared by the two places that must agree: `Annotation.fittingTextSize`,
/// which sizes the **committed** mark, and `AnnotationTextView.fittingSize`, which sizes the **live**
/// editor. They cannot share the *measurement* — the editor has to ask its own layout manager so IME
/// preedit counts, while the model measures an `NSAttributedString` — but everything on either side of
/// the measurement lives here, so a change to padding or wrapping lands in both instead of one.
///
/// The pair had already drifted: the model floored glyph width at nothing while the editor floored it
/// at `caretWidth`, and each recomputed `minHeight` from the font independently.
struct TextBoxMetrics {
    /// Stand-in for "unbounded" when measuring. `.greatestFiniteMagnitude` is the honest value but
    /// trips up layout arithmetic, so TextKit code conventionally uses a large finite number; this
    /// names the one that used to be spelled `10_000` at ten sites across five files.
    static let unboundedExtent: CGFloat = 10_000

    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let caretWidth: CGFloat
    let emptyWidth: CGFloat
    /// Floor from the font's own bounding box, so a box never collapses below one line of type.
    let minHeight: CGFloat
    /// Width past which the box soft-wraps instead of growing (the trailing screen edge, normally).
    let maxWidth: CGFloat

    init(style: TextStyle, maxWidth: CGFloat = TextBoxMetrics.unboundedExtent) {
        horizontalPadding = style.textHorizontalPadding
        verticalPadding = style.textVerticalPadding
        caretWidth = style.caretWidth
        emptyWidth = style.emptyBoxWidth
        minHeight = ceil(style.makeFont().boundingRectForFont.height) + style.textVerticalPadding * 2
        self.maxWidth = maxWidth
    }

    /// Caret-only box: no glyphs to wrap around, just room for the caret to sit centred.
    var emptySize: CGSize { CGSize(width: emptyWidth, height: minHeight) }

    /// Width the glyphs may occupy before the box would exceed `maxWidth`.
    var innerWidthAtMaxWidth: CGFloat { max(maxWidth - horizontalPadding * 2, 12) }

    /// Box that shrink-wraps a measured glyph extent, before any wrap decision.
    func size(glyphWidth: CGFloat, glyphHeight: CGFloat) -> CGSize {
        CGSize(
            width: max(ceil(glyphWidth), caretWidth) + horizontalPadding * 2,
            height: max(ceil(glyphHeight) + verticalPadding * 2, minHeight)
        )
    }

    /// Box for text that had to wrap: pinned to `maxWidth`, height from the re-measured extent.
    func wrappedSize(glyphHeight: CGFloat) -> CGSize {
        CGSize(width: maxWidth, height: max(ceil(glyphHeight) + verticalPadding * 2, minHeight))
    }

    /// Would a shrink-wrapped box of this size overrun the wrap width?
    func needsWrap(_ size: CGSize) -> Bool { size.width > maxWidth }
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
            // Clamp on read: a stored value can predate the 1…128 range (an unbounded corner
            // resize once persisted sizes in the hundreds) or be hand-edited in the plist.
            style.fontSize = TextStyle.clampFontSize(CGFloat(defaults.double(forKey: fontSizeKey)))
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
