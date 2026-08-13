import AppKit

// Annotation payload + mark model (geometry helpers).

enum AnnotationPayload: Equatable {
    case shape(ShapeKind, rect: CGRect, style: AnnotationStyle)
    case arrow(start: CGPoint, end: CGPoint, style: AnnotationStyle, caps: ArrowCaps)
    case pencil(points: [CGPoint], style: AnnotationStyle)
    case marker(MosaicGeometry, style: MarkerStyle)
    case mosaic(MosaicGeometry, style: MosaicStyle)
    case eraser(MosaicGeometry, style: EraserStyle)
    case text(string: String, rect: CGRect, style: TextStyle)
    /// Sequence number centered at `center` (selection-local).
    case step(number: Int, center: CGPoint, style: StepStyle)
    /// Source sample rect + magnified lens rect (selection-local). Zoom = lens / source.
    case magnifier(kind: ShapeKind, source: CGRect, lens: CGRect, style: MagnifierStyle)
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

    /// Convenience for freehand marker / highlighter.
    init(id: UUID = UUID(), markerPoints points: [CGPoint], markerStyle: MarkerStyle) {
        self.id = id
        var style = markerStyle
        style.clamp()
        self.payload = .marker(.stroke(points: points), style: style)
    }

    /// Convenience for region marker (rect / oval).
    init(
        id: UUID = UUID(),
        markerRegion mode: MosaicDrawMode,
        rect: CGRect,
        markerStyle: MarkerStyle
    ) {
        self.id = id
        var style = markerStyle
        style.clamp()
        let kind: MosaicDrawMode = (mode == .ellipse) ? .ellipse : .rectangle
        self.payload = .marker(.region(kind, rect: rect), style: style)
    }

    /// Convenience for freehand eraser.
    init(id: UUID = UUID(), eraserPoints points: [CGPoint], eraserStyle: EraserStyle) {
        self.id = id
        var style = eraserStyle
        style.clamp()
        self.payload = .eraser(.stroke(points: points), style: style)
    }

    /// Convenience for region eraser (rect / oval).
    init(
        id: UUID = UUID(),
        eraserRegion mode: MosaicDrawMode,
        rect: CGRect,
        eraserStyle: EraserStyle
    ) {
        self.id = id
        var style = eraserStyle
        style.clamp()
        let kind: MosaicDrawMode = (mode == .ellipse) ? .ellipse : .rectangle
        self.payload = .eraser(.region(kind, rect: rect), style: style)
    }

    /// Convenience for the text tool.
    init(id: UUID = UUID(), string: String, rect: CGRect, style: TextStyle) {
        self.id = id
        self.payload = .text(string: string, rect: rect, style: style)
    }

    /// Convenience for the step / numbering tool.
    init(id: UUID = UUID(), number: Int, center: CGPoint, stepStyle: StepStyle) {
        self.id = id
        var style = stepStyle
        style.clamp()
        self.payload = .step(number: max(number, 1), center: center, style: style)
    }

    /// Convenience for the magnifier tool.
    init(
        id: UUID = UUID(),
        magnifierKind kind: ShapeKind,
        source: CGRect,
        lens: CGRect,
        magnifierStyle: MagnifierStyle
    ) {
        self.id = id
        var style = magnifierStyle
        style.clamp()
        self.payload = .magnifier(kind: kind, source: source, lens: lens, style: style)
    }

    /// Disk / tooling type discriminator (`"shape"`, `"pencil"`, `"mosaic"`, `"text"`, …).
    var typeName: String {
        switch payload {
        case .shape: return "shape"
        case .arrow: return "arrow"
        case .pencil: return "pencil"
        case .marker: return "marker"
        case .mosaic: return "mosaic"
        case .eraser: return "eraser"
        case .text: return "text"
        case .step: return "step"
        case .magnifier: return "magnifier"
        }
    }

    // MARK: Shared accessors

