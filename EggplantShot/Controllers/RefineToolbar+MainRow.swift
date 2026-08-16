import AppKit

extension RefineToolbarController {
    func buildMainRow(primaryAction: SelectionOverlayController.ConfirmAction) -> NSView {
        selectButton = iconButton(
            systemName: "cursorarrow",
            tooltip: L10n.tr("Move (V)"),
            enabled: false,
            action: #selector(selectTapped)
        )
        shapeButton = iconButton(
            systemName: "rectangle",
            tooltip: L10n.tr("Shape (S)"),
            enabled: true,
            action: #selector(shapeTapped)
        )
        arrowButton = iconButton(
            systemName: "arrow.up.right",
            tooltip: L10n.tr("Arrow (A)"),
            enabled: true,
            action: #selector(arrowTapped)
        )
        pencilButton = iconButton(
            image: pencilToolIcon(),
            tooltip: L10n.tr("Pen (D)"),
            enabled: true,
            action: #selector(pencilTapped)
        )
        mosaicButton = iconButton(
            image: mosaicToolIcon(),
            tooltip: L10n.tr("Blur/Mosaic (M)"),
            enabled: true,
            action: #selector(mosaicTapped)
        )
        markerButton = iconButton(
            systemName: "paintbrush.pointed",
            tooltip: L10n.tr("Marker (F)"),
            enabled: true,
            action: #selector(markerTapped)
        )
        textButton = iconButton(
            image: textToolIcon(),
            tooltip: L10n.tr("Text (I / T)"),
            enabled: true,
            action: #selector(textTapped)
        )
        stepButton = iconButton(
            image: stepToolIcon(),
            tooltip: L10n.tr("Number (N)"),
            enabled: true,
            action: #selector(stepTapped)
        )
        magnifierButton = iconButton(
            systemName: "magnifyingglass",
            tooltip: L10n.tr("Magnifier"),
            enabled: true,
            action: #selector(magnifierTapped)
        )
        eraserButton = iconButton(
            systemName: "eraser",
            tooltip: L10n.tr("Eraser (E)"),
            enabled: true,
            action: #selector(eraserTapped)
        )

        let annotateViews: [NSView] = [
            selectButton,
            shapeButton,
            arrowButton,
            pencilButton,
            markerButton,
            mosaicButton,
            textButton,
            stepButton,
            magnifierButton,
            eraserButton,
        ]
        undoButton = iconButton(
            systemName: "arrow.uturn.backward",
            tooltip: L10n.tr("Undo (⌘Z)"),
            enabled: false,
            action: #selector(undoTapped)
        )
        redoButton = iconButton(
            systemName: "arrow.uturn.forward",
            tooltip: L10n.tr("Redo (⇧⌘Z)"),
            enabled: false,
            action: #selector(redoTapped)
        )
        let editViews: [NSView] = [
            iconButton(
                systemName: "doc.text.viewfinder",
                tooltip: L10n.tr("OCR/QR code (O)"),
                enabled: true,
                action: #selector(ocrTapped)
            ),
            undoButton,
            redoButton,
        ]

        let cancel = iconButton(systemName: "xmark", tooltip: L10n.tr("Cancel (Esc)"), enabled: true, action: #selector(cancelTapped))
        let pin = iconButton(systemName: "pin.fill", tooltip: L10n.tr("Pin (P)"), enabled: true, action: #selector(pinTapped))
        let save = iconButton(systemName: "square.and.arrow.down", tooltip: L10n.tr("Save (⌘S)"), enabled: true, action: #selector(saveTapped))
        let copy = iconButton(systemName: "doc.on.doc", tooltip: L10n.tr("Copy (⌘C)"), enabled: true, action: #selector(copyTapped))
        let more = iconButton(systemName: "ellipsis", tooltip: L10n.tr("More"), enabled: false, action: nil)

        let primary: NSButton
        switch primaryAction {
        case .pin, .save:
            primary = pin
        case .copy:
            primary = copy
        }
        primary.keyEquivalent = "\r"
        panel.defaultButtonCell = primary.cell as? NSButtonCell

        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)

        for v in annotateViews { stack.addArrangedSubview(v) }
        stack.addArrangedSubview(divider())
        for v in editViews { stack.addArrangedSubview(v) }
        stack.addArrangedSubview(divider())
        for v in [cancel, pin, save, copy, more] { stack.addArrangedSubview(v) }
        return stack
    }

    @objc func selectTapped() {
        selectTool(tool == .select ? .none : .select)
    }

    @objc func shapeTapped() {
        selectTool(tool == .rectangle ? .none : .rectangle)
    }

    @objc func arrowTapped() {
        selectTool(tool == .arrow ? .none : .arrow)
    }

    @objc func pencilTapped() {
        selectTool(tool == .pencil ? .none : .pencil)
    }

    @objc func mosaicTapped() {
        selectTool(tool == .mosaic ? .none : .mosaic)
    }

    @objc func markerTapped() {
        selectTool(tool == .marker ? .none : .marker)
    }

    @objc func textTapped() {
        selectTool(tool == .text ? .none : .text)
    }

    @objc func stepTapped() {
        selectTool(tool == .step ? .none : .step)
    }

    @objc func magnifierTapped() {
        selectTool(tool == .magnifier ? .none : .magnifier)
    }

    @objc func eraserTapped() {
        selectTool(tool == .eraser ? .none : .eraser)
    }

    @objc func pinTapped() { onEvent(.confirm(.pin)) }
    @objc func copyTapped() { onEvent(.confirm(.copy)) }
    @objc func saveTapped() { onEvent(.confirm(.save)) }
    @objc func cancelTapped() { onEvent(.confirm(.cancel)) }
    @objc func ocrTapped() { onEvent(.ocr) }
    @objc func undoTapped() { onEvent(.undo) }
    @objc func redoTapped() { onEvent(.redo) }

}
