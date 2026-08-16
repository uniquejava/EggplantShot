import AppKit
import CoreImage

// Text mark draw + Snipaste hover/selection chrome (3 resize corners + close).

extension AnnotationDrawing {
    /// Visual size of each Snipaste-style text corner badge (points).
    /// Snipaste's handles are small; 16pt matches them. The bold SF Symbol arrow stays legible here —
    /// below ~14pt its thin shaft starts breaking up into dots at @2x.
    static let textCornerBadgeSize: CGFloat = 16

    /// Minimum distance between neighboring badge *centers* (keeps a gap when the text box is tiny).
    static var textCornerBadgeMinCenterDistance: CGFloat { textCornerBadgeSize + 8 }

    /// Corner-badge centers. When the text box is smaller than `minCenterDistance`, badges are
    /// pushed **outward** from the four corners — the text frame itself is unchanged.
    static func textCornerBadgeCenters(in rect: CGRect) -> (
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomLeft: CGPoint,
        bottomRight: CGPoint
    ) {
        let minDist = textCornerBadgeMinCenterDistance
        let ox = max(0, (minDist - rect.width) / 2)
        let oy = max(0, (minDist - rect.height) / 2)
        return (
            topLeft: CGPoint(x: rect.minX - ox, y: rect.maxY + oy),
            topRight: CGPoint(x: rect.maxX + ox, y: rect.maxY + oy),
            bottomLeft: CGPoint(x: rect.minX - ox, y: rect.minY - oy),
            bottomRight: CGPoint(x: rect.maxX + ox, y: rect.minY - oy)
        )
    }

    static func drawText(string: String, style: TextStyle, in rect: CGRect) {
        let display = string.isEmpty ? " " : string
        let attributed = NSAttributedString(string: display, attributes: style.attributes())
        let pad = style.textPadding

        if style.hasBackground {
            let bg = ContrastChrome.textPlate(behind: style.color)
            bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }

        // Horizontal padding is an inset; vertical placement **centres** the glyph block in whatever
        // rect it is handed, which keeps `textVerticalPadding` a fitting-time concern.
        //
        // Centring rather than top-insetting by `textVerticalPadding` is the safer of the two for
        // marks saved before that padding grew: their rect is `max(glyphHeight, fontBoundingHeight)`
        // plus the old 2pt, so top-insetting by the larger value would push descenders out of the
        // box, whereas centring can never clip (the rect is always taller than the glyph block).
        // It is not pixel-identical though — a pre-existing mark's text shifts **down by up to 2pt**
        // (half the slack between the font's bounding box and its rendered line height), most at
        // large sizes. Accepted as the smallest-impact option; re-fitting rects on load would
        // change the stored geometry instead.
        var textRect = rect.insetBy(dx: pad, dy: 0)
        let natural = attributed.boundingRect(
            with: CGSize(width: textRect.width, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let slack = max(0, textRect.height - ceil(natural.height))
        textRect = textRect.insetBy(dx: 0, dy: slack / 2)
        // Wrap to the mark’s width (must match the field editor / commit sizing).
        attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    /// Snipaste text chrome: solid white frame + 3 blue resize corner badges + top-right close (X).
    static func drawTextResizeChrome(in rect: CGRect, lineWidth: CGFloat = 1) {
        guard rect.width >= 1, rect.height >= 1 else { return }
        NSColor.white.setStroke()
        let frame = NSBezierPath(rect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        frame.lineWidth = lineWidth
        frame.stroke()

        let size = textCornerBadgeSize
        let c = textCornerBadgeCenters(in: rect)
        // Three resize corners (diagonal arrows); top-right is close.
        drawTextCornerBadge(center: c.topLeft, size: size, kind: .resize(backslashDiagonal: true))
        drawTextCornerBadge(center: c.topRight, size: size, kind: .close)
        drawTextCornerBadge(center: c.bottomLeft, size: size, kind: .resize(backslashDiagonal: false))
        drawTextCornerBadge(center: c.bottomRight, size: size, kind: .resize(backslashDiagonal: true))
    }

    private enum TextCornerBadgeKind {
        case resize(backslashDiagonal: Bool)
        case close
    }

    /// White-bordered blue rounded rect (Snipaste) — not a soft filled blob.
    private static func drawTextCornerBadge(center: CGPoint, size: CGFloat, kind: TextCornerBadgeKind) {
        let badge = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        let outerRadius: CGFloat = 3
        // Rim stays ~0.107 × badge (Snipaste's proportion), so it scales with `textCornerBadgeSize`.
        let border: CGFloat = 1.5

        // White outer plate (the visible rim).
        NSColor.white.setFill()
        NSBezierPath(roundedRect: badge, xRadius: outerRadius, yRadius: outerRadius).fill()

        // Blue inset face.
        let inner = badge.insetBy(dx: border, dy: border)
        let innerRadius = max(outerRadius - border, 1)
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: inner, xRadius: innerRadius, yRadius: innerRadius).fill()

        switch kind {
        case .close:
            drawCloseX(in: inner)
        case .resize(let backslashDiagonal):
            drawDiagonalResizeArrow(in: inner, backslashDiagonal: backslashDiagonal)
        }
    }

    private static func drawCloseX(in badge: CGRect) {
        let inset = badge.width * 0.26
        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.move(to: CGPoint(x: badge.minX + inset, y: badge.minY + inset))
        path.line(to: CGPoint(x: badge.maxX - inset, y: badge.maxY - inset))
        path.move(to: CGPoint(x: badge.minX + inset, y: badge.maxY - inset))
        path.line(to: CGPoint(x: badge.maxX - inset, y: badge.minY + inset))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.stroke()
    }

    /// White SF Symbol arrows for the resize corners: open chevron heads on a thin shaft (Snipaste).
    /// Tinted once and reused — hover redraws all four badges, and symbol lookup is not free.
    /// Names are **positional** (where each arrow sits), not directional: the `.up.right.and.down.left`
    /// pair is the inward *shrink* glyph, so the outward `/` diagonal is `.down.left.and.up.right`.
    private static let textResizeGlyphBackslash = textBadgeGlyph("arrow.up.left.and.arrow.down.right")
    private static let textResizeGlyphSlash = textBadgeGlyph("arrow.down.left.and.arrow.up.right")

    /// Glyph width as a fraction of the blue face — Snipaste leaves the arrow clear breathing room.
    private static let textResizeGlyphFaceFraction: CGFloat = 0.70

    private static func textBadgeGlyph(_ symbolName: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }
        let glyph = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 32, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        )
        glyph?.isTemplate = false  // already white; template would re-tint to the context color
        return glyph
    }

    /// Snipaste-style diagonal ↔, centered in the blue face with its aspect preserved.
    private static func drawDiagonalResizeArrow(in badge: CGRect, backslashDiagonal: Bool) {
        let glyph = backslashDiagonal ? textResizeGlyphBackslash : textResizeGlyphSlash
        guard let glyph, glyph.size.width > 0, glyph.size.height > 0 else { return }
        // The symbol box hugs its strokes, so scale down explicitly rather than filling the face.
        let scale = min(badge.width / glyph.size.width, badge.height / glyph.size.height)
            * textResizeGlyphFaceFraction
        let size = CGSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
        glyph.draw(in: CGRect(
            x: badge.midX - size.width / 2,
            y: badge.midY - size.height / 2,
            width: size.width,
            height: size.height
        ))
    }
}
