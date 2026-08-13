import AppKit

// Ramer–Douglas–Peucker polyline simplify (pencil mouse-up).

enum PolylineSimplifier {
    static func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2, epsilon > 0 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        simplifySegment(points, epsilon: epsilon, start: 0, end: points.count - 1, keep: &keep)
        return zip(points, keep).compactMap { point, keepFlag in keepFlag ? point : nil }
    }

    private static func simplifySegment(
        _ points: [CGPoint],
        epsilon: CGFloat,
        start: Int,
        end: Int,
        keep: inout [Bool]
    ) {
        guard end > start + 1 else { return }
        let a = points[start]
        let b = points[end]
        var maxDist: CGFloat = 0
        var maxIndex = start
        for i in (start + 1)..<end {
            let d = perpendicularDistance(points[i], segmentFrom: a, to: b)
            if d > maxDist {
                maxDist = d
                maxIndex = i
            }
        }
        if maxDist > epsilon {
            keep[maxIndex] = true
            simplifySegment(points, epsilon: epsilon, start: start, end: maxIndex, keep: &keep)
            simplifySegment(points, epsilon: epsilon, start: maxIndex, end: end, keep: &keep)
        }
    }

    private static func perpendicularDistance(_ p: CGPoint, segmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 1e-8 {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}