    /// Stroke style for shape / arrow / pencil. No-op get/set for mosaic / marker / eraser / text / step / magnifier marks.
    var style: AnnotationStyle {
        get {
            switch payload {
            case .shape(_, _, let style), .arrow(_, _, let style, _), .pencil(_, let style):
                return style
            case .marker, .mosaic, .eraser, .text, .step, .magnifier:
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
            case .marker, .mosaic, .eraser, .text, .step, .magnifier:
                break
            }
        }
    }

    var magnifierStyle: MagnifierStyle {
        get {
            if case .magnifier(_, _, _, let style) = payload { return style }
            return .default
        }
        set {
            guard case .magnifier(let kind, let source, let lens, _) = payload else { return }
            var style = newValue
            style.clamp()
            payload = .magnifier(kind: kind, source: source, lens: lens, style: style)
        }
    }

    var magnifierKind: ShapeKind {
        get {
            if case .magnifier(let kind, _, _, _) = payload { return kind }
            return .rectangle
        }
        set {
            guard case .magnifier(_, let source, let lens, let style) = payload else { return }
            payload = .magnifier(kind: newValue, source: source, lens: lens, style: style)
        }
    }

    var magnifierSource: CGRect {
        get {
            if case .magnifier(_, let source, _, _) = payload { return source }
            return .null
        }
        set {
            guard case .magnifier(let kind, _, let lens, let style) = payload else { return }
            payload = .magnifier(kind: kind, source: newValue, lens: lens, style: style)
        }
    }

