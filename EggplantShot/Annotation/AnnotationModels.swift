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
        strokeColor: PaletteColor.sky.color,
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

    static func load() -> (style: AnnotationStyle, kind: Annotation.Kind) {
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
        let kind: Annotation.Kind = defaults.integer(forKey: kindKey) == 1 ? .ellipse : .rectangle
        return (style, kind)
    }

    static func save(style: AnnotationStyle, kind: Annotation.Kind) {
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

/// Fixed Snipaste-like quick palette (2×8).
enum PaletteColor: Int, CaseIterable {
    case white, black, red, orange
    case yellow, lime, green, teal
    case cyan, sky, blue, indigo
    case purple, magenta, pink, brown

    var color: NSColor {
        switch self {
        case .white: return NSColor(calibratedWhite: 1, alpha: 1)
        case .black: return NSColor(calibratedWhite: 0.08, alpha: 1)
        case .red: return NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.22, alpha: 1)
        case .orange: return NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.15, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.12, alpha: 1)
        case .lime: return NSColor(calibratedRed: 0.65, green: 0.9, blue: 0.2, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.22, green: 0.78, blue: 0.35, alpha: 1)
        case .teal: return NSColor(calibratedRed: 0.15, green: 0.72, blue: 0.68, alpha: 1)
        case .cyan: return NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.95, alpha: 1)
        case .sky: return NSColor(calibratedRed: 0.35, green: 0.72, blue: 0.98, alpha: 1)
        case .blue: return NSColor(calibratedRed: 0.18, green: 0.45, blue: 0.95, alpha: 1)
        case .indigo: return NSColor(calibratedRed: 0.35, green: 0.3, blue: 0.85, alpha: 1)
        case .purple: return NSColor(calibratedRed: 0.62, green: 0.28, blue: 0.9, alpha: 1)
        case .magenta: return NSColor(calibratedRed: 0.9, green: 0.25, blue: 0.7, alpha: 1)
        case .pink: return NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.65, alpha: 1)
        case .brown: return NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.2, alpha: 1)
        }
    }

    static func matching(_ color: NSColor) -> PaletteColor {
        let target = color.usingColorSpace(.genericRGB) ?? color
        return allCases.min(by: { a, b in
            distance(a.color, target) < distance(b.color, target)
        }) ?? .sky
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

/// One drawable mark. Geometry is in **selection-local** Cocoa points
/// (origin = selection bottom-left).
struct Annotation: Equatable {
    enum Kind: Equatable {
        case rectangle
        case ellipse
    }

    let id: UUID
    var kind: Kind
    var rect: CGRect
    var style: AnnotationStyle

    init(id: UUID = UUID(), kind: Kind = .rectangle, rect: CGRect, style: AnnotationStyle) {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.style = style
    }
}

enum AnnotationDrawing {
    /// Stroke or fill an annotation into the current graphics context. `rect` is already in context space.
    static func draw(_ annotation: Annotation, in rect: CGRect) {
        let path: NSBezierPath
        switch annotation.kind {
        case .rectangle:
            path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        case .ellipse:
            path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        }

        if annotation.style.isFilled {
            annotation.style.strokeColor.setFill()
            path.fill()
        } else {
            path.lineWidth = annotation.style.strokeWidth
            path.lineJoinStyle = .miter
            // Butt caps keep dash segments as rectangles (Snipaste-style).
            path.lineCapStyle = .butt
            let dash = annotation.style.lineStyle.dashPattern(strokeWidth: annotation.style.strokeWidth)
            if dash.isEmpty {
                path.setLineDash(nil, count: 0, phase: 0)
            } else {
                path.setLineDash(dash, count: dash.count, phase: 0)
            }
            annotation.style.strokeColor.setStroke()
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
