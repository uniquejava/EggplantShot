import AppKit
import CoreImage
import QuartzCore

// Text sub-toolbar + actions.

extension RefineToolbarController {
    func buildTextSubToolbar() -> NSView {
        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        textBoldButton = textStyleToggleButton(title: "B", tooltip: "Bold", action: #selector(textBoldTapped))
        textBoldButton.font = NSFont.boldSystemFont(ofSize: 12)
        textItalicButton = textStyleToggleButton(title: "I", tooltip: "Italic", action: #selector(textItalicTapped))
        textItalicButton.font = {
            let base = NSFont.systemFont(ofSize: 12)
            return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        }()
        textBackgroundButton = iconButton(
            systemName: "character.textbox",
            tooltip: "Background",
            enabled: true,
            action: #selector(textBackgroundTapped)
        )
        stack.addArrangedSubview(textBoldButton)
        stack.addArrangedSubview(textItalicButton)
        stack.addArrangedSubview(textBackgroundButton)
        stack.addArrangedSubview(miniDivider())

        textSizeButton = NSButton(frame: .zero)
        textSizeButton.bezelStyle = .inline
        textSizeButton.isBordered = false
        textSizeButton.setButtonType(.momentaryChange)
        textSizeButton.target = self
        textSizeButton.action = #selector(textSizeTapped(_:))
        textSizeButton.translatesAutoresizingMaskIntoConstraints = false
        textSizeButton.wantsLayer = true
        textSizeButton.layer?.cornerRadius = 4
        textSizeButton.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        textSizeButton.layer?.borderWidth = 1
        textSizeButton.layer?.borderColor = NSColor(calibratedWhite: 0.78, alpha: 1).cgColor
        textSizeButton.font = NSFont.systemFont(ofSize: 11)
        NSLayoutConstraint.activate([
            textSizeButton.widthAnchor.constraint(equalToConstant: 44),
            textSizeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        tooltip.register(textSizeButton, text: "Font size")
        stack.addArrangedSubview(textSizeButton)
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
        textColorPreview = preview
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
                    self.textStyle.color = picked.color
                    self.refreshSelectionChrome()
                    self.onEvent(.textStyleChanged(self.textStyle))
                }
                row.addArrangedSubview(control)
            }
            swatchGrid.addArrangedSubview(row)
        }
        stack.addArrangedSubview(swatchGrid)

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    func textStyleToggleButton(title: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.title = title
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
        self.tooltip.register(button, text: tooltip)
        return button
    }

    func textToolIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        // `flipped: true` matches SVG’s y-down viewBox so the T is right-side up.
        let image = NSImage(size: size, flipped: true) { rect in
            let s = rect.width / 24
            let path = NSBezierPath()
            // <polyline points="4 7 4 4 20 4 20 7" />
            path.move(to: NSPoint(x: 4 * s, y: 7 * s))
            path.line(to: NSPoint(x: 4 * s, y: 4 * s))
            path.line(to: NSPoint(x: 20 * s, y: 4 * s))
            path.line(to: NSPoint(x: 20 * s, y: 7 * s))
            // <line x1="9" x2="15" y1="20" y2="20" />
            path.move(to: NSPoint(x: 9 * s, y: 20 * s))
            path.line(to: NSPoint(x: 15 * s, y: 20 * s))
            // <line x1="12" x2="12" y1="4" y2="20" />
            path.move(to: NSPoint(x: 12 * s, y: 4 * s))
            path.line(to: NSPoint(x: 12 * s, y: 20 * s))
            path.lineWidth = 2 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Snipaste-like pencil: twin shaft lines, pointed tip, semi-ellipse eraser (~mosaic size).
    @objc func textBoldTapped() {
        textStyle.isBold.toggle()
        refreshSelectionChrome()
        onEvent(.textStyleChanged(textStyle))
    }

    @objc func textItalicTapped() {
        textStyle.isItalic.toggle()
        refreshSelectionChrome()
        onEvent(.textStyleChanged(textStyle))
    }

    @objc func textBackgroundTapped() {
        textStyle.hasBackground.toggle()
        refreshSelectionChrome()
        onEvent(.textStyleChanged(textStyle))
    }

    @objc func textSizeTapped(_ sender: NSButton) {
        let menu = NSMenu()
        for size in TextStyle.fontSizeChoices {
            let item = NSMenuItem(
                title: "\(Int(size))",
                action: #selector(textSizeMenuPicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Int(size)
            item.state = (abs(size - textStyle.fontSize) < 0.5) ? .on : .off
            menu.addItem(item)
        }
        let point = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc func textSizeMenuPicked(_ sender: NSMenuItem) {
        textStyle.fontSize = CGFloat(sender.tag)
        refreshSelectionChrome()
        onEvent(.textStyleChanged(textStyle))
    }

}
