import AppKit
import CoreImage
import QuartzCore

// Eraser sub-toolbar + actions.

extension RefineToolbarController {
    func buildEraserSubToolbar() -> NSView {
        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        eraserBrushButtons = EraserStyle.brushPresets.enumerated().map { index, width in
            let button = NSButton(frame: .zero)
            button.bezelStyle = .inline
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(eraserBrushTapped(_:))
            button.tag = Int(width)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 24),
                button.heightAnchor.constraint(equalToConstant: 24),
            ])
            let preview = EraserStyle.brushPreviewDiameters[index]
            button.image = strokeDotImage(diameter: preview, selected: false)
            tooltip.register(button, text: Self.brushSizeTooltip(index: index))
            return button
        }
        for button in eraserBrushButtons {
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(miniDivider())

        eraserRectButton = iconButton(
            image: mosaicBrushKindIcon(kind: .rectangle),
            tooltip: "Rectangular area",
            enabled: true,
            action: #selector(eraserRectTapped)
        )
        eraserOvalButton = iconButton(
            image: mosaicBrushKindIcon(kind: .ellipse),
            tooltip: "Elliptical area",
            enabled: true,
            action: #selector(eraserOvalTapped)
        )
        stack.addArrangedSubview(eraserRectButton)
        stack.addArrangedSubview(eraserOvalButton)

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    func refreshEraserChrome() {
        let selectedWidth = EraserStyle.nearestBrushPreset(eraserStyle.brushWidth)
        let isFreehand = (eraserDrawMode == .freehand)
        for (index, button) in eraserBrushButtons.enumerated() {
            let width = EraserStyle.brushPresets[index]
            let on = isFreehand && abs(width - selectedWidth) < 0.5
            let preview = EraserStyle.brushPreviewDiameters[index]
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = strokeDotImage(diameter: preview, selected: on)
            tintSelected(button, selected: on)
        }
        tintSelected(eraserRectButton, selected: eraserDrawMode == .rectangle)
        tintSelected(eraserOvalButton, selected: eraserDrawMode == .ellipse)
    }

    @objc func eraserBrushTapped(_ sender: NSButton) {
        eraserStyle.brushWidth = EraserStyle.nearestBrushPreset(CGFloat(sender.tag))
        eraserDrawMode = .freehand
        refreshEraserChrome()
        onEvent(.eraserDrawModeChanged(eraserDrawMode))
        onEvent(.eraserStyleChanged(eraserStyle))
    }

    @objc func eraserRectTapped() {
        eraserDrawMode = .rectangle
        refreshEraserChrome()
        onEvent(.eraserDrawModeChanged(eraserDrawMode))
    }

    @objc func eraserOvalTapped() {
        eraserDrawMode = .ellipse
        refreshEraserChrome()
        onEvent(.eraserDrawModeChanged(eraserDrawMode))
    }

}
