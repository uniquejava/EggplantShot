import AppKit

// Annotation payload + mark model (shared accessors). Tool-specific inits / geometry
// live in Annotation+{Tool}.swift so a new tool adds a payload case here plus one file.

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

    /// Shape kind. No-op get/set for non-shape payloads.
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
}
