import AppKit

extension Annotation {
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
}
