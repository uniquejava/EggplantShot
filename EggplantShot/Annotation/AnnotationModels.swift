import AppKit
import CoreImage

/// Drawing tool selected on the refine toolbar. `.none` = refine selection only.
enum AnnotateTool: Equatable {
    case none
    case rectangle
    case arrow
    case pencil
    case mosaic
    case text
}

/// Mosaic / blur draw mode: freehand stroke, or drag a blurred region.
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

    /// Maps Snipaste intensity 3…24 → gaussian radius in **points**.
    /// At 3 the backdrop (e.g. body text) stays readable; at 24 it’s heavily defocused.
    static func blurRadiusPoints(forIntensity intensity: CGFloat) -> CGFloat {
        let t = (clampedIntensity(intensity) - intensityRange.lowerBound)
            / (intensityRange.upperBound - intensityRange.lowerBound)
        return 0.7 + t * 13.3 // ≈ 0.7 … 14
    }
}

/// Arrowhead / end-cap styles (Snipaste start / end dropdown).
/// Raw values are stable for disk prefs; `menuCases` order matches the menu.
enum ArrowCapStyle: Int, CaseIterable {
    case none = 0
    case bar = 2
    case circle = 3
    case diamond = 4
    /// Open chevron; shaft runs to the tip so line + wings stay connected.
    case openArrow = 5
    /// Kept for older prefs / disk; not shown in the menu (looked like `openArrow`).
    case openArrowWide = 6
    /// Filled triangle (default end cap). Raw value 1 kept for existing records.
    case arrow = 1
    case hollowArrow = 7

    /// Styles shown in the start / end dropdown (Snipaste order, no near-duplicate).
    static let menuCases: [ArrowCapStyle] = [
        .none, .bar, .circle, .diamond, .openArrow, .arrow, .hollowArrow,
    ]

    /// True for triangle / chevron arrowheads (used by double-ended Switch).
    var isArrowhead: Bool {
        switch self {
        case .openArrow, .openArrowWide, .arrow, .hollowArrow: return true
        default: return false
        }
    }
}

/// Start / end caps for an arrow mark.
struct ArrowCaps: Equatable {
    var start: ArrowCapStyle
    var end: ArrowCapStyle

    static let `default` = ArrowCaps(start: .none, end: .openArrow)

    /// Both ends plain (Switch “no arrow” row active).
    var isPlainLine: Bool { start == .none && end == .none }

    /// At least one end has an ornament (Switch “with arrow” row active).
    var hasCaps: Bool { !isPlainLine }

    static func plainLine() -> ArrowCaps { ArrowCaps(start: .none, end: .none) }
}

/// Which endpoint is being dragged while editing an arrow.
enum ArrowEndpoint: Equatable {
    case start
    case end
}

/// Stroke / fill / color used when drawing or editing an annotation.
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
enum AnnotationPrefs {
    private static let strokeWidthKey = "annotate.strokeWidth"
    private static let isFilledKey = "annotate.isFilled"
    private static let lineStyleKey = "annotate.lineStyle"
    private static let paletteKey = "annotate.palette"
    private static let kindKey = "annotate.kind"
    private static let arrowStartCapKey = "annotate.arrow.startCap"
    private static let arrowEndCapKey = "annotate.arrow.endCap"
    private static let mosaicBrushWidthKey = "annotate.mosaic.brushWidth"
    private static let mosaicDrawModeKey = "annotate.mosaic.drawMode"
    private static let mosaicIntensityKey = "annotate.mosaic.intensity"
    /// Legacy tip-shape key; migrated into `mosaicDrawModeKey`.
    private static let mosaicBrushKindKey = "annotate.mosaic.brushKind"

    static func load() -> (style: AnnotationStyle, kind: ShapeKind) {
        let defaults = UserDefaults.standard
        var style = AnnotationStyle.default
        if defaults.object(forKey: strokeWidthKey) != nil {
            style.strokeWidth = CGFloat(defaults.double(forKey: strokeWidthKey))
        }
        style.isFilled = defaults.bool(forKey: isFilledKey)
        if defaults.object(forKey: lineStyleKey) != nil,
           let line = StrokeLineStyle(rawValue: defaults.integer(forKey: lineStyleKey)) {
            style.lineStyle = line
        }
        if defaults.object(forKey: paletteKey) != nil,
           let swatch = PaletteColor(rawValue: defaults.integer(forKey: paletteKey)) {
            style.strokeColor = swatch.color
        }
        let kind: ShapeKind = defaults.integer(forKey: kindKey) == 1 ? .ellipse : .rectangle
        return (style, kind)
    }

    static func loadArrowCaps() -> ArrowCaps {
        let defaults = UserDefaults.standard
        let start = ArrowCapStyle(rawValue: defaults.integer(forKey: arrowStartCapKey)) ?? .none
        let end: ArrowCapStyle
        if defaults.object(forKey: arrowEndCapKey) != nil {
            end = ArrowCapStyle(rawValue: defaults.integer(forKey: arrowEndCapKey)) ?? .openArrow
        } else {
            end = .openArrow
        }
        return ArrowCaps(start: start, end: end)
    }

    static func save(style: AnnotationStyle, kind: ShapeKind) {
        let defaults = UserDefaults.standard
        defaults.set(Double(style.strokeWidth), forKey: strokeWidthKey)
        defaults.set(style.isFilled, forKey: isFilledKey)
        defaults.set(style.lineStyle.rawValue, forKey: lineStyleKey)
        defaults.set(PaletteColor.matching(style.strokeColor).rawValue, forKey: paletteKey)
        defaults.set(kind == .ellipse ? 1 : 0, forKey: kindKey)
    }

    static func saveArrowCaps(_ caps: ArrowCaps) {
        let defaults = UserDefaults.standard
        defaults.set(caps.start.rawValue, forKey: arrowStartCapKey)
        defaults.set(caps.end.rawValue, forKey: arrowEndCapKey)
    }

    static func loadMosaicStyle() -> MosaicStyle {
        let defaults = UserDefaults.standard
        var style = MosaicStyle.default
        if defaults.object(forKey: mosaicBrushWidthKey) != nil {
            style.brushWidth = MosaicStyle.nearestBrushPreset(
                CGFloat(defaults.double(forKey: mosaicBrushWidthKey))
            )
        }
        if defaults.object(forKey: mosaicIntensityKey) != nil {
            style.intensity = MosaicStyle.clampedIntensity(
                CGFloat(defaults.double(forKey: mosaicIntensityKey))
            )
        }
        return style
    }

    static func loadMosaicDrawMode() -> MosaicDrawMode {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: mosaicDrawModeKey) != nil {
            return MosaicDrawMode(rawValue: defaults.integer(forKey: mosaicDrawModeKey)) ?? .freehand
        }
        // Migrate old tip-shape prefs (0 rect / 1 oval) → region modes.
        if defaults.object(forKey: mosaicBrushKindKey) != nil {
            switch defaults.integer(forKey: mosaicBrushKindKey) {
            case 0: return .rectangle
            case 1: return .ellipse
            default: return .freehand
            }
        }
        return .freehand
    }

    static func saveMosaicStyle(_ style: MosaicStyle) {
        var clamped = style
        clamped.clamp()
        let defaults = UserDefaults.standard
        defaults.set(Double(clamped.brushWidth), forKey: mosaicBrushWidthKey)
        defaults.set(Double(clamped.intensity), forKey: mosaicIntensityKey)
    }

    static func saveMosaicDrawMode(_ mode: MosaicDrawMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: mosaicDrawModeKey)
    }
}

/// Border outline pattern for stroke shapes (Snipaste 5 styles).
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

