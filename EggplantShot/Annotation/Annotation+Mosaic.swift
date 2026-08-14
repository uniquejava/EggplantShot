import AppKit

extension Annotation {
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
}
