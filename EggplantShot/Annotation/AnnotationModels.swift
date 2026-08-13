import AppKit

/// Drawing tool selected on the refine toolbar. `.none` = refine selection only.
enum AnnotateTool: Equatable {
    case none
    case rectangle
    case pencil
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
    case pencil(points: [CGPoint], style: AnnotationStyle)
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

    /// Convenience for the pencil tool.
    init(id: UUID = UUID(), points: [CGPoint], style: AnnotationStyle) {
        self.id = id
        self.payload = .pencil(points: points, style: style)
    }

    /// Disk / tooling type discriminator (`"shape"`, `"pencil"`, …).
    var typeName: String {
        switch payload {
        case .shape: return "shape"
        case .pencil: return "pencil"
        }
    }

    // MARK: Shared accessors

    var style: AnnotationStyle {
        get {
            switch payload {
            case .shape(_, _, let style), .pencil(_, let style):
                return style
            }
        }
        set {
            switch payload {
            case .shape(let kind, let rect, _):
                payload = .shape(kind, rect: rect, style: newValue)
            case .pencil(let points, _):
                payload = .pencil(points: points, style: newValue)
            }
        }
    }

    /// Axis-aligned bounds in selection-local space (shape rect, or pencil path hull).
    var boundingRect: CGRect {
        switch payload {
        case .shape(_, let rect, _):
            return rect
        case .pencil(let points, _):
            return Self.bounds(of: points)
        }
    }

    var isShape: Bool {
        if case .shape = payload { return true }
        return false
    }

    var isPencil: Bool {
        if case .pencil = payload { return true }
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
            guard case .shape(let kind, _, let style) = payload else { return }
            payload = .shape(kind, rect: newValue, style: style)
        }
    }

    var points: [CGPoint] {
        get {
            if case .pencil(let points, _) = payload { return points }
            return []
        }
        set {
            guard case .pencil(_, let style) = payload else { return }
            payload = .pencil(points: newValue, style: style)
        }
    }

    // MARK: Geometry helpers

    mutating func translate(by delta: CGSize) {
        switch payload {
        case .shape(let kind, let rect, let style):
            payload = .shape(kind, rect: rect.offsetBy(dx: delta.width, dy: delta.height), style: style)
        case .pencil(let points, let style):
            let moved = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
            payload = .pencil(points: moved, style: style)
        }
    }

    /// Maps geometry so `boundingRect` becomes `newBounds` (used by resize handles).
    mutating func mapBoundingRect(to newBounds: CGRect) {
        let old = boundingRect
        guard old.width > 0, old.height > 0 else { return }
        switch payload {
        case .shape(let kind, _, let style):
            payload = .shape(kind, rect: newBounds, style: style)
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
        }
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
    /// Draw `annotation` with selection-local geometry offset by `origin` (selection frame origin in context).
    static func draw(_ annotation: Annotation, origin: CGPoint) {
        switch annotation.payload {
        case .shape(let kind, let localRect, let style):
            let rect = localRect.offsetBy(dx: origin.x, dy: origin.y)
            drawShape(kind: kind, style: style, in: rect)
        case .pencil(let points, let style):
            let offset = points.map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
            drawPencil(points: offset, style: style)
        }
    }

    /// Legacy entry used when the caller already converted a shape rect to context space.
    static func draw(_ annotation: Annotation, in rect: CGRect) {
        switch annotation.payload {
        case .shape(let kind, _, let style):
            drawShape(kind: kind, style: style, in: rect)
        case .pencil:
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

    private static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
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
}

/// Cursors for annotate hit zones (draw / move / resize).
enum AnnotationCursors {
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

    private static func contrastingHalo(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.55
            ? NSColor.black.withAlphaComponent(0.35)
            : NSColor.white.withAlphaComponent(0.45)
    }
}
