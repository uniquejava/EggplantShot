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

    /// Arrowhead apex angle: **60°**, the classic arrowhead. Matched to draw.io's slimmer arrow, which
    /// measured 58–61° off a screenshot (13–14px of head height over 12px of length); 2·tan(30°) =
    /// 1.155 sits inside that width:length range, so 60° is the value it was almost certainly built
    /// from. Snipaste's is blunter — its head measured 71.4° (4.6× the stroke wide) — and read too
    /// upright here, so this deliberately does not match it.
    ///
    /// Only the *angle* is borrowed. draw.io's head is a fixed size regardless of stroke weight, so
    /// its 6:1 head-to-stroke ratio means nothing here; head length stays tied to stroke width below.
    /// (Not a "golden" constant — the golden angle is 137.5°.)
    static let arrowheadApexDegrees: CGFloat = 60

    /// Head width for a given head length at `apexDegrees`. Width is *derived* so the angle survives
    /// any length tweak — length and width used to be independent constants, which is how the chevron
    /// drifted to 41° while its own legend drew 64°.
    static func arrowheadSpan(
        length: CGFloat,
        apexDegrees: CGFloat = arrowheadApexDegrees
    ) -> CGFloat {
        2 * length * tan(apexDegrees / 2 * .pi / 180)
    }

    static func openArrowLength(strokeWidth: CGFloat, wide: Bool) -> CGFloat {
        wide ? max(strokeWidth * 3.8, 10) : max(strokeWidth * 3.6, 9)
    }

    static func openArrowWidth(strokeWidth: CGFloat, wide: Bool) -> CGFloat {
        arrowheadSpan(length: openArrowLength(strokeWidth: strokeWidth, wide: wide))
    }

    static func arrowheadLength(strokeWidth: CGFloat) -> CGFloat {
        max(strokeWidth * 3.2, 8)
    }

    static func arrowheadWidth(strokeWidth: CGFloat) -> CGFloat {
        arrowheadSpan(length: arrowheadLength(strokeWidth: strokeWidth))
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

        // Every ornament fills the same **ink** box: `tipDepth` deep, ending at `tip`, `tipSpan` tall.
        // Ink, not path — a mitered stroke reaches well past its own path, so a path built to the box
        // still renders oversized. Measured by rendering each glyph at 8× and taking the bounds of
        // pixels with alpha > 0.15: at sw 1.5 a chevron tip threw +1.31pt past `tip`, and the hollow
        // triangle's default-miter base corners +1.12pt per side — which is why those two read a point
        // longer and up to 2pt taller than the filled triangle beside them. Filled shapes need no
        // correction (ink == path); stroked ones are inset below. Re-measuring the same way should
        // show 0.00pt spread across all six ornaments, in both directions and both icon sizes.
        let tipSpan = min(rect.height * 0.70, 7.0)
        let halfSpan = tipSpan / 2
        // Depth follows the same apex as drawn arrowheads, so a legend predicts what you get on
        // screen. Capped by the tip budget, at 0.95 rather than 0.88 so a 60° head (which needs 6.06pt
        // of a 6.5pt budget) isn't clamped into looking blunter than what it draws. The bridge shortens
        // to absorb it; every ornament shares this depth, arrowhead or not, which is what keeps the six
        // ink boxes identical.
        let tipDepth = min(halfSpan / tan(arrowheadApexDegrees / 2 * .pi / 180), tipLen * 0.95)

        /// Path geometry for a stroked arrowhead whose *ink* fills `tipDepth` × `tipSpan`.
        /// The mitered tip adds `(w/2)/sin α` along the axis and each wing end adds `(w/2)·cos α`
        /// vertically; α depends on the result, so iterate — converges in two passes at this size.
        func strokedHead(width w: CGFloat) -> (tipInset: CGFloat, depth: CGFloat, half: CGFloat) {
            var depth = tipDepth
            var half = halfSpan
            var inset: CGFloat = 0
            for _ in 0..<3 {
                let a = atan2(half, depth)
                inset = (w / 2) / max(sin(a), 0.25)
                depth = tipDepth - inset
                half = max(halfSpan - (w / 2) * cos(a), 0.6)
            }
            return (inset, max(depth, 1), half)
        }

        switch cap {
        case .none:
            let ext = NSBezierPath()
            ext.move(to: join)
            ext.line(to: tip)
            ext.lineWidth = sw
            ext.lineCapStyle = .butt
            ext.stroke()

        case .bar:
            // Stroked vertical: its half-width spills past the path, so sit it back by sw/2.
            let barX = tipX - ux * (sw / 2)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: barX, y: y + halfSpan))
            path.line(to: CGPoint(x: barX, y: y - halfSpan))
            path.lineWidth = sw
            path.lineCapStyle = .butt
            // Bridge stub → bar so it sits at the tip like other ornaments.
            let bridge = NSBezierPath()
            bridge.move(to: join)
            bridge.line(to: CGPoint(x: barX, y: y))
            bridge.lineWidth = sw
            bridge.lineCapStyle = .butt
            bridge.stroke()
            path.stroke()

        case .circle:
            let r = halfSpan
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
            let halfLen = tipDepth / 2
            let halfWid = halfSpan
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
            let head = strokedHead(width: sw)
            let headTip = CGPoint(x: tipX - ux * head.tipInset, y: y)
            let baseX = headTip.x - ux * head.depth
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: headTip)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: baseX, y: y + head.half))
            path.line(to: headTip)
            path.line(to: CGPoint(x: baseX, y: y - head.half))
            path.lineWidth = sw
            path.lineJoinStyle = .miter
            path.lineCapStyle = .butt
            path.stroke()

        case .arrow:
            // Filled: ink is the path, so it takes the target box as-is.
            let base = CGPoint(x: tipX - ux * tipDepth, y: y)
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: base)
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            let path = NSBezierPath()
            path.move(to: tip)
            path.line(to: CGPoint(x: base.x, y: y + halfSpan))
            path.line(to: CGPoint(x: base.x, y: y - halfSpan))
            path.close()
            path.fill()

        case .hollowArrow:
            let swH = max(sw * 0.9, 1)
            let head = strokedHead(width: swH)
            let headTip = CGPoint(x: tipX - ux * head.tipInset, y: y)
            let baseX = headTip.x - ux * head.depth
            let br = NSBezierPath()
            br.move(to: join)
            br.line(to: CGPoint(x: baseX, y: y))
            br.lineWidth = sw
            br.lineCapStyle = .butt
            br.stroke()
            let path = NSBezierPath()
            path.move(to: headTip)
            path.line(to: CGPoint(x: baseX, y: y + head.half))
            path.line(to: CGPoint(x: baseX, y: y - head.half))
            path.close()
            path.lineWidth = swH
            path.lineJoinStyle = .miter
            // Default limit (10) lets the two base corners throw ~1.1pt spikes past the box. At 2 the
            // tip's 1.89 ratio still miters sharp while those corners bevel away.
            path.miterLimit = 2
            path.stroke()
        }
    }

}