/// Extensible mark payload. New tools add cases here without forking history/store.
enum AnnotationPayload: Equatable {
    case shape(ShapeKind, rect: CGRect, style: AnnotationStyle)
    case arrow(start: CGPoint, end: CGPoint, style: AnnotationStyle, caps: ArrowCaps)
    case pencil(points: [CGPoint], style: AnnotationStyle)
    case mosaic(MosaicGeometry, style: MosaicStyle)
    case text(string: String, rect: CGRect, style: TextStyle)
}

/// One drawable mark. Geometry is in **selection-local** Cocoa points
/// (origin = selection bottom-left).
struct Annotation: Equatable {
    let id: UUID
    var payload: AnnotationPayload

    init(id: UUID = UUID(), payload: AnnotationPayload) {
        self.id = id
        self.payload = payload
    }

    /// Convenience for the shape tool.
    init(id: UUID = UUID(), kind: ShapeKind = .rectangle, rect: CGRect, style: AnnotationStyle) {
        self.id = id
        self.payload = .shape(kind, rect: rect, style: style)
    }

    /// Convenience for the arrow tool.
    init(
        id: UUID = UUID(),
        start: CGPoint,
        end: CGPoint,
        style: AnnotationStyle,
        caps: ArrowCaps = .default
    ) {
        self.id = id
        self.payload = .arrow(start: start, end: end, style: style, caps: caps)
    }

    /// Convenience for the pencil tool.
    init(id: UUID = UUID(), points: [CGPoint], style: AnnotationStyle) {
        self.id = id
        self.payload = .pencil(points: points, style: style)
    }

    /// Convenience for freehand mosaic.
    init(id: UUID = UUID(), mosaicPoints points: [CGPoint], mosaicStyle: MosaicStyle) {
        self.id = id
        self.payload = .mosaic(.stroke(points: points), style: mosaicStyle)
    }

    /// Convenience for region mosaic (rect / oval).
    init(
        id: UUID = UUID(),
        mosaicRegion mode: MosaicDrawMode,
        rect: CGRect,
        mosaicStyle: MosaicStyle
    ) {
        self.id = id
        let kind: MosaicDrawMode = (mode == .ellipse) ? .ellipse : .rectangle
        self.payload = .mosaic(.region(kind, rect: rect), style: mosaicStyle)
    }

    /// Convenience for the text tool.
    init(id: UUID = UUID(), string: String, rect: CGRect, style: TextStyle) {
        self.id = id
        self.payload = .text(string: string, rect: rect, style: style)
    }

    /// Disk / tooling type discriminator (`"shape"`, `"pencil"`, `"mosaic"`, `"text"`, …).
    var typeName: String {
        switch payload {
        case .shape: return "shape"
        case .arrow: return "arrow"
        case .pencil: return "pencil"
        case .mosaic: return "mosaic"
        case .text: return "text"
        }
    }

    // MARK: Shared accessors

    /// Stroke style for shape / arrow / pencil. No-op get/set for mosaic / text marks.
    var style: AnnotationStyle {
        get {
            switch payload {
            case .shape(_, _, let style), .arrow(_, _, let style, _), .pencil(_, let style):
                return style
            case .mosaic, .text:
                return .default
            }
        }
        set {
            switch payload {
            case .shape(let kind, let rect, _):
                payload = .shape(kind, rect: rect, style: newValue)
            case .arrow(let start, let end, _, let caps):
                payload = .arrow(start: start, end: end, style: newValue, caps: caps)
            case .pencil(let points, _):
                payload = .pencil(points: points, style: newValue)
            case .mosaic, .text:
                break
            }
        }
    }

    var mosaicStyle: MosaicStyle {
        get {
            if case .mosaic(_, let style) = payload { return style }
            return .default
        }
        set {
            guard case .mosaic(let geometry, _) = payload else { return }
            var style = newValue
            style.clamp()
            payload = .mosaic(geometry, style: style)
        }
    }

    var mosaicGeometry: MosaicGeometry? {
        get {
            if case .mosaic(let geometry, _) = payload { return geometry }
            return nil
        }
        set {
            guard let newValue, case .mosaic(_, let style) = payload else { return }
            payload = .mosaic(newValue, style: style)
        }
    }

    var isMosaicStroke: Bool {
        if case .mosaic(.stroke, _) = payload { return true }
        return false
    }

    var isMosaicRegion: Bool {
        if case .mosaic(.region, _) = payload { return true }
        return false
    }

    var textStyle: TextStyle {
        get {
            if case .text(_, _, let style) = payload { return style }
            return .default
        }
        set {
            guard case .text(let string, let rect, _) = payload else { return }
            payload = .text(string: string, rect: rect, style: newValue)
        }
    }

    /// Axis-aligned bounds in selection-local space.
    var boundingRect: CGRect {
        switch payload {
        case .shape(_, let rect, _), .text(_, let rect, _):
            return rect
        case .arrow(let start, let end, let style, let caps):
            return AnnotationDrawing.arrowBounds(start: start, end: end, style: style, caps: caps)
        case .pencil(let points, _):
            return Self.bounds(of: points)
        case .mosaic(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                let hull = Self.bounds(of: points)
                let pad = style.brushWidth / 2
                return hull.insetBy(dx: -pad, dy: -pad)
            case .region(_, let rect):
                return rect
            }
        }
    }

    var isShape: Bool {
        if case .shape = payload { return true }
        return false
    }

    var isArrow: Bool {
        if case .arrow = payload { return true }
        return false
    }

    var isPencil: Bool {
        if case .pencil = payload { return true }
        return false
    }

    var isMosaic: Bool {
        if case .mosaic = payload { return true }
        return false
    }

    var isText: Bool {
        if case .text = payload { return true }
        return false
    }

    // MARK: Shape accessors (no-ops for non-shape payloads)

    var kind: ShapeKind {
        get {
            if case .shape(let kind, _, _) = payload { return kind }
            return .rectangle
        }
        set {
            guard case .shape(_, let rect, let style) = payload else { return }
            payload = .shape(newValue, rect: rect, style: style)
        }
    }

    var rect: CGRect {
        get { boundingRect }
        set {
            switch payload {
            case .shape(let kind, _, let style):
                payload = .shape(kind, rect: newValue, style: style)
            case .text(let string, _, let style):
                payload = .text(string: string, rect: newValue, style: style)
            case .arrow, .pencil, .mosaic:
                break
            }
        }
    }

    var points: [CGPoint] {
        get {
            switch payload {
            case .pencil(let points, _):
                return points
            case .mosaic(.stroke(let points), _):
                return points
            default:
                return []
            }
        }
        set {
            switch payload {
            case .pencil(_, let style):
                payload = .pencil(points: newValue, style: style)
            case .mosaic(.stroke, let style):
                payload = .mosaic(.stroke(points: newValue), style: style)
            default:
                break
            }
        }
    }

    var string: String {
        get {
            if case .text(let string, _, _) = payload { return string }
            return ""
        }
        set {
            guard case .text(_, let rect, let style) = payload else { return }
            payload = .text(string: newValue, rect: rect, style: style)
        }
    }

    // MARK: Arrow accessors

    var arrowStart: CGPoint {
        get {
            if case .arrow(let start, _, _, _) = payload { return start }
            return .zero
        }
        set {
            guard case .arrow(_, let end, let style, let caps) = payload else { return }
            payload = .arrow(start: newValue, end: end, style: style, caps: caps)
        }
    }

    var arrowEnd: CGPoint {
        get {
            if case .arrow(_, let end, _, _) = payload { return end }
            return .zero
        }
        set {
            guard case .arrow(let start, _, let style, let caps) = payload else { return }
            payload = .arrow(start: start, end: newValue, style: style, caps: caps)
        }
    }

    var arrowCaps: ArrowCaps {
        get {
            if case .arrow(_, _, _, let caps) = payload { return caps }
            return .default
        }
        set {
            guard case .arrow(let start, let end, let style, _) = payload else { return }
            payload = .arrow(start: start, end: end, style: style, caps: newValue)
        }
    }

