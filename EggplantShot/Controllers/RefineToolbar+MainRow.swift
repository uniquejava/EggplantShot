import AppKit

extension RefineToolbarController {
    func buildMainRow(primaryAction: SelectionOverlayController.ConfirmAction) -> NSView {
        shapeButton = iconButton(
            systemName: "rectangle",
            tooltip: "Shape (A)",
            enabled: true,
            action: #selector(shapeTapped)
        )
        arrowButton = iconButton(
            systemName: "arrow.up.right",
            tooltip: "Arrow (S)",
            enabled: true,
            action: #selector(arrowTapped)
        )
        pencilButton = iconButton(
            image: pencilToolIcon(),
            tooltip: "Pen (D)",
            enabled: true,
            action: #selector(pencilTapped)
        )
        mosaicButton = iconButton(
            image: mosaicToolIcon(),
            tooltip: "Mosaic (M)",
            enabled: true,
            action: #selector(mosaicTapped)
        )
        markerButton = iconButton(
            systemName: "paintbrush.pointed",
            tooltip: "Marker (F)",
            enabled: true,
            action: #selector(markerTapped)
        )
        textButton = iconButton(
            image: textToolIcon(),
            tooltip: "Text (T)",
            enabled: true,
            action: #selector(textTapped)
        )
        stepButton = iconButton(
            image: stepToolIcon(),
            tooltip: "Number (N)",
            enabled: true,
            action: #selector(stepTapped)
        )
        magnifierButton = iconButton(
            systemName: "magnifyingglass",
            tooltip: "Magnifier",
            enabled: true,
            action: #selector(magnifierTapped)
        )
        eraserButton = iconButton(
            systemName: "eraser",
            tooltip: "Eraser (E)",
            enabled: true,
            action: #selector(eraserTapped)
        )

        let annotateViews: [NSView] = [
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
            tooltip: "Undo (⌘Z)",
            enabled: false,
            action: #selector(undoTapped)
        )
        redoButton = iconButton(
            systemName: "arrow.uturn.forward",
            tooltip: "Redo (⇧⌘Z)",
            enabled: false,
            action: #selector(redoTapped)
        )
        let editViews: [NSView] = [
            iconButton(
                systemName: "doc.text.viewfinder",
                tooltip: "OCR (O)",
                enabled: true,
                action: #selector(ocrTapped)
            ),
            undoButton,
            redoButton,
        ]

        let cancel = iconButton(systemName: "xmark", tooltip: "Cancel", enabled: true, action: #selector(cancelTapped))
        let pin = iconButton(systemName: "pin.fill", tooltip: "Pin (P)", enabled: true, action: #selector(pinTapped))
        let save = iconButton(systemName: "square.and.arrow.down", tooltip: "Save (⌘S)", enabled: true, action: #selector(saveTapped))
        let copy = iconButton(systemName: "doc.on.doc", tooltip: "Copy (⌘C)", enabled: true, action: #selector(copyTapped))
        let more = iconButton(systemName: "ellipsis", tooltip: "More", enabled: false, action: nil)

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
