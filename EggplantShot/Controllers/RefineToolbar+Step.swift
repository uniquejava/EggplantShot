import AppKit
import CoreImage
import QuartzCore

// Step sub-toolbar + actions.

extension RefineToolbarController {
    func buildStepSubToolbar() -> NSView {
        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        stepKindButtons = StepChromeKind.allCases.map { kind in
            let button = NSButton(frame: .zero)
            button.bezelStyle = .inline
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(stepKindTapped(_:))
            button.tag = kind.rawValue
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 24),
                button.heightAnchor.constraint(equalToConstant: 24),
            ])
            button.image = stepChromeIcon(kind: kind, selected: false)
            tooltip.register(button, text: stepKindTooltip(kind))
            return button
        }
        for button in stepKindButtons {
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(miniDivider())

        stepSizeButton = NSButton(frame: .zero)
        stepSizeButton.bezelStyle = .inline
        stepSizeButton.isBordered = false
        stepSizeButton.setButtonType(.momentaryChange)
        stepSizeButton.target = self
        stepSizeButton.action = #selector(stepSizeTapped(_:))
        stepSizeButton.translatesAutoresizingMaskIntoConstraints = false
        stepSizeButton.wantsLayer = true
        stepSizeButton.layer?.cornerRadius = 4
        stepSizeButton.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        stepSizeButton.layer?.borderWidth = 1
        stepSizeButton.layer?.borderColor = NSColor(calibratedWhite: 0.78, alpha: 1).cgColor
        tooltip.register(stepSizeButton, text: "Size")
        stepSizeButton.font = NSFont.systemFont(ofSize: 11)
        NSLayoutConstraint.activate([
            stepSizeButton.widthAnchor.constraint(equalToConstant: 44),
            stepSizeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        stack.addArrangedSubview(stepSizeButton)
        stack.addArrangedSubview(miniDivider())

        let preview = NSView(frame: .zero)
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 3
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = NSColor(calibratedWhite: 0.35, alpha: 1).cgColor
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 24),
            preview.heightAnchor.constraint(equalToConstant: 24),
        ])
        stepColorPreview = preview
        stack.addArrangedSubview(preview)

        let swatchGrid = NSStackView(views: [])
        swatchGrid.orientation = .vertical
        swatchGrid.spacing = 2
        swatchGrid.alignment = .leading

        let allSwatches = PaletteColor.allCases
        let columns = 10
        for rowStart in stride(from: 0, to: allSwatches.count, by: columns) {
            let row = NSStackView(views: [])
            row.orientation = .horizontal
            row.spacing = 2
            let end = min(rowStart + columns, allSwatches.count)
            for swatch in allSwatches[rowStart..<end] {
                let control = PaletteSwatchControl(swatch: swatch) { [weak self] picked in
                    guard let self else { return }
                    self.stepStyle.color = picked.color
                    self.refreshSelectionChrome()
                    self.onEvent(.stepStyleChanged(self.stepStyle))
                }
                row.addArrangedSubview(control)
            }
            swatchGrid.addArrangedSubview(row)
        }
        stack.addArrangedSubview(swatchGrid)

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    func refreshStepChrome() {
        for button in stepKindButtons {
            let kind = StepChromeKind(rawValue: button.tag) ?? .filled
            let on = kind == stepStyle.kind
            button.image = stepChromeIcon(kind: kind, selected: on)
            tintSelected(button, selected: on)
        }
        stepSizeButton.title = "\(Int(stepStyle.size.rounded()))"
        stepColorPreview.layer?.backgroundColor = stepStyle.color.cgColor
    }

    func stepToolIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let oval = rect.insetBy(dx: 1.5, dy: 1.5)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: oval).fill()
            // Cut out the digit so tintSelected keeps a white-looking “1”.
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.saveGState()
            ctx.setBlendMode(.destinationOut)
            AnnotationDrawing.drawCenteredDigit(
                "1",
                at: CGPoint(x: rect.midX, y: rect.midY),
                font: NSFont.systemFont(ofSize: 9, weight: .bold),
                color: .black
            )
            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    func stepKindTooltip(_ kind: StepChromeKind) -> String {
        switch kind {
        case .filled: return "Filled"
        case .outline: return "Outline"
        case .plain: return "Number only"
        }
    }

    /// Sub-toolbar chrome previews (filled / outline / plain).
    func stepChromeIcon(kind: StepChromeKind, selected: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let accent = selected ? NSColor.systemBlue : NSColor(calibratedWhite: 0.28, alpha: 1)
        return NSImage(size: size, flipped: false) { rect in
            let d: CGFloat = 14
            let disk = CGRect(
                x: (rect.width - d) / 2,
                y: (rect.height - d) / 2,
                width: d,
                height: d
            )
            let digitColor: NSColor
            switch kind {
            case .filled:
                accent.setFill()
                NSBezierPath(ovalIn: disk).fill()
                digitColor = .white
            case .outline:
                let path = NSBezierPath(ovalIn: disk.insetBy(dx: 0.75, dy: 0.75))
                path.lineWidth = 1.5
                accent.setStroke()
                path.stroke()
                digitColor = accent
            case .plain:
                // Dashed rounded plate so a bare “1” still reads as a tool chip.
                let plate = disk.insetBy(dx: 0.5, dy: 0.5)
                let frame = NSBezierPath(roundedRect: plate, xRadius: 3, yRadius: 3)
                frame.lineWidth = 1.25
                let dash: [CGFloat] = [2.5, 1.5]
                frame.setLineDash(dash, count: dash.count, phase: 0)
                accent.setStroke()
                frame.stroke()
                digitColor = accent
            }
            let font = NSFont.systemFont(ofSize: 9, weight: .bold)
            AnnotationDrawing.drawCenteredDigit(
                "1",
                at: CGPoint(x: rect.midX, y: rect.midY),
                font: font,
                color: digitColor
            )
            return true
        }
    }

    @objc func stepKindTapped(_ sender: NSButton) {
        stepStyle.kind = StepChromeKind(rawValue: sender.tag) ?? .filled
        refreshSelectionChrome()
        onEvent(.stepStyleChanged(stepStyle))
    }

    @objc func stepSizeTapped(_ sender: NSButton) {
        let menu = NSMenu()
        for size in StepStyle.sizeChoices {
            let item = NSMenuItem(
                title: "\(Int(size))",
                action: #selector(stepSizeMenuPicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Int(size)
            item.state = (abs(size - stepStyle.size) < 0.5) ? .on : .off
            menu.addItem(item)
        }
        let point = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc func stepSizeMenuPicked(_ sender: NSMenuItem) {
        stepStyle.size = StepStyle.nearestSize(CGFloat(sender.tag))
        refreshSelectionChrome()
        onEvent(.stepStyleChanged(stepStyle))
    }

}
