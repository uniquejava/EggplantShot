import AppKit
import CoreImage

// Arrow + cap draw / hit / preview.

extension AnnotationDrawing {
    static func drawArrow(start: CGPoint, end: CGPoint, style: AnnotationStyle, caps: ArrowCaps) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else {
            let r = max(style.strokeWidth / 2, 0.5)
            style.strokeColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)).fill()
            return
        }

        let ux = dx / length
        let uy = dy / length
        let startInset = shaftInset(for: caps.start, strokeWidth: style.strokeWidth)
        let endInset = shaftInset(for: caps.end, strokeWidth: style.strokeWidth)

        var shaftStart = start
        var shaftEnd = end
        if startInset > 0 {
            shaftStart = CGPoint(x: start.x + ux * startInset, y: start.y + uy * startInset)
        }
        if endInset > 0 {
            shaftEnd = CGPoint(x: end.x - ux * endInset, y: end.y - uy * endInset)
        }

        if hypot(shaftEnd.x - shaftStart.x, shaftEnd.y - shaftStart.y) > 0.5 {
            let path = NSBezierPath()
            path.move(to: shaftStart)
            path.line(to: shaftEnd)
            applyStroke(style, to: path)
            path.lineCapStyle = .butt
            style.strokeColor.setStroke()
            path.stroke()
        }

        // Outward at start is opposite the shaft; at end along the shaft.
        drawCap(caps.start, tip: start, directionX: -ux, directionY: -uy, style: style)
        drawCap(caps.end, tip: end, directionX: ux, directionY: uy, style: style)
    }

    /// How far the shaft stops short of `tip` for this cap.
    static func shaftInset(for cap: ArrowCapStyle, strokeWidth: CGFloat) -> CGFloat {
        switch cap {
        case .none, .bar:
            // Open chevrons: shaft runs all the way to the tip so line + arrow stay one piece.
            return 0
        case .openArrow, .openArrowWide:
            return 0
        case .circle:
            return circleRadius(strokeWidth: strokeWidth)
        case .diamond:
            return diamondHalfLength(strokeWidth: strokeWidth) * 2
        case .arrow, .hollowArrow:
            // Meet the triangle base, overlapping slightly so stroke + fill fuse.
            return max(arrowheadLength(strokeWidth: strokeWidth) - strokeWidth * 0.35, strokeWidth)
        }
    }

    static func drawCap(
        _ cap: ArrowCapStyle,
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        style: AnnotationStyle
    ) {
        let w = style.strokeWidth
        let color = style.strokeColor
        switch cap {
        case .none:
            break

        case .bar:
            let half = max(w * 1.6, 4)
            let px = -directionY
            let py = directionX
            let a = CGPoint(x: tip.x + px * half, y: tip.y + py * half)
            let b = CGPoint(x: tip.x - px * half, y: tip.y - py * half)
            let path = NSBezierPath()
            path.move(to: a)
            path.line(to: b)
            path.lineWidth = w
            path.lineCapStyle = .butt
            color.setStroke()
            path.stroke()

        case .circle:
            let r = circleRadius(strokeWidth: w)
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)).fill()

        case .diamond:
            let halfLen = diamondHalfLength(strokeWidth: w)
            let halfWid = max(w * 1.4, 3.5)
            let px = -directionY
            let py = directionX
            let base = CGPoint(x: tip.x - directionX * halfLen * 2, y: tip.y - directionY * halfLen * 2)
            let mid = CGPoint(x: tip.x - directionX * halfLen, y: tip.y - directionY * halfLen)
            let left = CGPoint(x: mid.x + px * halfWid, y: mid.y + py * halfWid)
            let right = CGPoint(x: mid.x - px * halfWid, y: mid.y - py * halfWid)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: left)
            path.line(to: base)
            path.line(to: right)
            path.close()
            color.setFill()
            path.fill()

        case .openArrow:
            drawOpenArrowhead(
                tip: tip,
                directionX: directionX,
                directionY: directionY,
                length: openArrowLength(strokeWidth: w, wide: false),
                width: openArrowWidth(strokeWidth: w, wide: false),
                strokeWidth: w,
                color: color
            )

        case .openArrowWide:
            drawOpenArrowhead(
                tip: tip,
                directionX: directionX,
                directionY: directionY,
                length: openArrowLength(strokeWidth: w, wide: true),
                width: openArrowWidth(strokeWidth: w, wide: true),
                strokeWidth: w,
                color: color
            )

        case .arrow:
            drawFilledArrowhead(
                tip: tip,
                directionX: directionX,
                directionY: directionY,
                length: arrowheadLength(strokeWidth: w),
                width: arrowheadWidth(strokeWidth: w),
                color: color
            )

        case .hollowArrow:
            drawHollowArrowhead(
                tip: tip,
                directionX: directionX,
                directionY: directionY,
                length: arrowheadLength(strokeWidth: w),
                width: arrowheadWidth(strokeWidth: w),
                strokeWidth: max(w * 0.85, 1.2),
                color: color
            )
        }
    }

    static func drawFilledArrowhead(
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        length: CGFloat,
        width: CGFloat,
        color: NSColor
    ) {
        let base = CGPoint(x: tip.x - directionX * length, y: tip.y - directionY * length)
        let px = -directionY
        let py = directionX
        let left = CGPoint(x: base.x + px * width / 2, y: base.y + py * width / 2)
        let right = CGPoint(x: base.x - px * width / 2, y: base.y - py * width / 2)
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: left)
        path.line(to: right)
        path.close()
        color.setFill()
        path.fill()
    }

    static func drawHollowArrowhead(
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        length: CGFloat,
        width: CGFloat,
        strokeWidth: CGFloat,
        color: NSColor
    ) {
        let base = CGPoint(x: tip.x - directionX * length, y: tip.y - directionY * length)
        let px = -directionY
        let py = directionX
        let left = CGPoint(x: base.x + px * width / 2, y: base.y + py * width / 2)
        let right = CGPoint(x: base.x - px * width / 2, y: base.y - py * width / 2)
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: left)
        path.line(to: right)
        path.close()
        path.lineWidth = strokeWidth
        path.lineJoinStyle = .miter
        path.lineCapStyle = .butt
        color.setStroke()
        path.stroke()
    }

    static func drawOpenArrowhead(
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        length: CGFloat,
        width: CGFloat,
        strokeWidth: CGFloat,
        color: NSColor
    ) {
        let base = CGPoint(x: tip.x - directionX * length, y: tip.y - directionY * length)
        let px = -directionY
        let py = directionX
        let left = CGPoint(x: base.x + px * width / 2, y: base.y + py * width / 2)
        let right = CGPoint(x: base.x - px * width / 2, y: base.y - py * width / 2)
        let path = NSBezierPath()
        path.move(to: left)
        path.line(to: tip)
        path.line(to: right)
        path.lineWidth = strokeWidth
        path.lineJoinStyle = .miter
        path.lineCapStyle = .butt
        color.setStroke()
        path.stroke()
    }

    static func circleRadius(strokeWidth: CGFloat) -> CGFloat {
        max(strokeWidth * 1.35, 3.5)
    }

    static func diamondHalfLength(strokeWidth: CGFloat) -> CGFloat {
        max(strokeWidth * 1.6, 4)
    }

    static func openArrowLength(strokeWidth: CGFloat, wide: Bool) -> CGFloat {
        // Shorter depth + wider span → opener V (closer to Snipaste open chevron).
        wide ? max(strokeWidth * 2.8, 8) : max(strokeWidth * 2.5, 7)
    }

    static func openArrowWidth(strokeWidth: CGFloat, wide: Bool) -> CGFloat {
        wide ? max(strokeWidth * 4.6, 12) : max(strokeWidth * 4.2, 11)
    }

    static func arrowheadLength(strokeWidth: CGFloat) -> CGFloat {
        max(strokeWidth * 3.2, 8)
    }

    static func arrowheadWidth(strokeWidth: CGFloat) -> CGFloat {
        max(strokeWidth * 2.4, 6)
    }

    /// Axis-aligned bounds including end caps.
    static func arrowBounds(start: CGPoint, end: CGPoint, style: AnnotationStyle, caps: ArrowCaps) -> CGRect {
        var minX = min(start.x, end.x)
        var maxX = max(start.x, end.x)
        var minY = min(start.y, end.y)
        var maxY = max(start.y, end.y)
        let pad = max(
            arrowheadWidth(strokeWidth: style.strokeWidth) / 2,
            openArrowWidth(strokeWidth: style.strokeWidth, wide: true) / 2,
            circleRadius(strokeWidth: style.strokeWidth),
            style.strokeWidth * 1.6,
            style.strokeWidth / 2
        ) + 1
        minX -= pad
        maxX += pad
        minY -= pad
        maxY += pad
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    /// Expanded hit region for a cap (selection-local). `direction` points outward toward the tip.
    static func capHitPath(
        _ cap: ArrowCapStyle,
        tip: CGPoint,
        directionX: CGFloat,
        directionY: CGFloat,
        strokeWidth: CGFloat
    ) -> NSBezierPath? {
        let w = strokeWidth
        let px = -directionY
        let py = directionX
        switch cap {
        case .none:
            return nil
        case .bar:
            return nil
        case .circle:
            let r = circleRadius(strokeWidth: w) + 2
            return NSBezierPath(ovalIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2))
        case .diamond:
            let halfLen = diamondHalfLength(strokeWidth: w)
            let halfWid = max(w * 1.4, 3.5) + 1
            let base = CGPoint(x: tip.x - directionX * halfLen * 2, y: tip.y - directionY * halfLen * 2)
            let mid = CGPoint(x: tip.x - directionX * halfLen, y: tip.y - directionY * halfLen)
            let left = CGPoint(x: mid.x + px * halfWid, y: mid.y + py * halfWid)
            let right = CGPoint(x: mid.x - px * halfWid, y: mid.y - py * halfWid)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: left)
            path.line(to: base)
            path.line(to: right)
            path.close()
            return path
        case .openArrow, .openArrowWide:
            let wide = (cap == .openArrowWide)
            let length = openArrowLength(strokeWidth: w, wide: wide)
            let width = openArrowWidth(strokeWidth: w, wide: wide)
            let base = CGPoint(x: tip.x - directionX * length, y: tip.y - directionY * length)
            let left = CGPoint(x: base.x + px * width / 2, y: base.y + py * width / 2)
            let right = CGPoint(x: base.x - px * width / 2, y: base.y - py * width / 2)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: left)
            path.line(to: right)
            path.close()
            return path
        case .arrow, .hollowArrow:
            let length = arrowheadLength(strokeWidth: w)
            let width = arrowheadWidth(strokeWidth: w)
            let base = CGPoint(x: tip.x - directionX * length, y: tip.y - directionY * length)
            let left = CGPoint(x: base.x + px * width / 2, y: base.y + py * width / 2)
            let right = CGPoint(x: base.x - px * width / 2, y: base.y - py * width / 2)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: left)
            path.line(to: right)
            path.close()
            return path
        }
    }

    /// Miniature full-arrow preview (start + shaft + end) for the caps Switch rows.
    /// Ornaments are hard-capped to the row height so the top half doesn’t dwarf the plain bottom line.
    static func drawCapsPairPreview(
        _ caps: ArrowCaps,
        in rect: CGRect,
        color: NSColor,
        strokeWidth: CGFloat = 1.35
    ) {
        guard rect.width > 4, rect.height > 2 else { return }
        let y = rect.midY
        let pad: CGFloat = 1.5
        let left = CGPoint(x: rect.minX + pad, y: y)
        let right = CGPoint(x: rect.maxX - pad, y: y)
        // Keep glyphs inside the row: ~half the row height max.
        let sw = min(strokeWidth, 1.25)
        let tipLen = min(3.2, rect.height * 0.55)
        let tipWid = min(3.0, rect.height * 0.5)

        color.setStroke()
        color.setFill()

        let startInset = miniatureCapInset(caps.start, tipLen: tipLen)
        let endInset = miniatureCapInset(caps.end, tipLen: tipLen)
        var shaftStart = left
        var shaftEnd = right
        if startInset > 0 { shaftStart = CGPoint(x: left.x + startInset, y: y) }
        if endInset > 0 { shaftEnd = CGPoint(x: right.x - endInset, y: y) }

        if shaftEnd.x - shaftStart.x > 0.5 {
            let path = NSBezierPath()
            path.move(to: shaftStart)
            path.line(to: shaftEnd)
            path.lineWidth = sw
            path.lineCapStyle = .butt
            path.stroke()
        }

        drawMiniatureCap(caps.start, tip: left, pointingRight: false, tipLen: tipLen, tipWid: tipWid, stroke: sw, color: color)
        drawMiniatureCap(caps.end, tip: right, pointingRight: true, tipLen: tipLen, tipWid: tipWid, stroke: sw, color: color)
    }

    static func miniatureCapInset(_ cap: ArrowCapStyle, tipLen: CGFloat) -> CGFloat {
        switch cap {
        case .none, .bar, .openArrow, .openArrowWide: return 0
        case .circle: return tipLen * 0.45
        case .diamond: return tipLen
        case .arrow, .hollowArrow: return tipLen * 0.85
        }
    }

    static func drawMiniatureCap(
        _ cap: ArrowCapStyle,
        tip: CGPoint,
        pointingRight: Bool,
        tipLen: CGFloat,
        tipWid: CGFloat,
        stroke: CGFloat,
        color: NSColor
    ) {
        let ux: CGFloat = pointingRight ? 1 : -1
        let y = tip.y
        color.setStroke()
        color.setFill()

        switch cap {
        case .none:
            break
        case .bar:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: tip.x, y: y + tipWid / 2))
            path.line(to: CGPoint(x: tip.x, y: y - tipWid / 2))
            path.lineWidth = stroke
            path.lineCapStyle = .butt
            path.stroke()
        case .circle:
            let r = tipWid * 0.4
            let c = CGPoint(x: tip.x - ux * r, y: y)
            NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        case .diamond:
            let half = tipLen * 0.5
            let mid = CGPoint(x: tip.x - ux * half, y: y)
            let base = CGPoint(x: tip.x - ux * tipLen, y: y)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: mid.x, y: y + tipWid / 2))
            path.line(to: base)
            path.line(to: CGPoint(x: mid.x, y: y - tipWid / 2))
            path.close()
            path.fill()
        case .openArrow, .openArrowWide:
            let base = CGPoint(x: tip.x - ux * tipLen, y: y)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: base.x, y: y + tipWid / 2))
            path.line(to: tip)
            path.line(to: CGPoint(x: base.x, y: y - tipWid / 2))
            path.lineWidth = stroke
            path.lineJoinStyle = .miter
            path.lineCapStyle = .butt
            path.stroke()
        case .arrow:
            let base = CGPoint(x: tip.x - ux * tipLen, y: y)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: base.x, y: y + tipWid / 2))
            path.line(to: CGPoint(x: base.x, y: y - tipWid / 2))
            path.close()
            path.fill()
        case .hollowArrow:
            let base = CGPoint(x: tip.x - ux * tipLen, y: y)
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: base.x, y: y + tipWid / 2))
            path.line(to: CGPoint(x: base.x, y: y - tipWid / 2))
            path.close()
            path.lineWidth = stroke
            path.lineJoinStyle = .miter
            path.stroke()
        }
    }

    /// Draw a compact horizontal preview of `cap` for toolbar / menu icons.
    /// Short stub + small tip with padding — not a full-width shaft like the body line-style pill.
    static func drawCapPreview(
        _ cap: ArrowCapStyle,
        in rect: CGRect,
        pointingLeft: Bool,
        color: NSColor,
        strokeWidth: CGFloat = 2
    ) {
        guard rect.width > 4, rect.height > 4 else { return }

        let y = rect.midY
        let sw = min(max(strokeWidth, 1.2), 1.6)
        // Fixed glyph budget inside `rect` (caller already insets for chip padding).
        let tipLen: CGFloat = min(6.5, rect.width * 0.38)
        let stubLen: CGFloat = min(8.5, max(rect.width - tipLen - 1, 5))
        let total = stubLen + tipLen
        let originX = rect.midX - total / 2

        let tipX: CGFloat
        let stubFarX: CGFloat
        let joinX: CGFloat
        let ux: CGFloat
        if pointingLeft {
            tipX = originX
            joinX = originX + tipLen
            stubFarX = joinX + stubLen
            ux = -1
        } else {
            stubFarX = originX
            joinX = originX + stubLen
            tipX = joinX + tipLen
            ux = 1
        }

        let tip = CGPoint(x: tipX, y: y)
        let far = CGPoint(x: stubFarX, y: y)
        let join = CGPoint(x: joinX, y: y)

        color.setStroke()
        color.setFill()

        // Stub only (short) — never spans the whole chip.
        let stub = NSBezierPath()
        stub.move(to: far)
        stub.line(to: join)
        stub.lineWidth = sw
        stub.lineCapStyle = .butt
        stub.stroke()

        // Tip ornaments stay inside tipLen × modest height (breathing room).
        let halfH = min(rect.height * 0.32, 3.2)
        let slot = tipLen

        switch cap {
        case .none:
            let ext = NSBezierPath()
            ext.move(to: join)
            ext.line(to: tip)
            ext.lineWidth = sw
            ext.lineCapStyle = .butt
            ext.stroke()

        case .bar:
            let bridge = NSBezierPath()
            bridge.move(to: join)
            bridge.line(to: tip)
            bridge.lineWidth = sw
            bridge.lineCapStyle = .butt
            bridge.stroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: tipX, y: y + halfH))
            path.line(to: CGPoint(x: tipX, y: y - halfH))
            path.lineWidth = sw
            path.lineCapStyle = .butt
            path.stroke()

        case .circle:
            let r = min(halfH, slot * 0.42)
            let c = CGPoint(x: tipX - ux * r, y: y)
            let bridgeEnd = CGPoint(x: c.x - ux * r, y: y)
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: bridgeEnd)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()

        case .diamond:
            let halfLen = min(slot * 0.45, 3.2)
            let halfWid = halfH * 0.9
            let mid = CGPoint(x: tipX - ux * halfLen, y: y)
            let base = CGPoint(x: tipX - ux * halfLen * 2, y: y)
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: base)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: mid.x, y: y + halfWid))
            path.line(to: base)
            path.line(to: CGPoint(x: mid.x, y: y - halfWid))
            path.close()
            path.fill()

        case .openArrow, .openArrowWide:
            let length = min(slot * 0.85, 5.5)
            let width = halfH * 1.7
            let base = CGPoint(x: tipX - ux * length, y: y)
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: tip)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: base.x, y: y + width / 2))
            path.line(to: tip)
            path.line(to: CGPoint(x: base.x, y: y - width / 2))
            path.lineWidth = sw
            path.lineJoinStyle = .miter
            path.lineCapStyle = .butt
            path.stroke()

        case .arrow:
            let length = min(slot * 0.88, 5.5)
            let width = halfH * 1.55
            let base = CGPoint(x: tipX - ux * length, y: y)
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: base)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: base.x, y: y + width / 2))
            path.line(to: CGPoint(x: base.x, y: y - width / 2))
            path.close()
            path.fill()

        case .hollowArrow:
            let length = min(slot * 0.88, 5.5)
            let width = halfH * 1.55
            let base = CGPoint(x: tipX - ux * length, y: y)
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: base)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: base.x, y: y + width / 2))
            path.line(to: CGPoint(x: base.x, y: y - width / 2))
            path.close()
            path.lineWidth = max(sw * 0.9, 1)
            path.lineJoinStyle = .miter
            path.stroke()
        }
    }

}