    // MARK: Geometry helpers

    mutating func translate(by delta: CGSize) {
        switch payload {
        case .shape(let kind, let rect, let style):
            payload = .shape(kind, rect: rect.offsetBy(dx: delta.width, dy: delta.height), style: style)
        case .arrow(let start, let end, let style, let caps):
            let s = CGPoint(x: start.x + delta.width, y: start.y + delta.height)
            let e = CGPoint(x: end.x + delta.width, y: end.y + delta.height)
            payload = .arrow(start: s, end: e, style: style, caps: caps)
        case .pencil(let points, let style):
            let moved = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
            payload = .pencil(points: moved, style: style)
        case .mosaic(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                let moved = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
                payload = .mosaic(.stroke(points: moved), style: style)
            case .region(let mode, let rect):
                payload = .mosaic(
                    .region(mode, rect: rect.offsetBy(dx: delta.width, dy: delta.height)),
                    style: style
                )
            }
        case .text(let string, let rect, let style):
            payload = .text(
                string: string,
                rect: rect.offsetBy(dx: delta.width, dy: delta.height),
                style: style
            )
        }
    }

    /// Maps geometry so `boundingRect` becomes `newBounds` (used by resize handles).
    mutating func mapBoundingRect(to newBounds: CGRect) {
        let old = boundingRect
        guard old.width > 0, old.height > 0 else { return }
        switch payload {
        case .shape(let kind, _, let style):
            payload = .shape(kind, rect: newBounds, style: style)
        case .arrow(let start, let end, let style, let caps):
            let sx = newBounds.width / old.width
            let sy = newBounds.height / old.height
            let s = CGPoint(
                x: newBounds.minX + (start.x - old.minX) * sx,
                y: newBounds.minY + (start.y - old.minY) * sy
            )
            let e = CGPoint(
                x: newBounds.minX + (end.x - old.minX) * sx,
                y: newBounds.minY + (end.y - old.minY) * sy
            )
            payload = .arrow(start: s, end: e, style: style, caps: caps)
        case .pencil(let points, let style):
            let sx = newBounds.width / old.width
            let sy = newBounds.height / old.height
            let mapped = points.map { p in
                CGPoint(
                    x: newBounds.minX + (p.x - old.minX) * sx,
                    y: newBounds.minY + (p.y - old.minY) * sy
                )
            }
            payload = .pencil(points: mapped, style: style)
        case .mosaic(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                let pad = style.brushWidth / 2
                let oldHull = old.insetBy(dx: pad, dy: pad)
                let newHull = newBounds.insetBy(dx: pad, dy: pad)
                guard oldHull.width > 0, oldHull.height > 0 else { return }
                let sx = newHull.width / oldHull.width
                let sy = newHull.height / oldHull.height
                let mapped = points.map { p in
                    CGPoint(
                        x: newHull.minX + (p.x - oldHull.minX) * sx,
                        y: newHull.minY + (p.y - oldHull.minY) * sy
                    )
                }
                payload = .mosaic(.stroke(points: mapped), style: style)
            case .region(let mode, _):
                payload = .mosaic(.region(mode, rect: newBounds), style: style)
            }
        case .text(let string, _, let style):
            payload = .text(string: string, rect: newBounds, style: style)
        }
    }

    /// How `origin` maps onto the fitted text box (selection-local Cocoa points).
    enum TextRectAnchor {
        /// `origin` is the top-left (grow downward while editing).
        case topLeft
        /// `origin` is the left edge at the vertical center (click-to-place).
        case leadingMidY
    }

    /// Fitted rect for `string` with `style`, anchored at `origin`.
    /// Width grows with glyphs; wraps only when exceeding `maxWidth`.
    static func fittedTextRect(
        string: String,
        style: TextStyle,
        origin: CGPoint,
        maxWidth: CGFloat = 10_000,
        anchor: TextRectAnchor = .topLeft
    ) -> CGRect {
        let size = fittingTextSize(string: string, style: style, maxWidth: maxWidth)
        let y: CGFloat
        switch anchor {
        case .topLeft:
            y = origin.y - size.height
        case .leadingMidY:
            y = origin.y - size.height / 2
        }
        return CGRect(x: origin.x, y: y, width: size.width, height: size.height)
    }

    /// Box size: glyphs + tiny padding only; empty box is caret-wide. Soft-wrap past `maxWidth`.
    static func fittingTextSize(
        string: String,
        style: TextStyle,
        maxWidth: CGFloat = 10_000
    ) -> CGSize {
        let pad = style.textPadding
        let minH = ceil(style.makeFont().boundingRectForFont.height) + pad * 2
        if string.isEmpty {
            return CGSize(width: pad * 2 + TextStyle.caretWidth, height: minH)
        }
        let attributed = NSAttributedString(string: string, attributes: style.attributes())
        let natural = attributed.boundingRect(
            with: CGSize(width: 10_000, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let naturalW = ceil(natural.width) + pad * 2
        let naturalH = max(ceil(natural.height) + pad * 2, minH)
        if naturalW <= maxWidth {
            return CGSize(width: naturalW, height: naturalH)
        }
        let inner = max(maxWidth - pad * 2, 12)
        let wrapped = attributed.boundingRect(
            with: CGSize(width: inner, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(
            width: maxWidth,
            height: max(ceil(wrapped.height) + pad * 2, minH)
        )
    }

    static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }
}

enum AnnotationDrawing {
    /// Backdrop used to sample pixels for mosaic / blur marks.
    struct MosaicSampleContext {
        let image: NSImage
        /// Image-space point corresponding to selection-local `(0, 0)`.
        let selectionOriginInImage: CGPoint
    }

    /// Draw `annotation` with selection-local geometry offset by `origin` (selection frame origin in context).
    static func draw(_ annotation: Annotation, origin: CGPoint, sample: MosaicSampleContext? = nil) {
        switch annotation.payload {
        case .shape(let kind, let localRect, let style):
            let rect = localRect.offsetBy(dx: origin.x, dy: origin.y)
            drawShape(kind: kind, style: style, in: rect)
        case .arrow(let start, let end, let style, let caps):
            let s = CGPoint(x: start.x + origin.x, y: start.y + origin.y)
            let e = CGPoint(x: end.x + origin.x, y: end.y + origin.y)
            drawArrow(start: s, end: e, style: style, caps: caps)
        case .pencil(let points, let style):
            let offset = points.map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
            drawPencil(points: offset, style: style)
        case .mosaic(let geometry, let style):
            drawMosaic(geometry: geometry, style: style, drawOrigin: origin, sample: sample)
        case .text(let string, let localRect, let style):
            let rect = localRect.offsetBy(dx: origin.x, dy: origin.y)
            drawText(string: string, style: style, in: rect)
        }
    }

    /// Legacy entry used when the caller already converted a shape rect to context space.
    static func draw(_ annotation: Annotation, in rect: CGRect) {
        switch annotation.payload {
        case .shape(let kind, _, let style):
            drawShape(kind: kind, style: style, in: rect)
        case .arrow, .pencil, .mosaic, .text:
            draw(annotation, origin: .zero)
        }
    }

    private static func drawShape(kind: ShapeKind, style: AnnotationStyle, in rect: CGRect) {
        let path: NSBezierPath
        switch kind {
        case .rectangle:
            path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        case .ellipse:
            path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        }

        if style.isFilled {
            style.strokeColor.setFill()
            path.fill()
        } else {
            applyStroke(style, to: path)
            style.strokeColor.setStroke()
            path.stroke()
        }
    }

    private static func drawArrow(start: CGPoint, end: CGPoint, style: AnnotationStyle, caps: ArrowCaps) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else {
            let r = max(style.strokeWidth / 2, 0.5)
            style.strokeColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)).fill()
            return
        }

        let ux = dx / length
        let uy = dy / length
        let startInset = shaftInset(for: caps.start, strokeWidth: style.strokeWidth)
        let endInset = shaftInset(for: caps.end, strokeWidth: style.strokeWidth)

        var shaftStart = start
        var shaftEnd = end
        if startInset > 0 {
            shaftStart = CGPoint(x: start.x + ux * startInset, y: start.y + uy * startInset)
        }
        if endInset > 0 {
            shaftEnd = CGPoint(x: end.x - ux * endInset, y: end.y - uy * endInset)
        }

        if hypot(shaftEnd.x - shaftStart.x, shaftEnd.y - shaftStart.y) > 0.5 {
            let path = NSBezierPath()
            path.move(to: shaftStart)
            path.line(to: shaftEnd)
            applyStroke(style, to: path)
            path.lineCapStyle = .butt
            style.strokeColor.setStroke()
            path.stroke()
        }

        // Outward at start is opposite the shaft; at end along the shaft.
        drawCap(caps.start, tip: start, directionX: -ux, directionY: -uy, style: style)
        drawCap(caps.end, tip: end, directionX: ux, directionY: uy, style: style)
    }

