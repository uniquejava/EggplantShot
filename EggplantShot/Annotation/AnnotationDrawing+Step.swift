import AppKit
import CoreImage

// Step badge draw.

extension AnnotationDrawing {
    static func drawStep(number: Int, center: CGPoint, style: StepStyle) {
        let d = style.diameter
        let disk = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        let label = "\(number)"
        let font = style.makeFont()
        let digitColor: NSColor
        switch style.kind {
        case .filled:
            style.color.setFill()
            NSBezierPath(ovalIn: disk).fill()
            digitColor = .white
        case .outline:
            let stroke = max(d * 0.08, 1.25)
            let path = NSBezierPath(ovalIn: disk.insetBy(dx: stroke / 2, dy: stroke / 2))
            path.lineWidth = stroke
            style.color.setStroke()
            path.stroke()
            digitColor = style.color
        case .plain:
            digitColor = style.color
        }

        drawCenteredDigit(label, at: center, font: font, color: digitColor)
    }

    /// Digits look sunk if centered by `size(withAttributes:)` — that box includes empty
    /// descender space. Align the optical mid (`baseline + capHeight/2`) to `center`.
    static func drawCenteredDigit(_ label: String, at center: CGPoint, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        // `draw(at:)` origin = bottom-left of the typographic box;
        // baseline = origin.y - descender (descender is negative).
        let origin = CGPoint(
            x: center.x - size.width / 2,
            y: center.y - font.capHeight / 2 + font.descender
        )
        (label as NSString).draw(at: origin, withAttributes: attrs)
    }

}
