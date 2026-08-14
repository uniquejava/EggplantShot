import AppKit
import CoreImage

// Pencil stroke draw.

extension AnnotationDrawing {
    static func drawPencil(points: [CGPoint], style: AnnotationStyle) {
        guard let first = points.first else { return }
        if points.count == 1 {
            let r = max(style.strokeWidth / 2, 0.5)
            style.strokeColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2)).fill()
            return
        }
        // Bulk `addLines` beats appending point by point — a long scribble is thousands of points
        // and the live draft rebuilds this path on every accepted sample.
        let cgPath = CGMutablePath()
        cgPath.addLines(between: points)
        let path = NSBezierPath(cgPath: cgPath)
        // Round caps/joins suit freehand; dash still reuses StrokeLineStyle.
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.lineWidth = style.strokeWidth
        let dash = style.lineStyle.dashPattern(strokeWidth: style.strokeWidth)
        if dash.isEmpty {
            path.setLineDash(nil, count: 0, phase: 0)
        } else {
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        style.strokeColor.setStroke()
        path.stroke()
    }
}
