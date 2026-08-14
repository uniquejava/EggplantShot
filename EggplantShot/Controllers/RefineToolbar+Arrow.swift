import AppKit
import CoreImage
import QuartzCore

// Arrow cap menus + switch.

extension RefineToolbarController {
    func makeCapDropdownButton(tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        // Cap chips are narrower than the body line-style pill; leave room for padding.
        button.layer?.cornerRadius = 5
        button.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor(calibratedWhite: 0.78, alpha: 1).cgColor
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
        self.tooltip.register(button, text: tooltip)
        return button
    }

    enum CapPreviewDirection {
        case left
        case right
    }

    /// Chip icon: short stub + small tip, inset so the glyph isn’t edge-to-edge.
    func arrowCapPreviewImage(cap: ArrowCapStyle, pointing: CapPreviewDirection) -> NSImage {
        let size = CGSize(width: 26, height: 14)
        return NSImage(size: size, flipped: false) { rect in
            AnnotationDrawing.drawCapPreview(
                cap,
                in: rect.insetBy(dx: 3, dy: 2),
                pointingLeft: pointing == .left,
                color: NSColor(calibratedWhite: 0.28, alpha: 1),
                strokeWidth: 1.5
            )
            return true
        }
    }

    @objc func arrowStartCapTapped(_ sender: NSButton) {
        presentCapMenu(for: .start, from: sender)
    }

    @objc func arrowEndCapTapped(_ sender: NSButton) {
        presentCapMenu(for: .end, from: sender)
    }

    func presentCapMenu(for endpoint: ArrowEndpoint, from sender: NSButton) {
        let menu = NSMenu()
        let current = endpoint == .start ? arrowCaps.start : arrowCaps.end
        for option in ArrowCapStyle.menuCases {
            let item = NSMenuItem(
                title: "",
                action: #selector(arrowCapMenuPicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = option.rawValue
            item.representedObject = endpoint == .start ? "start" : "end"
            item.state = (option == current) ? .on : .off
            item.image = arrowCapMenuImage(
                option,
                pointing: endpoint == .start ? .left : .right
            )
            menu.addItem(item)
        }
        let point = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc func arrowCapMenuPicked(_ sender: NSMenuItem) {
        guard let option = ArrowCapStyle(rawValue: sender.tag),
              let which = sender.representedObject as? String
        else { return }
        if which == "start" {
            arrowCaps.start = option
        } else {
            arrowCaps.end = option
        }
        refreshSelectionChrome()
        onEvent(.arrowCapsChanged(arrowCaps))
    }

    func arrowCapMenuImage(_ cap: ArrowCapStyle, pointing: CapPreviewDirection) -> NSImage {
        // Same footprint for every row; inset so glyphs don’t touch the menu edges.
        let size = CGSize(width: 28, height: 14)
        return NSImage(size: size, flipped: false) { rect in
            AnnotationDrawing.drawCapPreview(
                cap,
                in: rect.insetBy(dx: 3, dy: 2),
                pointingLeft: pointing == .left,
                color: NSColor(calibratedWhite: 0.25, alpha: 1),
                strokeWidth: 1.5
            )
            return true
        }
    }

    @objc func arrowDoubleTapped() {
        // Toggle: strip arrowheads ↔ restore last arrowed caps (not force double-ended).
        if arrowCaps.hasCaps {
            lastArrowedCaps = arrowCaps
            arrowCaps = .plainLine()
        } else {
            arrowCaps = lastArrowedCaps.hasCaps ? lastArrowedCaps : .default
        }
        refreshSelectionChrome()
        onEvent(.arrowCapsChanged(arrowCaps))
    }

    /// Snipaste-like stacked Switch: top = armed caps preview, bottom = plain line.
    /// Active row is dark; inactive row is light gray.
    func arrowCapsSwitchImage() -> NSImage {
        let size = CGSize(width: 20, height: 20)
        let arrowsActive = arrowCaps.hasCaps
        let armed = arrowCaps.hasCaps ? arrowCaps : lastArrowedCaps
        let active = NSColor(calibratedWhite: 0.18, alpha: 1)
        let inactive = NSColor(calibratedWhite: 0.62, alpha: 1)
        return NSImage(size: size, flipped: false) { rect in
            // Pack the two shafts tightly around the vertical center (Snipaste-like).
            let rowH: CGFloat = 5
            let rowGap: CGFloat = 1.5
            let stackH = rowH * 2 + rowGap
            let bottomOriginY = (rect.height - stackH) / 2
            let bottom = CGRect(x: 2, y: bottomOriginY, width: rect.width - 4, height: rowH)
            let top = CGRect(x: 2, y: bottomOriginY + rowH + rowGap, width: rect.width - 4, height: rowH)
            AnnotationDrawing.drawCapsPairPreview(
                armed,
                in: top,
                color: arrowsActive ? active : inactive,
                strokeWidth: 1.15
            )
            AnnotationDrawing.drawCapsPairPreview(
                .plainLine(),
                in: bottom,
                color: arrowsActive ? inactive : active,
                strokeWidth: 1.15
            )
            return true
        }
    }

    func lineStyleMenuImage(_ lineStyle: StrokeLineStyle) -> NSImage {
        let size = CGSize(width: 56, height: 14)
        let previewStroke: CGFloat = 2
        return NSImage(size: size, flipped: false) { rect in
            NSColor(calibratedWhite: 0.25, alpha: 1).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 2, y: rect.midY))
            line.line(to: NSPoint(x: rect.width - 2, y: rect.midY))
            line.lineWidth = previewStroke
            line.lineCapStyle = .butt
            let dash = lineStyle.dashPattern(strokeWidth: previewStroke)
            if !dash.isEmpty {
                line.setLineDash(dash, count: dash.count, phase: 0)
            }
            line.stroke()
            return true
        }
    }

}
/// Caps Switch: press nudges the stacked glyphs down; release restores (Snipaste press feel).
final class ArrowCapsSwitchButton: NSButton {
    let pressTranslationY: CGFloat = -1.5

    override func mouseDown(with event: NSEvent) {
        wantsLayer = true
        applyPressOffset(pressTranslationY, animated: true)
        // Blocks until mouse-up, then sends the action.
        super.mouseDown(with: event)
        applyPressOffset(0, animated: true)
    }

    func applyPressOffset(_ y: CGFloat, animated: Bool) {
        wantsLayer = true
        let apply = {
            self.layer?.transform = CATransform3DMakeTranslation(0, y, 0)
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.07
                ctx.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }
    }
}


