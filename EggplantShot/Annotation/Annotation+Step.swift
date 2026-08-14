import AppKit

extension Annotation {
    /// Convenience for the step / numbering tool.
    init(id: UUID = UUID(), number: Int, center: CGPoint, stepStyle: StepStyle) {
        self.id = id
        var style = stepStyle
        style.clamp()
        self.payload = .step(number: max(number, 1), center: center, style: style)
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
}
