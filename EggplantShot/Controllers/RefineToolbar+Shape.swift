import AppKit

extension RefineToolbarController {
    func buildSubToolbar() -> NSView {
        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        // Switch group 1: three stroke widths + fill (mutually exclusive).
        strokeButtons = StrokeWidthOption.allCases.map { option in
            let button = NSButton(frame: .zero)
            button.bezelStyle = .inline
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(strokeTapped(_:))
            button.tag = option.rawValue
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22),
            ])
            button.image = strokeDotImage(diameter: option.previewDiameter, selected: false)
            tooltip.register(button, text: option.toolTip)
            return button
        }
        for b in strokeButtons { stack.addArrangedSubview(b) }

        fillButton = NSButton(frame: .zero)
        fillButton.bezelStyle = .inline
        fillButton.isBordered = false
        fillButton.setButtonType(.momentaryChange)
        fillButton.imagePosition = .imageOnly
        fillButton.target = self
        fillButton.action = #selector(fillTapped)
        fillButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fillButton.widthAnchor.constraint(equalToConstant: 22),
            fillButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        fillButton.image = fillSwatchImage(selected: false)
        tooltip.register(fillButton, text: L10n.tr("Fill"))
        stack.addArrangedSubview(fillButton)

        let afterFillDivider = miniDivider()
        stack.addArrangedSubview(afterFillDivider)

        // Switch group 2: rectangle ↔ ellipse / circle.
        rectKindButton = iconButton(
            systemName: "rectangle",
            tooltip: L10n.tr("Rectangle"),
            enabled: true,
            action: #selector(rectKindTapped)
        )
        ovalKindButton = iconButton(
            systemName: "oval",
            tooltip: L10n.tr("Ellipse"),
            enabled: true,
            action: #selector(ovalKindTapped)
        )
        stack.addArrangedSubview(rectKindButton)
        stack.addArrangedSubview(ovalKindButton)

        afterKindDivider = miniDivider()
        stack.addArrangedSubview(afterKindDivider)

        // Shared by shape + pencil: hide fill / kind for pencil (Snipaste pen options).
        // Keep `afterKindDivider` visible for shape/pencil so stroke → line-style stays separated.
        shapeOnlyViews = [fillButton, afterFillDivider, rectKindButton, ovalKindButton]

        // Arrow start-cap dropdown (Snipaste left picker).
        let beforeArrowDivider = miniDivider()
        stack.addArrangedSubview(beforeArrowDivider)
        arrowStartCapButton = makeCapDropdownButton(
            tooltip: L10n.tr("Start cap"),
            action: #selector(arrowStartCapTapped(_:))
        )
        stack.addArrangedSubview(arrowStartCapButton)

        // Body / border line style dropdown (Snipaste middle picker + shape/pen).
        lineStyleButton = NSButton(frame: .zero)
        lineStyleButton.bezelStyle = .inline
        lineStyleButton.isBordered = false
        lineStyleButton.setButtonType(.momentaryChange)
        lineStyleButton.imagePosition = .imageOnly
        lineStyleButton.target = self
        lineStyleButton.action = #selector(lineStyleTapped(_:))
        lineStyleButton.translatesAutoresizingMaskIntoConstraints = false
        lineStyleButton.wantsLayer = true
        lineStyleButton.layer?.cornerRadius = 10
        lineStyleButton.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        lineStyleButton.layer?.borderWidth = 1
        lineStyleButton.layer?.borderColor = NSColor(calibratedWhite: 0.78, alpha: 1).cgColor
        NSLayoutConstraint.activate([
            lineStyleButton.widthAnchor.constraint(equalToConstant: 56),
            lineStyleButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        tooltip.register(lineStyleButton, text: L10n.tr("Line style"))
        stack.addArrangedSubview(lineStyleButton)

        // Arrow end-cap dropdown (Snipaste right picker).
        arrowEndCapButton = makeCapDropdownButton(
            tooltip: L10n.tr("End cap"),
            action: #selector(arrowEndCapTapped(_:))
        )
        stack.addArrangedSubview(arrowEndCapButton)

        // Caps on/off Switch: stacked “current” / “plain” previews (Snipaste).
        let switchBtn = ArrowCapsSwitchButton(frame: .zero)
        switchBtn.bezelStyle = .inline
        switchBtn.isBordered = false
        switchBtn.setButtonType(.momentaryChange)
        switchBtn.imagePosition = .imageOnly
        switchBtn.target = self
        switchBtn.action = #selector(arrowDoubleTapped)
        switchBtn.translatesAutoresizingMaskIntoConstraints = false
        switchBtn.wantsLayer = true
        NSLayoutConstraint.activate([
            switchBtn.widthAnchor.constraint(equalToConstant: 24),
            switchBtn.heightAnchor.constraint(equalToConstant: 24),
        ])
        tooltip.register(switchBtn, text: L10n.tr("Switch arrowheads"))
        arrowDoubleButton = switchBtn
        stack.addArrangedSubview(arrowDoubleButton)

        // No divider here — the shared color-section divider below is enough
        // (otherwise arrow mode shows a double rule before the palette).
        arrowOnlyViews = [
            beforeArrowDivider,
            arrowStartCapButton,
            arrowEndCapButton,
            arrowDoubleButton,
        ]

        stack.addArrangedSubview(miniDivider())

        // Color preview (24pt) + 2×10 grid: chips 11pt, gap 2pt (measured from Snipaste @2x).
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
        colorPreview = preview
        stack.addArrangedSubview(preview)

        let swatchGrid = NSStackView(views: [])
        swatchGrid.orientation = .vertical
        swatchGrid.spacing = 2
        swatchGrid.alignment = .leading
        swatchGrid.wantsLayer = true
        swatchGrid.layer?.masksToBounds = false

        let allSwatches = PaletteColor.allCases
        let columns = 10
        for rowStart in stride(from: 0, to: allSwatches.count, by: columns) {
            let row = NSStackView(views: [])
            row.orientation = .horizontal
            row.spacing = 2
            row.wantsLayer = true
            row.layer?.masksToBounds = false
            let end = min(rowStart + columns, allSwatches.count)
            for swatch in allSwatches[rowStart..<end] {
                let control = PaletteSwatchControl(swatch: swatch) { [weak self] picked in
                    guard let self else { return }
                    self.style.strokeColor = picked.color
                    self.refreshSelectionChrome()
                    self.onEvent(.styleChanged(self.style))
                }
                row.addArrangedSubview(control)
            }
            swatchGrid.addArrangedSubview(row)
        }
        stack.addArrangedSubview(swatchGrid)

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    @objc func strokeTapped(_ sender: NSButton) {
        let option = StrokeWidthOption(rawValue: sender.tag) ?? .medium
        style.strokeWidth = option.points
        style.isFilled = false
        refreshSelectionChrome()
        onEvent(.styleChanged(style))
    }

    @objc func fillTapped() {
        guard tool == .rectangle else { return }
        style.isFilled = true
        refreshSelectionChrome()
        onEvent(.styleChanged(style))
    }

    @objc func rectKindTapped() {
        kind = .rectangle
        refreshSelectionChrome()
        onEvent(.kindChanged(kind))
    }

    @objc func ovalKindTapped() {
        kind = .ellipse
        refreshSelectionChrome()
        onEvent(.kindChanged(kind))
    }

    @objc func lineStyleTapped(_ sender: NSButton) {
        guard !style.isFilled else { return }
        let menu = NSMenu()
        for option in StrokeLineStyle.allCases {
            let item = NSMenuItem(
                title: "",
                action: #selector(lineStyleMenuPicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = option.rawValue
            item.state = (option == style.lineStyle) ? .on : .off
            item.toolTip = option.toolTip
            item.image = lineStyleMenuImage(option)
            menu.addItem(item)
        }
        let point = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc func lineStyleMenuPicked(_ sender: NSMenuItem) {
        guard let option = StrokeLineStyle(rawValue: sender.tag) else { return }
        style.lineStyle = option
        style.isFilled = false
        refreshSelectionChrome()
        onEvent(.styleChanged(style))
    }

}
