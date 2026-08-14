import AppKit

extension Annotation {
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
}