    var magnifierLens: CGRect {
        get {
            if case .magnifier(_, _, let lens, _) = payload { return lens }
            return .null
        }
        set {
            guard case .magnifier(let kind, let source, _, let style) = payload else { return }
            payload = .magnifier(kind: kind, source: source, lens: newValue, style: style)
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

    var markerStyle: MarkerStyle {
        get {
            if case .marker(_, let style) = payload { return style }
            return .default
        }
        set {
            guard case .marker(let geometry, _) = payload else { return }
            var style = newValue
            style.clamp()
            payload = .marker(geometry, style: style)
        }
    }

    var markerGeometry: MosaicGeometry? {
        get {
            if case .marker(let geometry, _) = payload { return geometry }
            return nil
        }
        set {
            guard let newValue, case .marker(_, let style) = payload else { return }
            payload = .marker(newValue, style: style)
        }
    }

    var isMarkerStroke: Bool {
        if case .marker(.stroke, _) = payload { return true }
        return false
    }

    var isMarkerRegion: Bool {
        if case .marker(.region, _) = payload { return true }
        return false
    }

    var eraserStyle: EraserStyle {
        get {
            if case .eraser(_, let style) = payload { return style }
            return .default
        }
        set {
            guard case .eraser(let geometry, _) = payload else { return }
            var style = newValue
            style.clamp()
            payload = .eraser(geometry, style: style)
        }
    }

    var eraserGeometry: MosaicGeometry? {
        get {
            if case .eraser(let geometry, _) = payload { return geometry }
            return nil
        }
        set {
            guard let newValue, case .eraser(_, let style) = payload else { return }
            payload = .eraser(newValue, style: style)
        }
    }

    var isEraserStroke: Bool {
        if case .eraser(.stroke, _) = payload { return true }
        return false
    }

    var isEraserRegion: Bool {
        if case .eraser(.region, _) = payload { return true }
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

    var stepStyle: StepStyle {
        get {
            if case .step(_, _, let style) = payload { return style }
            return .default
        }
        set {
            guard case .step(let number, let center, _) = payload else { return }
            var style = newValue
            style.clamp()
            payload = .step(number: number, center: center, style: style)
        }
    }

    var stepNumber: Int {
        get {
            if case .step(let number, _, _) = payload { return number }
            return 0
        }
        set {
            guard case .step(_, let center, let style) = payload else { return }
            payload = .step(number: max(newValue, 1), center: center, style: style)
        }
    }

    var stepCenter: CGPoint {
        get {
            if case .step(_, let center, _) = payload { return center }
            return .zero
        }
        set {
            guard case .step(let number, _, let style) = payload else { return }
            payload = .step(number: number, center: newValue, style: style)
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
        case .marker(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                let hull = Self.bounds(of: points)
                let pad = style.brushWidth / 2
                return hull.insetBy(dx: -pad, dy: -pad)
            case .region(_, let rect):
                return rect
            }
        case .mosaic(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                let hull = Self.bounds(of: points)
                let pad = style.brushWidth / 2
                return hull.insetBy(dx: -pad, dy: -pad)
            case .region(_, let rect):
                return rect
            }
        case .eraser(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                let hull = Self.bounds(of: points)
                let pad = style.brushWidth / 2
                return hull.insetBy(dx: -pad, dy: -pad)
            case .region(_, let rect):
                return rect
            }
        case .step(_, let center, let style):
            return style.bounds(around: center)
        case .magnifier(_, let source, let lens, let style):
            let pad = style.strokeWidth / 2
            return source.union(lens).insetBy(dx: -pad, dy: -pad)
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

    var isMarker: Bool {
        if case .marker = payload { return true }
        return false
    }

    var isMosaic: Bool {
        if case .mosaic = payload { return true }
        return false
    }

    var isEraser: Bool {
        if case .eraser = payload { return true }
        return false
    }

    var isText: Bool {
        if case .text = payload { return true }
        return false
    }

    var isStep: Bool {
        if case .step = payload { return true }
        return false
    }

    var isMagnifier: Bool {
        if case .magnifier = payload { return true }
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
            case .arrow, .pencil, .marker, .mosaic, .eraser, .step, .magnifier:
                break
            }
        }
    }

    var points: [CGPoint] {
        get {
            switch payload {
            case .pencil(let points, _):
                return points
            case .marker(.stroke(let points), _), .mosaic(.stroke(let points), _),
                 .eraser(.stroke(let points), _):
                return points
            default:
                return []
            }
        }
        set {
            switch payload {
            case .pencil(_, let style):
                payload = .pencil(points: newValue, style: style)
            case .marker(.stroke, let style):
                payload = .marker(.stroke(points: newValue), style: style)
            case .mosaic(.stroke, let style):
                payload = .mosaic(.stroke(points: newValue), style: style)
            case .eraser(.stroke, let style):
                payload = .eraser(.stroke(points: newValue), style: style)
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
        case .marker(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                let moved = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
                payload = .marker(.stroke(points: moved), style: style)
            case .region(let mode, let rect):
                payload = .marker(
                    .region(mode, rect: rect.offsetBy(dx: delta.width, dy: delta.height)),
                    style: style
                )
            }
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
        case .eraser(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                let moved = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
                payload = .eraser(.stroke(points: moved), style: style)
            case .region(let mode, let rect):
                payload = .eraser(
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
        case .step(let number, let center, let style):
            payload = .step(
                number: number,
                center: CGPoint(x: center.x + delta.width, y: center.y + delta.height),
                style: style
            )
        case .magnifier(let kind, let source, let lens, let style):
            payload = .magnifier(
                kind: kind,
                source: source.offsetBy(dx: delta.width, dy: delta.height),
                lens: lens.offsetBy(dx: delta.width, dy: delta.height),
                style: style
            )
        }
    }

    /// Moves only the source or lens frame of a magnifier mark.
    mutating func translateMagnifierPart(_ part: MagnifierPart, by delta: CGSize) {
        guard case .magnifier(let kind, let source, let lens, let style) = payload else { return }
        switch part {
        case .source:
            payload = .magnifier(
                kind: kind,
                source: source.offsetBy(dx: delta.width, dy: delta.height),
                lens: lens,
                style: style
            )
        case .lens:
            payload = .magnifier(
                kind: kind,
                source: source,
                lens: lens.offsetBy(dx: delta.width, dy: delta.height),
                style: style
            )
        }
    }

    /// Resizes only the source or lens frame (selection-local).
    mutating func mapMagnifierPart(_ part: MagnifierPart, to newBounds: CGRect) {
        guard case .magnifier(let kind, let source, let lens, let style) = payload else { return }
        switch part {
        case .source:
            payload = .magnifier(kind: kind, source: newBounds, lens: lens, style: style)
        case .lens:
            payload = .magnifier(kind: kind, source: source, lens: newBounds, style: style)
        }
    }

    /// Resizes the lens; source scales proportionally about its center so `style.scale` stays fixed.
    mutating func resizeMagnifierLens(to newLens: CGRect) {
        guard case .magnifier(let kind, let source, _, let style) = payload else { return }
        let syncedSource = Self.scaledMagnifierSource(
            lens: newLens,
            scale: style.scale,
            center: CGPoint(x: source.midX, y: source.midY)
        )
        payload = .magnifier(kind: kind, source: syncedSource, lens: newLens, style: style)
    }

    /// Average width/height zoom of lens vs source (clamped to `MagnifierStyle.scaleRange`).
    /// Used only as a fallback when a stored `scale` is missing (legacy disk records).
    static func magnifierScale(source: CGRect, lens: CGRect) -> CGFloat {
        guard source.width > 0.5, source.height > 0.5 else { return MagnifierStyle.defaultScale }
        let sx = lens.width / source.width
        let sy = lens.height / source.height
        return MagnifierStyle.clampedScale((sx + sy) / 2)
    }

    /// Concentric lens around `source` at `scale` (default `MagnifierStyle.defaultScale`).
    static func concentricMagnifierLens(for source: CGRect, scale: CGFloat = MagnifierStyle.defaultScale) -> CGRect {
        scaledMagnifierLens(
            source: source,
            scale: scale,
            center: CGPoint(x: source.midX, y: source.midY)
        )
    }

    /// Lens sized to `source * scale`, centered on `center` (keeps offset when slider changes).
    static func scaledMagnifierLens(source: CGRect, scale: CGFloat, center: CGPoint) -> CGRect {
        let s = MagnifierStyle.clampedScale(scale)
        let w = max(source.width * s, 1)
        let h = max(source.height * s, 1)
        return CGRect(
            x: center.x - w / 2,
            y: center.y - h / 2,
            width: w,
            height: h
        )
    }

    /// Source sized to `lens / scale`, centered on `center` (keeps sample focus when lens resizes).
    static func scaledMagnifierSource(lens: CGRect, scale: CGFloat, center: CGPoint) -> CGRect {
        let s = MagnifierStyle.clampedScale(scale)
        let w = max(lens.width / s, 1)
        let h = max(lens.height / s, 1)
        return CGRect(
            x: center.x - w / 2,
            y: center.y - h / 2,
            width: w,
            height: h
        )
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
        case .marker(let geometry, let style):
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
                payload = .marker(.stroke(points: mapped), style: style)
            case .region(let mode, _):
                payload = .marker(.region(mode, rect: newBounds), style: style)
            }
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
        case .eraser(let geometry, let style):
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
                payload = .eraser(.stroke(points: mapped), style: style)
            case .region(let mode, _):
                payload = .eraser(.region(mode, rect: newBounds), style: style)
            }
        case .text(let string, _, let style):
            payload = .text(string: string, rect: newBounds, style: style)
        case .step(let number, _, let style):
            // Steps keep aspect via center; resize chrome is disabled — keep center of newBounds.
            payload = .step(
                number: number,
                center: CGPoint(x: newBounds.midX, y: newBounds.midY),
                style: style
            )
        case .magnifier(let kind, let source, let lens, let style):
            // Dual-frame resize uses `mapMagnifierPart`; whole-bounds map keeps relative layout.
            let sx = newBounds.width / old.width
            let sy = newBounds.height / old.height
            let mappedSource = CGRect(
                x: newBounds.minX + (source.minX - old.minX) * sx,
                y: newBounds.minY + (source.minY - old.minY) * sy,
                width: source.width * sx,
                height: source.height * sy
            )
            let mappedLens = CGRect(
                x: newBounds.minX + (lens.minX - old.minX) * sx,
                y: newBounds.minY + (lens.minY - old.minY) * sy,
                width: lens.width * sx,
                height: lens.height * sy
            )
            payload = .magnifier(kind: kind, source: mappedSource, lens: mappedLens, style: style)
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

/// Ramer–Douglas–Peucker polyline simplify (mouse-up). Live sampling stays dense; commit drops near-colinear points.
