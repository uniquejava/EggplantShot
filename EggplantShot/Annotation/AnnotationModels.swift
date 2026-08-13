import AppKit

/// Drawing tool selected on the refine toolbar. `.none` = refine selection only.
enum AnnotateTool: Equatable {
    case none
    case rectangle
}

/// Stroke / fill / color used when drawing or editing an annotation.
struct AnnotationStyle: Equatable {
    var strokeWidth: CGFloat
    var strokeColor: NSColor
    /// Filled body (sub-toolbar item 4). Mutually exclusive with stroke-width picks.
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

    static func save(style: AnnotationStyle, kind: ShapeKind) {
        let defaults = UserDefaults.standard
        defaults.set(Double(style.strokeWidth), forKey: strokeWidthKey)
        defaults.set(style.isFilled, forKey: isFilledKey)
        defaults.set(style.lineStyle.rawValue, forKey: lineStyleKey)
        defaults.set(PaletteColor.matching(style.strokeColor).rawValue, forKey: paletteKey)
        defaults.set(kind == .ellipse ? 1 : 0, forKey: kindKey)
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

/// Extensible mark payload. New tools add cases here without forking history/store.
enum AnnotationPayload: Equatable {
    case shape(ShapeKind, rect: CGRect, style: AnnotationStyle)
    // later: arrow, stroke (pen/marker), mosaic, text, step, …
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

    /// Convenience for the shape tool (only payload today).
    init(id: UUID = UUID(), kind: ShapeKind = .rectangle, rect: CGRect, style: AnnotationStyle) {
        self.id = id
        self.payload = .shape(kind, rect: rect, style: style)
    }

    /// Disk / tooling type discriminator (`"shape"`, later `"stroke"`, …).
    var typeName: String {
        switch payload {
        case .shape: return "shape"
        }
    }

    // MARK: Shape accessors (no-ops / defaults for non-shape payloads)

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
        get {
            if case .shape(_, let rect, _) = payload { return rect }
            return .null
        }
        set {
            guard case .shape(let kind, _, let style) = payload else { return }
            payload = .shape(kind, rect: newValue, style: style)
        }
    }

    var style: AnnotationStyle {
        get {
            if case .shape(_, _, let style) = payload { return style }
            return .default
        }
        set {
            guard case .shape(let kind, let rect, _) = payload else { return }
            payload = .shape(kind, rect: rect, style: newValue)
        }
    }

    var isShape: Bool {
        if case .shape = payload { return true }
        return false
    }
}

enum AnnotationDrawing {
    /// Stroke or fill an annotation into the current graphics context. `rect` is already in context space.
    static func draw(_ annotation: Annotation, in rect: CGRect) {
        switch annotation.payload {
        case .shape(let kind, _, let style):
            drawShape(kind: kind, style: style, in: rect)
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
            style.strokeColor.setStroke()
            path.stroke()
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
}

/// Cursors for annotate hit zones (draw / move / resize).
enum AnnotationCursors {
    /// White “＋” used inside the selection / annotation interior (draw mode).
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
}
