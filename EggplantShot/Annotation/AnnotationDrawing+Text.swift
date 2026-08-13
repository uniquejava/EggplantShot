import AppKit
import CoreImage

// Text mark draw.

extension AnnotationDrawing {
    static func drawText(string: String, style: TextStyle, in rect: CGRect) {
        let display = string.isEmpty ? " " : string
        let attributed = NSAttributedString(string: display, attributes: style.attributes())
        let pad = style.textPadding

        if style.hasBackground {
            let bg = ContrastChrome.textPlate(behind: style.color)
            bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }

        let textRect = rect.insetBy(dx: pad, dy: pad)
        // Wrap to the mark’s width (must match the field editor / commit sizing).
        attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

}
