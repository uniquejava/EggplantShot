import AppKit
import CoreImage

// Shape draw.

extension AnnotationDrawing {
    static func drawShape(kind: ShapeKind, style: AnnotationStyle, in rect: CGRect) {
        let path: NSBezierPath
        switch kind {
        case .rectangle:
            path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        case .ellipse:
            path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        }

        if style.isFilled {
            style.strokeColor.setFill()
            path.fill()
        } else {
            applyStroke(style, to: path)
            style.strokeColor.setStroke()
            path.stroke()
        }
    }

}
