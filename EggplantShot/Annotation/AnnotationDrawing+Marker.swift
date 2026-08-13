import AppKit
import CoreImage

// Marker (highlighter) draw.

extension AnnotationDrawing {
    static func drawMarker(
        geometry: MosaicGeometry,
        style: MarkerStyle,
        drawOrigin: CGPoint
    ) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }

        ctx.compositingOperation = .sourceOver
        let fill = style.fillColor

        switch geometry {
        case .stroke(let localPoints):
            guard !localPoints.isEmpty else { return }
            let brush = max(style.brushWidth, 1)
            let offset = localPoints.map { CGPoint(x: $0.x + drawOrigin.x, y: $0.y + drawOrigin.y) }
            guard let first = offset.first else { return }
            let path = NSBezierPath()
            if offset.count == 1 {
                let r = brush / 2
                path.appendOval(in: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2))
                fill.setFill()
                path.fill()
                return
            }
            path.move(to: first)
            for p in offset.dropFirst() { path.line(to: p) }
            path.lineWidth = brush
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            fill.setStroke()
            path.stroke()

        case .region(let mode, let localRect):
            guard localRect.width >= 1, localRect.height >= 1 else { return }
            let rect = localRect.offsetBy(dx: drawOrigin.x, dy: drawOrigin.y)
            let path: NSBezierPath
            switch mode {
            case .ellipse:
                path = NSBezierPath(ovalIn: rect)
            case .rectangle, .freehand:
                path = NSBezierPath(rect: rect)
            }
            fill.setFill()
            path.fill()
        }
    }
}
