import AppKit
import QuartzCore

extension RefineToolbarController {
    func makeChromeCard() -> HoverChromeCard {
        let card = HoverChromeCard()
        card.tooltip = tooltip
        return card
    }

    func embed(_ child: NSView, in card: HoverChromeCard) {
        card.installContent(child)
    }

    /// Shared mosaic / magnifier control: preview chip + slider + value (tight slider→label gap).
    func appendValueSlider(
        to stack: NSStackView,
        preview: NSView,
        minValue: Double,
        maxValue: Double,
        value: Double,
        labelText: String,
        labelWidth: CGFloat,
        action: Selector
    ) -> (slider: MosaicIntensitySlider, label: NSTextField) {
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 24),
            preview.heightAnchor.constraint(equalToConstant: 24),
        ])
        stack.addArrangedSubview(preview)

        // Nested so slider↔value sits tighter than the outer 4pt toolbar spacing.
        // spacing 0 + leading align: avoid the old right-aligned fixed-width gap.
        let cluster = NSStackView(views: [])
        cluster.orientation = .horizontal
        cluster.alignment = .centerY
        cluster.spacing = 0

        let slider = MosaicIntensitySlider(frame: .zero)
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.doubleValue = value
        slider.target = self
        slider.action = action
        slider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            slider.widthAnchor.constraint(equalToConstant: 90),
            slider.heightAnchor.constraint(equalToConstant: 18),
        ])
        cluster.addArrangedSubview(slider)

        let label = NSTextField(labelWithString: labelText)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.28, alpha: 1)
        label.alignment = .left
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: labelWidth),
        ])
        cluster.addArrangedSubview(label)

        stack.addArrangedSubview(cluster)
        return (slider, label)
    }

    func layoutPanel(content: NSView) {
        content.layoutSubtreeIfNeeded()
        let fitting = rootStack.fittingSize
        let size = CGSize(width: max(fitting.width, 280), height: max(fitting.height, 28))
        content.frame = CGRect(origin: .zero, size: size)
        panel.setContentSize(size)
    }

    func refreshSelectionChrome() {
        tintSelected(shapeButton, selected: tool == .rectangle)
        tintSelected(arrowButton, selected: tool == .arrow)
        tintSelected(pencilButton, selected: tool == .pencil)
        tintSelected(markerButton, selected: tool == .marker)
        tintSelected(mosaicButton, selected: tool == .mosaic)
        tintSelected(textButton, selected: tool == .text)
        tintSelected(stepButton, selected: tool == .step)
        tintSelected(magnifierButton, selected: tool == .magnifier)
        tintSelected(eraserButton, selected: tool == .eraser)
        colorPreview.layer?.backgroundColor = style.strokeColor.cgColor
        textColorPreview.layer?.backgroundColor = textStyle.color.cgColor
        markerColorPreview.layer?.backgroundColor = markerStyle.color.cgColor
        stepColorPreview.layer?.backgroundColor = stepStyle.color.cgColor
        magnifierColorPreview.layer?.backgroundColor = magnifierStyle.color.cgColor

        let isText = (tool == .text)
        let isMosaic = (tool == .mosaic)
        let isMarker = (tool == .marker)
        let isStep = (tool == .step)
        let isMagnifier = (tool == .magnifier)
        let isEraser = (tool == .eraser)
        strokeOptionsRow.isHidden = isText || isMosaic || isMarker || isStep || isMagnifier || isEraser
        textOptionsRow.isHidden = !isText
        mosaicOptionsRow.isHidden = !isMosaic
        markerOptionsRow.isHidden = !isMarker
        eraserOptionsRow.isHidden = !isEraser
        stepOptionsRow.isHidden = !isStep
        magnifierOptionsRow.isHidden = !isMagnifier

        let isArrow = (tool == .arrow)
        let shapeExtrasVisible = (tool == .rectangle)
        for view in shapeOnlyViews {
            view.isHidden = !shapeExtrasVisible
        }
        afterKindDivider.isHidden = isArrow || isText || isMosaic || isMarker || isStep || isMagnifier
            || isEraser
        for view in arrowOnlyViews {
            view.isHidden = !isArrow
        }

        tintSelected(magnifierRectButton, selected: magnifierKind == .rectangle)
        tintSelected(magnifierOvalButton, selected: magnifierKind == .ellipse)
        let magStroke = StrokeWidthOption.matching(magnifierStyle.strokeWidth)
        for button in magnifierStrokeButtons {
            let option = StrokeWidthOption(rawValue: button.tag) ?? .medium
            let on = option == magStroke
            button.image = strokeDotImage(diameter: option.previewDiameter, selected: on)
            tintSelected(button, selected: on)
        }
        tintSelected(magnifierIncludeButton, selected: magnifierStyle.includeAnnotations)
        magnifierScaleSlider.doubleValue = Double(magnifierStyle.scale)
        magnifierScaleLabel.stringValue = Self.formatMagnifierScale(magnifierStyle.scale)
        magnifierScalePreview.scale = magnifierStyle.scale
        magnifierScalePreview.needsDisplay = true

        let selectedStroke = StrokeWidthOption.matching(style.strokeWidth)
        let treatAsStroke = !style.isFilled || tool == .pencil || tool == .arrow
        for button in strokeButtons {
            let option = StrokeWidthOption(rawValue: button.tag) ?? .medium
            let on = treatAsStroke && option == selectedStroke
            button.image = strokeDotImage(diameter: option.previewDiameter, selected: on)
            tintSelected(button, selected: on)
        }
        fillButton.image = fillSwatchImage(selected: style.isFilled && tool == .rectangle)
        tintSelected(fillButton, selected: style.isFilled && tool == .rectangle)

        tintSelected(rectKindButton, selected: kind == .rectangle)
        tintSelected(ovalKindButton, selected: kind == .ellipse)

        lineStyleButton.image = lineStylePreviewImage(style.lineStyle)
        tooltip.register(lineStyleButton, text: isArrow ? "Line style" : "Border style")
        let lineEnabled = treatAsStroke
        lineStyleButton.isEnabled = lineEnabled
        lineStyleButton.alphaValue = lineEnabled ? 1 : 0.45

        arrowStartCapButton.image = arrowCapPreviewImage(cap: arrowCaps.start, pointing: .left)
        arrowEndCapButton.image = arrowCapPreviewImage(cap: arrowCaps.end, pointing: .right)
        if arrowCaps.hasCaps {
            lastArrowedCaps = arrowCaps
        }
        arrowDoubleButton.image = arrowCapsSwitchImage()
        // Don’t use the blue selected chrome — Switch uses black / light gray glyphs.
        arrowDoubleButton.contentTintColor = nil
        arrowDoubleButton.layer?.backgroundColor = nil

        tintSelected(textBoldButton, selected: textStyle.isBold)
        tintSelected(textItalicButton, selected: textStyle.isItalic)
        tintSelected(textBackgroundButton, selected: textStyle.hasBackground)
        let sizeLabel = "\(Int(textStyle.fontSize.rounded()))"
        textSizeButton.title = sizeLabel

        refreshMosaicChrome()
        refreshMarkerChrome()
        refreshEraserChrome()
        refreshStepChrome()
    }

    func divider() -> NSView {
        let wrap = NSView(frame: .zero)
        wrap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrap.widthAnchor.constraint(equalToConstant: 7),
            wrap.heightAnchor.constraint(equalToConstant: 24),
        ])
        let line = NSView(frame: .zero)
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 1).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 14),
            line.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
        ])
        return wrap
    }

    func miniDivider() -> NSView {
        let wrap = NSView(frame: .zero)
        wrap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrap.widthAnchor.constraint(equalToConstant: 6),
            wrap.heightAnchor.constraint(equalToConstant: 20),
        ])
        let line = NSView(frame: .zero)
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 1).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 12),
            line.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
        ])
        return wrap
    }

    func orderFront() {
        panel.orderFrontRegardless()
    }

    func close() {
        tooltip.hide()
        panel.orderOut(nil)
        panel.close()
    }

    func containsGlobalPoint(_ point: CGPoint) -> Bool {
        panel.frame.contains(point)
    }

    func reposition(around selection: CGRect) {
        tooltip.hide()
        let size = panel.frame.size
        let gap: CGFloat = 4
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(selection) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        // Prefer below the selection, right-aligned to the selection’s trailing edge.
        var origin = CGPoint(
            x: selection.maxX - size.width,
            y: selection.minY - size.height - gap
        )
        if origin.y < screen.frame.minY + 4 {
            origin.y = selection.maxY + gap
        }

        origin.x = min(max(origin.x, screen.frame.minX + 4), screen.frame.maxX - size.width - 4)
        origin.y = min(max(origin.y, screen.frame.minY + 4), screen.frame.maxY - size.height - 4)

        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

}
