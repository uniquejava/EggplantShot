import AppKit
import CoreImage
import QuartzCore

// Shared toolbar icon helpers.

extension RefineToolbarController {
    func tintSelected(_ button: NSButton, selected: Bool) {
        guard button.isEnabled else {
            button.contentTintColor = NSColor(calibratedWhite: 0.55, alpha: 1)
            button.layer?.backgroundColor = nil
            return
        }
        button.contentTintColor = selected
            ? NSColor.systemBlue
            : NSColor(calibratedWhite: 0.22, alpha: 1)
        if selected {
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.12).cgColor
            button.layer?.cornerRadius = 4
        } else {
            button.layer?.backgroundColor = nil
        }
    }

    func strokeDotImage(diameter: CGFloat, selected: Bool) -> NSImage {
        let size = CGSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let color = selected ? NSColor.systemBlue : NSColor(calibratedWhite: 0.25, alpha: 1)
            color.setFill()
            let r = CGRect(
                x: (rect.width - diameter) / 2,
                y: (rect.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            NSBezierPath(ovalIn: r).fill()
            return true
        }
    }

    func fillSwatchImage(selected: Bool) -> NSImage {
        let size = CGSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let color = selected ? NSColor.systemBlue : NSColor(calibratedWhite: 0.25, alpha: 1)
            color.setFill()
            let r = CGRect(x: 3, y: 3, width: 12, height: 12)
            NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
    }

    /// Compact pill preview: line pattern + chevron (Snipaste-like).
    func lineStylePreviewImage(_ lineStyle: StrokeLineStyle) -> NSImage {
        let size = CGSize(width: 52, height: 18)
        let previewStroke: CGFloat = 2
        return NSImage(size: size, flipped: false) { rect in
            let ink = NSColor(calibratedWhite: 0.28, alpha: 1)
            ink.setStroke()

            let y = rect.midY
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 6, y: y))
            line.line(to: NSPoint(x: 34, y: y))
            line.lineWidth = previewStroke
            line.lineCapStyle = .butt
            let dash = lineStyle.dashPattern(strokeWidth: previewStroke)
            if !dash.isEmpty {
                line.setLineDash(dash, count: dash.count, phase: 0)
            }
            line.stroke()

            // Up / down chevrons on the trailing edge.
            let chevronX: CGFloat = 42
            let chevron = NSBezierPath()
            chevron.move(to: NSPoint(x: chevronX, y: y + 4.5))
            chevron.line(to: NSPoint(x: chevronX + 3.5, y: y + 1.5))
            chevron.line(to: NSPoint(x: chevronX + 7, y: y + 4.5))
            chevron.move(to: NSPoint(x: chevronX, y: y - 4.5))
            chevron.line(to: NSPoint(x: chevronX + 3.5, y: y - 1.5))
            chevron.line(to: NSPoint(x: chevronX + 7, y: y - 4.5))
            chevron.lineWidth = 1.2
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            ink.setStroke()
            chevron.stroke()
            return true
        }
    }

    func iconButton(
        systemName: String,
        tooltip: String,
        enabled: Bool,
        action: Selector?
    ) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        return iconButton(image: image, tooltip: tooltip, enabled: enabled, action: action)
    }

    func iconButton(
        image: NSImage?,
        tooltip: String,
        enabled: Bool,
        action: Selector?
    ) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageOnly
        button.isEnabled = enabled
        button.target = action == nil ? nil : self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        button.image = image
        button.contentTintColor = enabled
            ? NSColor(calibratedWhite: 0.22, alpha: 1)
            : NSColor(calibratedWhite: 0.55, alpha: 1)
        self.tooltip.register(button, text: tooltip)
        return button
    }

    /// Pop a menu under a chip; suppress the custom tooltip so it cannot cover row 1.
    func popUpToolbarMenu(_ menu: NSMenu, from sender: NSView) {
        tooltip.beginMenuSuppression()
        defer { tooltip.endMenuSuppression() }
        let point = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    /// Mosaic / marker / eraser brush presets (14 / 18 / 24).
    static func brushSizeTooltip(index: Int) -> String {
        switch index {
        case 0: return L10n.tr("Small brush")
        case 1: return L10n.tr("Medium brush")
        default: return L10n.tr("Large brush")
        }
    }

    /// Lucide [`type`](https://lucide.dev/icons/type) (ISC) — capital T with top/bottom bars.
    func pencilToolIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            // Axis tip (bottom-left) → eraser (top-right); a touch larger than mosaic.
            let tip = CGPoint(x: 2.6, y: 2.6)
            let end = CGPoint(x: 13.4, y: 13.4)
            let dx = end.x - tip.x
            let dy = end.y - tip.y
            let len = hypot(dx, dy)
            guard len > 1 else { return false }
            let ux = dx / len
            let uy = dy / len
            let px = -uy
            let py = ux

            let halfGap: CGFloat = 1.45
            let tipLen: CGFloat = 3.0
            let ferruleGap: CGFloat = 1.15 // air between shaft and eraser (metal-band read)
            let eraserLen: CGFloat = 2.35
            let lineW: CGFloat = 1.35

            func along(_ t: CGFloat) -> CGPoint {
                CGPoint(x: tip.x + ux * t, y: tip.y + uy * t)
            }
            func offset(_ p: CGPoint, by s: CGFloat) -> CGPoint {
                CGPoint(x: p.x + px * s, y: p.y + py * s)
            }

            let shaftA = along(tipLen)
            let shaftB = along(len - eraserLen - ferruleGap)
            let leftA = offset(shaftA, by: halfGap)
            let leftB = offset(shaftB, by: halfGap)
            let rightA = offset(shaftA, by: -halfGap)
            let rightB = offset(shaftB, by: -halfGap)

            NSColor.black.setStroke()

            let shaft = NSBezierPath()
            shaft.move(to: leftA)
            shaft.line(to: leftB)
            shaft.move(to: rightA)
            shaft.line(to: rightB)
            shaft.lineWidth = lineW
            shaft.lineCapStyle = .butt
            shaft.stroke()

            let tipPath = NSBezierPath()
            tipPath.move(to: tip)
            tipPath.line(to: leftA)
            tipPath.move(to: tip)
            tipPath.line(to: rightA)
            tipPath.lineWidth = lineW
            tipPath.lineCapStyle = .round
            tipPath.stroke()

            // Half-capsule eraser: flat face toward shaft, with a small ferrule gap.
            let flat = along(len - eraserLen)
            let eraserHalfW = halfGap + 0.2
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.saveGState()
            ctx.translateBy(x: flat.x, y: flat.y)
            ctx.rotate(by: atan2(uy, ux))
            // Capsule half: straight sides + semicircular dome on +X.
            let body = max(eraserLen - eraserHalfW, 0.35)
            let cap = NSBezierPath()
            cap.move(to: CGPoint(x: 0, y: -eraserHalfW))
            cap.line(to: CGPoint(x: body, y: -eraserHalfW))
            cap.appendArc(
                withCenter: CGPoint(x: body, y: 0),
                radius: eraserHalfW,
                startAngle: -90,
                endAngle: 90,
                clockwise: false
            )
            cap.line(to: CGPoint(x: 0, y: eraserHalfW))
            cap.close()
            NSColor.black.setFill()
            cap.fill()
            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Snipaste-like 2×2 pixel block: rounded outer frame, large cells tight to the border.
}