    /// How far the shaft stops short of `tip` for this cap.
    static func shaftInset(for cap: ArrowCapStyle, strokeWidth: CGFloat) -> CGFloat {
        switch cap {
        case .none, .bar:
            // Open chevrons: shaft runs all the way to the tip so line + arrow stay one piece.
            return 0
        case .openArrow, .openArrowWide:
            return 0
        case .circle:
            return circleRadius(strokeWidth: strokeWidth)
        case .diamond:
            return diamondHalfLength(strokeWidth: strokeWidth) * 2
        case .arrow, .hollowArrow:
            // Meet the triangle base, overlapping slightly so stroke + fill fuse.
            return max(arrowheadLength(strokeWidth: strokeWidth) - strokeWidth * 0.35, strokeWidth)
        }
    }

    private static func drawCap(
        _ cap: ArrowCapStyle,
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        style: AnnotationStyle
    ) {
        let w = style.strokeWidth
        let color = style.strokeColor
        switch cap {
        case .none:
            break

        case .bar:
            let half = max(w * 1.6, 4)
            let px = -directionY
            let py = directionX
            let a = CGPoint(x: tip.x + px * half, y: tip.y + py * half)
            let b = CGPoint(x: tip.x - px * half, y: tip.y - py * half)
            let path = NSBezierPath()
            path.move(to: a)
            path.line(to: b)
            path.lineWidth = w
            path.lineCapStyle = .butt
            color.setStroke()
            path.stroke()

        case .circle:
            let r = circleRadius(strokeWidth: w)
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)).fill()

