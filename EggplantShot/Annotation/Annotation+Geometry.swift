import AppKit

// Shared mark geometry: bounds, translate, resize-map.

extension Annotation {
    /// Rect / oval region of a paint mark (marker / mosaic / eraser). `nil` for freehand strokes
    /// and every other payload — those have no body to grab.
    var paintRegion: (mode: MosaicDrawMode, rect: CGRect)? {
        switch payload {
        case .marker(let geometry, _), .mosaic(let geometry, _), .eraser(let geometry, _):
            if case .region(let mode, let rect) = geometry {
                return (mode, rect)
            }
            return nil
        case .shape, .arrow, .pencil, .text, .step, .magnifier:
            return nil
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
            return geometry.boundingRect(brushWidth: style.brushWidth)
        case .mosaic(let geometry, let style):
            return geometry.boundingRect(brushWidth: style.brushWidth)
        case .eraser(let geometry, let style):
            return geometry.boundingRect(brushWidth: style.brushWidth)
        case .step(_, let center, let style):
            return style.bounds(around: center)
        case .magnifier(_, let source, let lens, let style):
            let pad = style.strokeWidth / 2
            return source.union(lens).insetBy(dx: -pad, dy: -pad)
        }
    }

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
            payload = .marker(geometry.translated(by: delta), style: style)
        case .mosaic(let geometry, let style):
            payload = .mosaic(geometry.translated(by: delta), style: style)
        case .eraser(let geometry, let style):
            payload = .eraser(geometry.translated(by: delta), style: style)
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
            guard let mapped = geometry.mapped(from: old, to: newBounds, brushWidth: style.brushWidth) else { return }
            payload = .marker(mapped, style: style)
        case .mosaic(let geometry, let style):
            guard let mapped = geometry.mapped(from: old, to: newBounds, brushWidth: style.brushWidth) else { return }
            payload = .mosaic(mapped, style: style)
        case .eraser(let geometry, let style):
            guard let mapped = geometry.mapped(from: old, to: newBounds, brushWidth: style.brushWidth) else { return }
            payload = .eraser(mapped, style: style)
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
