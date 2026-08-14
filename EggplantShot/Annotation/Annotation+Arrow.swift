import AppKit

extension Annotation {
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
}