        case .diamond:
            let halfLen = diamondHalfLength(strokeWidth: w)
            let halfWid = max(w * 1.4, 3.5)
            let px = -directionY
            let py = directionX
            let base = CGPoint(x: tip.x - directionX * halfLen * 2, y: tip.y - directionY * halfLen * 2)
            let mid = CGPoint(x: tip.x - directionX * halfLen, y: tip.y - directionY * halfLen)
            let left = CGPoint(x: mid.x + px * halfWid, y: mid.y + py * halfWid)
            let right = CGPoint(x: mid.x - px * halfWid, y: mid.y - py * halfWid)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: left)
            path.line(to: base)
            path.line(to: right)
            path.close()
            color.setFill()
            path.fill()

        case .openArrow:
            drawOpenArrowhead(
                tip: tip,
                directionX: directionX,
                directionY: directionY,
                length: openArrowLength(strokeWidth: w, wide: false),
                width: openArrowWidth(strokeWidth: w, wide: false),
                strokeWidth: w,
                color: color
            )

        case .openArrowWide:
            drawOpenArrowhead(
                tip: tip,
                directionX: directionX,
                directionY: directionY,
                length: openArrowLength(strokeWidth: w, wide: true),
                width: openArrowWidth(strokeWidth: w, wide: true),
                strokeWidth: w,
                color: color
            )

        case .arrow:
            drawFilledArrowhead(
                tip: tip,
                directionX: directionX,
                directionY: directionY,
                length: arrowheadLength(strokeWidth: w),
                width: arrowheadWidth(strokeWidth: w),
                color: color
            )

        case .hollowArrow:
            drawHollowArrowhead(
                tip: tip,
                directionX: directionX,
                directionY: directionY,
                length: arrowheadLength(strokeWidth: w),
                width: arrowheadWidth(strokeWidth: w),
                strokeWidth: max(w * 0.85, 1.2),
                color: color
            )
        }
    }

    private static func drawFilledArrowhead(
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        length: CGFloat,
        width: CGFloat,
        color: NSColor
    ) {
        let base = CGPoint(x: tip.x - directionX * length, y: tip.y - directionY * length)
        let px = -directionY
        let py = directionX
        let left = CGPoint(x: base.x + px * width / 2, y: base.y + py * width / 2)
        let right = CGPoint(x: base.x - px * width / 2, y: base.y - py * width / 2)
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: left)
        path.line(to: right)
        path.close()
        color.setFill()
        path.fill()
    }

    private static func drawHollowArrowhead(
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        length: CGFloat,
        width: CGFloat,
        strokeWidth: CGFloat,
        color: NSColor
    ) {
        let base = CGPoint(x: tip.x - directionX * length, y: tip.y - directionY * length)
        let px = -directionY
        let py = directionX
        let left = CGPoint(x: base.x + px * width / 2, y: base.y + py * width / 2)
        let right = CGPoint(x: base.x - px * width / 2, y: base.y - py * width / 2)
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: left)
        path.line(to: right)
        path.close()
        path.lineWidth = strokeWidth
        path.lineJoinStyle = .miter
        path.lineCapStyle = .butt
        color.setStroke()
        path.stroke()
    }

    private static func drawOpenArrowhead(
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        length: CGFloat,
        width: CGFloat,
        strokeWidth: CGFloat,
        color: NSColor
    ) {
        let base = CGPoint(x: tip.x - directionX * length, y: tip.y - directionY * length)
        let px = -directionY
        let py = directionX
        let left = CGPoint(x: base.x + px * width / 2, y: base.y + py * width / 2)
        let right = CGPoint(x: base.x - px * width / 2, y: base.y - py * width / 2)
        let path = NSBezierPath()
        path.move(to: left)
        path.line(to: tip)
        path.line(to: right)
        path.lineWidth = strokeWidth
        path.lineJoinStyle = .miter
        path.lineCapStyle = .butt
        color.setStroke()
        path.stroke()
    }

    static func circleRadius(strokeWidth: CGFloat) -> CGFloat {
        max(strokeWidth * 1.35, 3.5)
    }

    static func diamondHalfLength(strokeWidth: CGFloat) -> CGFloat {
        max(strokeWidth * 1.6, 4)
    }

    static func openArrowLength(strokeWidth: CGFloat, wide: Bool) -> CGFloat {
        // Shorter depth + wider span → opener V (closer to Snipaste open chevron).
        wide ? max(strokeWidth * 2.8, 8) : max(strokeWidth * 2.5, 7)
    }

    static func openArrowWidth(strokeWidth: CGFloat, wide: Bool) -> CGFloat {
        wide ? max(strokeWidth * 4.6, 12) : max(strokeWidth * 4.2, 11)
    }

    static func arrowheadLength(strokeWidth: CGFloat) -> CGFloat {
        max(strokeWidth * 3.2, 8)
    }

    static func arrowheadWidth(strokeWidth: CGFloat) -> CGFloat {
        max(strokeWidth * 2.4, 6)
    }

    /// Axis-aligned bounds including end caps.
    static func arrowBounds(start: CGPoint, end: CGPoint, style: AnnotationStyle, caps: ArrowCaps) -> CGRect {
        var minX = min(start.x, end.x)
        var maxX = max(start.x, end.x)
        var minY = min(start.y, end.y)
        var maxY = max(start.y, end.y)
        let pad = max(
            arrowheadWidth(strokeWidth: style.strokeWidth) / 2,
            openArrowWidth(strokeWidth: style.strokeWidth, wide: true) / 2,
            circleRadius(strokeWidth: style.strokeWidth),
            style.strokeWidth * 1.6,
            style.strokeWidth / 2
        ) + 1
        minX -= pad
        maxX += pad
        minY -= pad
        maxY += pad
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    /// Expanded hit region for a cap (selection-local). `direction` points outward toward the tip.
    static func capHitPath(
        _ cap: ArrowCapStyle,
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        strokeWidth: CGFloat
    ) -> NSBezierPath? {
        let w = strokeWidth
        let px = -directionY
        let py = directionX
        switch cap {
        case .none:
            return nil
        case .bar:
            return nil
        case .circle:
            let r = circleRadius(strokeWidth: w) + 2
            return NSBezierPath(ovalIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2))
        case .diamond:
            let halfLen = diamondHalfLength(strokeWidth: w)
            let halfWid = max(w * 1.4, 3.5) + 1
            let base = CGPoint(x: tip.x - directionX * halfLen * 2, y: tip.y - directionY * halfLen * 2)
            let mid = CGPoint(x: tip.x - directionX * halfLen, y: tip.y - directionY * halfLen)
            let left = CGPoint(x: mid.x + px * halfWid, y: mid.y + py * halfWid)
            let right = CGPoint(x: mid.x - px * halfWid, y: mid.y - py * halfWid)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: left)
            path.line(to: base)
            path.line(to: right)
            path.close()
            return path
        case .openArrow, .openArrowWide:
            let wide = (cap == .openArrowWide)
            let length = openArrowLength(strokeWidth: w, wide: wide)
            let width = openArrowWidth(strokeWidth: w, wide: wide)
            let base = CGPoint(x: tip.x - directionX * length, y: tip.y - directionY * length)
            let left = CGPoint(x: base.x + px * width / 2, y: base.y + py * width / 2)
            let right = CGPoint(x: base.x - px * width / 2, y: base.y - py * width / 2)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: left)
            path.line(to: right)
            path.close()
            return path
        case .arrow, .hollowArrow:
            let length = arrowheadLength(strokeWidth: w)
            let width = arrowheadWidth(strokeWidth: w)
            let base = CGPoint(x: tip.x - directionX * length, y: tip.y - directionY * length)
            let left = CGPoint(x: base.x + px * width / 2, y: base.y + py * width / 2)
            let right = CGPoint(x: base.x - px * width / 2, y: base.y - py * width / 2)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: left)
            path.line(to: right)
            path.close()
            return path
        }
    }

    /// Miniature full-arrow preview (start + shaft + end) for the caps Switch rows.
    /// Ornaments are hard-capped to the row height so the top half doesn’t dwarf the plain bottom line.
    static func drawCapsPairPreview(
        _ caps: ArrowCaps,
        in rect: CGRect,
        color: NSColor,
        strokeWidth: CGFloat = 1.35
    ) {
        guard rect.width > 4, rect.height > 2 else { return }
        let y = rect.midY
        let pad: CGFloat = 1.5
        let left = CGPoint(x: rect.minX + pad, y: y)
        let right = CGPoint(x: rect.maxX - pad, y: y)
        // Keep glyphs inside the row: ~half the row height max.
        let sw = min(strokeWidth, 1.25)
        let tipLen = min(3.2, rect.height * 0.55)
        let tipWid = min(3.0, rect.height * 0.5)

        color.setStroke()
        color.setFill()

        let startInset = miniatureCapInset(caps.start, tipLen: tipLen)
        let endInset = miniatureCapInset(caps.end, tipLen: tipLen)
        var shaftStart = left
        var shaftEnd = right
        if startInset > 0 { shaftStart = CGPoint(x: left.x + startInset, y: y) }
        if endInset > 0 { shaftEnd = CGPoint(x: right.x - endInset, y: y) }

        if shaftEnd.x - shaftStart.x > 0.5 {
            let path = NSBezierPath()
            path.move(to: shaftStart)
            path.line(to: shaftEnd)
            path.lineWidth = sw
            path.lineCapStyle = .butt
            path.stroke()
        }

        drawMiniatureCap(caps.start, tip: left, pointingRight: false, tipLen: tipLen, tipWid: tipWid, stroke: sw, color: color)
        drawMiniatureCap(caps.end, tip: right, pointingRight: true, tipLen: tipLen, tipWid: tipWid, stroke: sw, color: color)
    }

    private static func miniatureCapInset(_ cap: ArrowCapStyle, tipLen: CGFloat) -> CGFloat {
        switch cap {
        case .none, .bar, .openArrow, .openArrowWide: return 0
        case .circle: return tipLen * 0.45
        case .diamond: return tipLen
        case .arrow, .hollowArrow: return tipLen * 0.85
        }
    }

    private static func drawMiniatureCap(
        _ cap: ArrowCapStyle,
        tip: CGPoint,
        pointingRight: Bool,
        tipLen: CGFloat,
        tipWid: CGFloat,
        stroke: CGFloat,
        color: NSColor
    ) {
        let ux: CGFloat = pointingRight ? 1 : -1
        let y = tip.y
        color.setStroke()
        color.setFill()

        switch cap {
        case .none:
            break
        case .bar:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: tip.x, y: y + tipWid / 2))
            path.line(to: CGPoint(x: tip.x, y: y - tipWid / 2))
            path.lineWidth = stroke
            path.lineCapStyle = .butt
            path.stroke()
        case .circle:
            let r = tipWid * 0.4
            let c = CGPoint(x: tip.x - ux * r, y: y)
            NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        case .diamond:
            let half = tipLen * 0.5
            let mid = CGPoint(x: tip.x - ux * half, y: y)
            let base = CGPoint(x: tip.x - ux * tipLen, y: y)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: mid.x, y: y + tipWid / 2))
            path.line(to: base)
            path.line(to: CGPoint(x: mid.x, y: y - tipWid / 2))
            path.close()
            path.fill()
        case .openArrow, .openArrowWide:
            let base = CGPoint(x: tip.x - ux * tipLen, y: y)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: base.x, y: y + tipWid / 2))
            path.line(to: tip)
            path.line(to: CGPoint(x: base.x, y: y - tipWid / 2))
            path.lineWidth = stroke
            path.lineJoinStyle = .miter
            path.lineCapStyle = .butt
            path.stroke()
        case .arrow:
            let base = CGPoint(x: tip.x - ux * tipLen, y: y)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: base.x, y: y + tipWid / 2))
            path.line(to: CGPoint(x: base.x, y: y - tipWid / 2))
            path.close()
            path.fill()
        case .hollowArrow:
            let base = CGPoint(x: tip.x - ux * tipLen, y: y)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: base.x, y: y + tipWid / 2))
            path.line(to: CGPoint(x: base.x, y: y - tipWid / 2))
            path.close()
            path.lineWidth = stroke
            path.lineJoinStyle = .miter
            path.stroke()
        }
    }

    /// Draw a compact horizontal preview of `cap` for toolbar / menu icons.
    /// Short stub + small tip with padding — not a full-width shaft like the body line-style pill.
    static func drawCapPreview(
        _ cap: ArrowCapStyle,
        in rect: CGRect,
        pointingLeft: Bool,
        color: NSColor,
        strokeWidth: CGFloat = 2
    ) {
        guard rect.width > 4, rect.height > 4 else { return }

        let y = rect.midY
        let sw = min(max(strokeWidth, 1.2), 1.6)
        // Fixed glyph budget inside `rect` (caller already insets for chip padding).
        let tipLen: CGFloat = min(6.5, rect.width * 0.38)
        let stubLen: CGFloat = min(8.5, max(rect.width - tipLen - 1, 5))
        let total = stubLen + tipLen
        let originX = rect.midX - total / 2

        let tipX: CGFloat
        let stubFarX: CGFloat
        let joinX: CGFloat
        let ux: CGFloat
        if pointingLeft {
            tipX = originX
            joinX = originX + tipLen
            stubFarX = joinX + stubLen
            ux = -1
        } else {
            stubFarX = originX
            joinX = originX + stubLen
            tipX = joinX + tipLen
            ux = 1
        }

        let tip = CGPoint(x: tipX, y: y)
        let far = CGPoint(x: stubFarX, y: y)
        let join = CGPoint(x: joinX, y: y)

        color.setStroke()
        color.setFill()

        // Stub only (short) — never spans the whole chip.
        let stub = NSBezierPath()
        stub.move(to: far)
        stub.line(to: join)
        stub.lineWidth = sw
        stub.lineCapStyle = .butt
        stub.stroke()

        // Tip ornaments stay inside tipLen × modest height (breathing room).
        let halfH = min(rect.height * 0.32, 3.2)
        let slot = tipLen

        switch cap {
        case .none:
            let ext = NSBezierPath()
            ext.move(to: join)
            ext.line(to: tip)
            ext.lineWidth = sw
            ext.lineCapStyle = .butt
            ext.stroke()

        case .bar:
            let bridge = NSBezierPath()
            bridge.move(to: join)
            bridge.line(to: tip)
            bridge.lineWidth = sw
            bridge.lineCapStyle = .butt
            bridge.stroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: tipX, y: y + halfH))
            path.line(to: CGPoint(x: tipX, y: y - halfH))
            path.lineWidth = sw
            path.lineCapStyle = .butt
            path.stroke()

        case .circle:
            let r = min(halfH, slot * 0.42)
            let c = CGPoint(x: tipX - ux * r, y: y)
            let bridgeEnd = CGPoint(x: c.x - ux * r, y: y)
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: bridgeEnd)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()

        case .diamond:
            let halfLen = min(slot * 0.45, 3.2)
            let halfWid = halfH * 0.9
            let mid = CGPoint(x: tipX - ux * halfLen, y: y)
            let base = CGPoint(x: tipX - ux * halfLen * 2, y: y)
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: base)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: mid.x, y: y + halfWid))
            path.line(to: base)
            path.line(to: CGPoint(x: mid.x, y: y - halfWid))
            path.close()
            path.fill()

        case .openArrow, .openArrowWide:
            let length = min(slot * 0.85, 5.5)
            let width = halfH * 1.7
            let base = CGPoint(x: tipX - ux * length, y: y)
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: tip)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: base.x, y: y + width / 2))
            path.line(to: tip)
            path.line(to: CGPoint(x: base.x, y: y - width / 2))
            path.lineWidth = sw
            path.lineJoinStyle = .miter
            path.lineCapStyle = .butt
            path.stroke()

        case .arrow:
            let length = min(slot * 0.88, 5.5)
            let width = halfH * 1.55
            let base = CGPoint(x: tipX - ux * length, y: y)
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: base)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: base.x, y: y + width / 2))
            path.line(to: CGPoint(x: base.x, y: y - width / 2))
            path.close()
            path.fill()

        case .hollowArrow:
            let length = min(slot * 0.88, 5.5)
            let width = halfH * 1.55
            let base = CGPoint(x: tipX - ux * length, y: y)
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: base)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: base.x, y: y + width / 2))
            path.line(to: CGPoint(x: base.x, y: y - width / 2))
            path.close()
            path.lineWidth = max(sw * 0.9, 1)
            path.lineJoinStyle = .miter
            path.stroke()
        }
    }

    private static func drawPencil(points: [CGPoint], style: AnnotationStyle) {
        guard let first = points.first else { return }
        if points.count == 1 {
            let r = max(style.strokeWidth / 2, 0.5)
            style.strokeColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2)).fill()
            return
        }
        let path = NSBezierPath()
        path.move(to: first)
        for p in points.dropFirst() {
            path.line(to: p)
        }
        // Round caps/joins suit freehand; dash still reuses StrokeLineStyle.
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.lineWidth = style.strokeWidth
        let dash = style.lineStyle.dashPattern(strokeWidth: style.strokeWidth)
        if dash.isEmpty {
            path.setLineDash(nil, count: 0, phase: 0)
        } else {
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        style.strokeColor.setStroke()
        path.stroke()
    }

    /// Gaussian-blur the backdrop under a freehand brush or region mask (P4).
    private static func drawMosaic(
        geometry: MosaicGeometry,
        style: MosaicStyle,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext?
    ) {
        let intensity = MosaicStyle.clampedIntensity(style.intensity)
        let radius = MosaicStyle.blurRadiusPoints(forIntensity: intensity)

        switch geometry {
        case .stroke(let localPoints):
            guard !localPoints.isEmpty else { return }
            let brush = max(style.brushWidth, 1)
            guard let sample else {
                let offset = localPoints.map { CGPoint(x: $0.x + drawOrigin.x, y: $0.y + drawOrigin.y) }
                drawMosaicFallbackStroke(points: offset, brushWidth: brush)
                return
            }
            let pad = brush / 2 + radius * 2
            let hull = Annotation.bounds(of: localPoints).insetBy(dx: -pad, dy: -pad)
            drawBlurredMask(
                localMask: mosaicStrokeMask(localPoints: localPoints, brushWidth: brush),
                localHull: hull,
                radius: radius,
                drawOrigin: drawOrigin,
                sample: sample
            ) {
                let offset = localPoints.map { CGPoint(x: $0.x + drawOrigin.x, y: $0.y + drawOrigin.y) }
                drawMosaicFallbackStroke(points: offset, brushWidth: brush)
            }

        case .region(let mode, let localRect):
            guard localRect.width >= 1, localRect.height >= 1 else { return }
            guard let sample else {
                drawMosaicFallbackRegion(rect: localRect.offsetBy(dx: drawOrigin.x, dy: drawOrigin.y), mode: mode)
                return
            }
            let pad = radius * 2
            let hull = localRect.insetBy(dx: -pad, dy: -pad)
            let mask: NSBezierPath
            switch mode {
            case .ellipse:
                mask = NSBezierPath(ovalIn: localRect)
            case .rectangle, .freehand:
                mask = NSBezierPath(rect: localRect)
            }
            drawBlurredMask(
                localMask: mask,
                localHull: hull,
                radius: radius,
                drawOrigin: drawOrigin,
                sample: sample
            ) {
                drawMosaicFallbackRegion(
                    rect: localRect.offsetBy(dx: drawOrigin.x, dy: drawOrigin.y),
                    mode: mode
                )
            }
        }
    }

    private static func drawBlurredMask(
        localMask: NSBezierPath,
        localHull: CGRect,
        radius: CGFloat,
        drawOrigin: CGPoint,
        sample: MosaicSampleContext,
        fallback: () -> Void
    ) {
        guard localHull.width >= 1, localHull.height >= 1 else { return }
        let imageBounds = CGRect(origin: .zero, size: sample.image.size)
        let sampleHull = localHull.offsetBy(
            dx: sample.selectionOriginInImage.x,
            dy: sample.selectionOriginInImage.y
        )
        let crop = sampleHull.intersection(imageBounds)
        guard crop.width >= 1, crop.height >= 1 else { return }

        guard let blurred = blurredCrop(from: sample.image, crop: crop, radius: radius) else {
            fallback()
            return
        }

        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }

        let mask = localMask.copy() as? NSBezierPath ?? localMask
        let transform = AffineTransform(translationByX: drawOrigin.x, byY: drawOrigin.y)
        mask.transform(using: transform)
        mask.addClip()

        let drawRect = crop.offsetBy(
            dx: drawOrigin.x - sample.selectionOriginInImage.x,
            dy: drawOrigin.y - sample.selectionOriginInImage.y
        )
        blurred.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private static func drawMosaicFallbackStroke(points: [CGPoint], brushWidth: CGFloat) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        if points.count == 1 {
            let r = brushWidth / 2
            path.appendOval(in: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2))
            NSColor.black.withAlphaComponent(0.18).setFill()
            path.fill()
            return
        }
        path.move(to: first)
        for p in points.dropFirst() { path.line(to: p) }
        path.lineWidth = brushWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        NSColor.black.withAlphaComponent(0.18).setStroke()
        path.stroke()
    }

    private static func drawMosaicFallbackRegion(rect: CGRect, mode: MosaicDrawMode) {
        let path: NSBezierPath
        switch mode {
        case .ellipse:
            path = NSBezierPath(ovalIn: rect)
        case .rectangle, .freehand:
            path = NSBezierPath(rect: rect)
        }
        NSColor.black.withAlphaComponent(0.18).setFill()
        path.fill()
    }

    private static func mosaicStrokeMask(localPoints: [CGPoint], brushWidth: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = localPoints.first else { return path }
        if localPoints.count == 1 {
            let r = brushWidth / 2
            path.appendOval(in: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2))
            return path
        }
        path.move(to: first)
        for p in localPoints.dropFirst() { path.line(to: p) }
        let stroked = path.cgPath.copy(
            strokingWithWidth: brushWidth,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        )
        return NSBezierPath(cgPath: stroked)
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static func blurredCrop(
        from image: NSImage,
        crop: CGRect,
        radius: CGFloat
    ) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let pixelScale = (scaleX + scaleY) / 2
        let pixelCrop = CGRect(
            x: crop.minX * scaleX,
            y: (image.size.height - crop.maxY) * scaleY,
            width: crop.width * scaleX,
            height: crop.height * scaleY
        ).integral
        guard pixelCrop.width >= 1, pixelCrop.height >= 1,
              let cropped = cgImage.cropping(to: pixelCrop)
        else { return nil }

        let ci = CIImage(cgImage: cropped)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ci, forKey: kCIInputImageKey)
        filter?.setValue(radius * pixelScale, forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage?.cropped(to: ci.extent),
              let outCG = ciContext.createCGImage(output, from: ci.extent)
        else { return nil }

        return NSImage(cgImage: outCG, size: crop.size)
    }

    private static func drawText(string: String, style: TextStyle, in rect: CGRect) {
        let display = string.isEmpty ? " " : string
        let attributed = NSAttributedString(string: display, attributes: style.attributes())
        let pad = style.textPadding

        if style.hasBackground {
            let bg = contrastingBackground(for: style.color)
            bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }

        let textRect = rect.insetBy(dx: pad, dy: pad)
        // Wrap to the mark’s width (must match the field editor / commit sizing).
        attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    /// Light plate behind dark ink; dark plate behind light ink.
    private static func contrastingBackground(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.55
            ? NSColor.black.withAlphaComponent(0.55)
            : NSColor.white.withAlphaComponent(0.85)
    }

    private static func applyStroke(_ style: AnnotationStyle, to path: NSBezierPath) {
        path.lineWidth = style.strokeWidth
        path.lineJoinStyle = .miter
        // Butt caps keep dash segments as rectangles (Snipaste-style).
        path.lineCapStyle = .butt
        let dash = style.lineStyle.dashPattern(strokeWidth: style.strokeWidth)
        if dash.isEmpty {
            path.setLineDash(nil, count: 0, phase: 0)
        } else {
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
    }

    static func drawHandles(in rect: CGRect, size: CGFloat, accent: NSColor) {
        let centers: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
        ]
        for c in centers {
            let r = CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(rect: r).fill()
            accent.setStroke()
            let stroke = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
            stroke.lineWidth = 1
            stroke.stroke()
        }
    }

    /// Snipaste-style square endpoint handles (start filled, end hollow).
    static func drawArrowEndpointHandles(
        start: CGPoint,
        end: CGPoint,
        size: CGFloat,
        accent: NSColor
    ) {
        let half = size / 2
        // Start: filled accent square.
        let startRect = CGRect(x: start.x - half, y: start.y - half, width: size, height: size)
        accent.setFill()
        NSBezierPath(rect: startRect).fill()
        NSColor.white.setStroke()
        let startStroke = NSBezierPath(rect: startRect.insetBy(dx: 0.5, dy: 0.5))
        startStroke.lineWidth = 1
        startStroke.stroke()

        // End: hollow white square with accent border.
        let endRect = CGRect(x: end.x - half, y: end.y - half, width: size, height: size)
        NSColor.white.setFill()
        NSBezierPath(rect: endRect).fill()
        accent.setStroke()
        let endStroke = NSBezierPath(rect: endRect.insetBy(dx: 0.5, dy: 0.5))
        endStroke.lineWidth = 1
        endStroke.stroke()
    }

    /// Distance from `point` to the polyline (selection-local). Used for pencil hit-testing.
    static func distance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return .greatestFiniteMagnitude }
        guard points.count > 1 else { return hypot(point.x - first.x, point.y - first.y) }
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0..<(points.count - 1) {
            best = min(best, distance(from: point, toSegment: points[i], points[i + 1]))
        }
        return best
    }

    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSq = dx * dx + dy * dy
        if lengthSq < 0.0001 {
            return hypot(point.x - a.x, point.y - a.y)
        }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSq))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - proj.x, point.y - proj.y)
    }

    /// Hit-test arrow shaft + end caps (selection-local).
    static func hitsArrow(
        point: CGPoint,
        start: CGPoint,
        end: CGPoint,
        style: AnnotationStyle,
        caps: ArrowCaps,
        tolerance: CGFloat
    ) -> Bool {
        if distance(from: point, toSegment: start, end) <= tolerance {
            return true
        }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return false }
        let ux = dx / length
        let uy = dy / length

        if hitsCap(caps.start, tip: start, directionX: -ux, directionY: -uy, style: style, point: point, tolerance: tolerance) {
            return true
        }
        if hitsCap(caps.end, tip: end, directionX: ux, directionY: uy, style: style, point: point, tolerance: tolerance) {
            return true
        }
        return false
    }

    private static func hitsCap(
        _ cap: ArrowCapStyle,
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        style: AnnotationStyle,
        point: CGPoint,
        tolerance: CGFloat
    ) -> Bool {
        switch cap {
        case .none:
            return false
        case .bar:
            let half = max(style.strokeWidth * 1.6, 4) + 2
            let px = -directionY
            let py = directionX
            let a = CGPoint(x: tip.x + px * half, y: tip.y + py * half)
            let b = CGPoint(x: tip.x - px * half, y: tip.y - py * half)
            return distance(from: point, toSegment: a, b) <= tolerance
        case .circle, .diamond, .openArrow, .openArrowWide, .arrow, .hollowArrow:
            guard let path = capHitPath(
                cap,
                tip: tip,
                directionX: directionX,
                directionY: directionY,
                strokeWidth: style.strokeWidth
            ) else { return false }
            return path.contains(point)
        }
    }
}

