import AppKit
import CoreImage

// Handles + geometry hit-testing.

extension AnnotationDrawing {
    static func drawHandles(in rect: CGRect, size: CGFloat) {
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
            // Hollow white square — keep freeze visible under the handle.
            NSColor.white.setStroke()
            let stroke = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
            stroke.lineWidth = 1
            stroke.stroke()
        }
    }

    /// Square endpoint handles (start / end); hollow white border so the freeze shows through.
    static func drawArrowEndpointHandles(
        start: CGPoint,
        end: CGPoint,
        size: CGFloat
    ) {
        let half = size / 2
        for center in [start, end] {
            let r = CGRect(x: center.x - half, y: center.y - half, width: size, height: size)
            NSColor.white.setStroke()
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

    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
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

    /// Hit-test arrow shaft + end caps (selection-local).
    static func hitsArrow(
        point: CGPoint,
        start: CGPoint,
        end: CGPoint,
        style: AnnotationStyle,
        caps: ArrowCaps,
        tolerance: CGFloat
    ) -> Bool {
        if distance(from: point, toSegment: start, end) <= tolerance {
            return true
        }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return false }
        let ux = dx / length
        let uy = dy / length

        if hitsCap(caps.start, tip: start, directionX: -ux, directionY: -uy, style: style, point: point, tolerance: tolerance) {
            return true
        }
        if hitsCap(caps.end, tip: end, directionX: ux, directionY: uy, style: style, point: point, tolerance: tolerance) {
            return true
        }
        return false
    }

    static func hitsCap(
        _ cap: ArrowCapStyle,
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        style: AnnotationStyle,
        point: CGPoint,
        tolerance: CGFloat
    ) -> Bool {
        switch cap {
        case .none:
            return false
        case .bar:
            let half = max(style.strokeWidth * 1.6, 4) + 2
            let px = -directionY
            let py = directionX
            let a = CGPoint(x: tip.x + px * half, y: tip.y + py * half)
            let b = CGPoint(x: tip.x - px * half, y: tip.y - py * half)
            return distance(from: point, toSegment: a, b) <= tolerance
        case .circle, .diamond, .openArrow, .openArrowWide, .arrow, .hollowArrow:
            guard let path = capHitPath(
                cap,
                tip: tip,
                directionX: directionX,
                directionY: directionY,
                strokeWidth: style.strokeWidth
            ) else { return false }
            return path.contains(point)
        }
    }
}
