import AppKit

extension Annotation {
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
}