/// Cursors for annotate hit zones (draw / move / resize).
enum AnnotationCursors {
    /// System four-arrow “move” cursor (thin; hotspot at center so it doesn’t cover the target).
    /// Loaded from HIServices — do not call private `NSCursor._moveCursor` (aborts on macOS 15+).
    static let move: NSCursor = hiServicesMoveCursor() ?? drawnMoveCursor()

    /// White “＋” used inside the selection / annotation interior (shape draw mode).
    static let whitePlus: NSCursor = {
        let size: CGFloat = 24
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let mid = NSPoint(x: rect.midX, y: rect.midY)
            let arm: CGFloat = 8
            let line = NSBezierPath()
            line.move(to: NSPoint(x: mid.x - arm, y: mid.y))
            line.line(to: NSPoint(x: mid.x + arm, y: mid.y))
            line.move(to: NSPoint(x: mid.x, y: mid.y - arm))
            line.line(to: NSPoint(x: mid.x, y: mid.y + arm))
            line.lineCapStyle = .round

            // Dark halo so it stays visible on light screenshots.
            line.lineWidth = 4
            NSColor.black.withAlphaComponent(0.55).setStroke()
            line.stroke()

            line.lineWidth = 2
            NSColor.white.setStroke()
            line.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }()

    /// Transparent cursor while pencil is stroking (Snipaste: crosshair vanishes; only the ink shows).
    static let hidden: NSCursor = {
        let image = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }
        return NSCursor(image: image, hotSpot: .zero)
    }()

    private static var pencilCrosshairCache: (key: UInt64, cursor: NSCursor)?
    private static var mosaicCrosshairCache: (key: Int, cursor: NSCursor)?

    /// Brush outline matching actual diameter (no artificial cap that hid size changes).
    static func mosaicCrosshair(brushWidth: CGFloat) -> NSCursor {
        let diameter = max(brushWidth, 8)
        let key = Int((diameter * 2).rounded()) // half-point precision
        if let cache = mosaicCrosshairCache, cache.key == key {
            return cache.cursor
        }
        let pad: CGFloat = 3
        let size = diameter + pad * 2
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let r = rect.insetBy(dx: pad, dy: pad)
            let path = NSBezierPath(ovalIn: r)
            path.lineWidth = 1.5
            NSColor.black.withAlphaComponent(0.45).setStroke()
            path.stroke()
            path.lineWidth = 1
            NSColor.white.setStroke()
            path.stroke()
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
        mosaicCrosshairCache = (key, cursor)
        return cursor
    }

    /// Snipaste-style pencil reticle: center dot + four short thin arms, tinted to stroke color.
    static func pencilCrosshair(color: NSColor) -> NSCursor {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        let key =
            (UInt64((rgb.redComponent * 255).rounded()) << 24)
            | (UInt64((rgb.greenComponent * 255).rounded()) << 16)
            | (UInt64((rgb.blueComponent * 255).rounded()) << 8)
            | UInt64((rgb.alphaComponent * 255).rounded())
        if let cache = pencilCrosshairCache, cache.key == key {
            return cache.cursor
        }
        let cursor = makePencilCrosshair(color: rgb)
        pencilCrosshairCache = (key, cursor)
        return cursor
    }

    private static func makePencilCrosshair(color: NSColor) -> NSCursor {
        let size: CGFloat = 23
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let mid = NSPoint(x: rect.midX, y: rect.midY)
            // Gap from center to each arm; arm length — keep hairline thin.
            let gap: CGFloat = 3
            let arm: CGFloat = 5
            let ink = color

            let arms = NSBezierPath()
            arms.move(to: NSPoint(x: mid.x - gap - arm, y: mid.y))
            arms.line(to: NSPoint(x: mid.x - gap, y: mid.y))
            arms.move(to: NSPoint(x: mid.x + gap, y: mid.y))
            arms.line(to: NSPoint(x: mid.x + gap + arm, y: mid.y))
            arms.move(to: NSPoint(x: mid.x, y: mid.y - gap - arm))
            arms.line(to: NSPoint(x: mid.x, y: mid.y - gap))
            arms.move(to: NSPoint(x: mid.x, y: mid.y + gap))
            arms.line(to: NSPoint(x: mid.x, y: mid.y + gap + arm))
            arms.lineCapStyle = .butt
            arms.lineWidth = 1

            // Hairline halo so cyan-on-cyan (etc.) still reads.
            arms.lineWidth = 2
            contrastingHalo(for: ink).setStroke()
            arms.stroke()
            arms.lineWidth = 1
            ink.setStroke()
            arms.stroke()

            let dotR: CGFloat = 1.1
            let dot = NSBezierPath(ovalIn: CGRect(
                x: mid.x - dotR,
                y: mid.y - dotR,
                width: dotR * 2,
                height: dotR * 2
            ))
            contrastingHalo(for: ink).setFill()
            NSBezierPath(ovalIn: CGRect(
                x: mid.x - dotR - 0.6,
                y: mid.y - dotR - 0.6,
                width: (dotR + 0.6) * 2,
                height: (dotR + 0.6) * 2
            )).fill()
            ink.setFill()
            dot.fill()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }

    private static func hiServicesMoveCursor() -> NSCursor? {
        let dir = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors/move"
        let info = NSDictionary(contentsOfFile: "\(dir)/info.plist")
        let hotx = (info?["hotx"] as? NSNumber)?.doubleValue ?? 9
        let hoty = (info?["hoty"] as? NSNumber)?.doubleValue ?? 9
        // Prefer PDF (vector); PNG is the 1x bitmap fallback Apple ships alongside it.
        let image =
            NSImage(contentsOfFile: "\(dir)/cursor.pdf")
            ?? NSImage(contentsOfFile: "\(dir)/cursor_1only_.png")
        guard let image else { return nil }
        // PDF page is 18×18pt with hotspot (9,9); keep natural size so hotspot stays centered.
        if abs(image.size.width - 18) > 0.5 || abs(image.size.height - 18) > 0.5 {
            image.size = NSSize(width: 18, height: 18)
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: hotx, y: hoty))
    }

    /// Drawn four-arrow fallback if HIServices assets are unavailable.
    private static func drawnMoveCursor() -> NSCursor {
        let size: CGFloat = 20
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let mid = NSPoint(x: rect.midX, y: rect.midY)
            let arm: CGFloat = 7
            let head: CGFloat = 3

            let path = NSBezierPath()
            // Cross
            path.move(to: NSPoint(x: mid.x - arm, y: mid.y))
            path.line(to: NSPoint(x: mid.x + arm, y: mid.y))
            path.move(to: NSPoint(x: mid.x, y: mid.y - arm))
            path.line(to: NSPoint(x: mid.x, y: mid.y + arm))
            // Arrow heads
            path.move(to: NSPoint(x: mid.x - arm + head, y: mid.y - head))
            path.line(to: NSPoint(x: mid.x - arm, y: mid.y))
            path.line(to: NSPoint(x: mid.x - arm + head, y: mid.y + head))
            path.move(to: NSPoint(x: mid.x + arm - head, y: mid.y - head))
            path.line(to: NSPoint(x: mid.x + arm, y: mid.y))
            path.line(to: NSPoint(x: mid.x + arm - head, y: mid.y + head))
            path.move(to: NSPoint(x: mid.x - head, y: mid.y - arm + head))
            path.line(to: NSPoint(x: mid.x, y: mid.y - arm))
            path.line(to: NSPoint(x: mid.x + head, y: mid.y - arm + head))
            path.move(to: NSPoint(x: mid.x - head, y: mid.y + arm - head))
            path.line(to: NSPoint(x: mid.x, y: mid.y + arm))
            path.line(to: NSPoint(x: mid.x + head, y: mid.y + arm - head))
            path.lineCapStyle = .round
            path.lineJoinStyle = .miter

            path.lineWidth = 3
            NSColor.black.withAlphaComponent(0.55).setStroke()
            path.stroke()
            path.lineWidth = 1.5
            NSColor.white.setStroke()
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }

    private static func contrastingHalo(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.55
            ? NSColor.black.withAlphaComponent(0.35)
            : NSColor.white.withAlphaComponent(0.45)
    }
}
