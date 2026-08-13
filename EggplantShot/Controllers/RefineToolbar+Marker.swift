import AppKit
import CoreImage
import QuartzCore

// Marker sub-toolbar + actions.

extension RefineToolbarController {
    func buildMarkerSubToolbar() -> NSView {
        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        markerBrushButtons = MarkerStyle.brushPresets.enumerated().map { index, width in
            let button = NSButton(frame: .zero)
            button.bezelStyle = .inline
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.imagePosition = .imageOnly
            button.toolTip = "Brush \(Int(width))"
            button.target = self
            button.action = #selector(markerBrushTapped(_:))
            button.tag = Int(width)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 24),
                button.heightAnchor.constraint(equalToConstant: 24),
            ])
            let preview = MarkerStyle.brushPreviewDiameters[index]
            button.image = strokeDotImage(diameter: preview, selected: false)
            return button
        }
        for button in markerBrushButtons {
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(miniDivider())

        markerRectButton = iconButton(
            image: mosaicBrushKindIcon(kind: .rectangle),
            tooltip: "Rectangle region",
            enabled: true,
            action: #selector(markerRectTapped)
        )
        markerOvalButton = iconButton(
            image: mosaicBrushKindIcon(kind: .ellipse),
            tooltip: "Oval region",
            enabled: true,
            action: #selector(markerOvalTapped)
        )
        stack.addArrangedSubview(markerRectButton)
        stack.addArrangedSubview(markerOvalButton)
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
        markerColorPreview = preview
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
                    self.markerStyle.color = picked.color
                    self.refreshSelectionChrome()
                    self.onEvent(.markerStyleChanged(self.markerStyle))
                }
                row.addArrangedSubview(control)
            }
            swatchGrid.addArrangedSubview(row)
        }
        stack.addArrangedSubview(swatchGrid)

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// Eraser = mosaic’s first five icons only (brush sizes + rect / oval region).
    func refreshMarkerChrome() {
        let selectedWidth = MarkerStyle.nearestBrushPreset(markerStyle.brushWidth)
        let isFreehand = (markerDrawMode == .freehand)
        for (index, button) in markerBrushButtons.enumerated() {
            let width = MarkerStyle.brushPresets[index]
            let on = isFreehand && abs(width - selectedWidth) < 0.5
            let preview = MarkerStyle.brushPreviewDiameters[index]
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = strokeDotImage(diameter: preview, selected: on)
            tintSelected(button, selected: on)
        }
        tintSelected(markerRectButton, selected: markerDrawMode == .rectangle)
        tintSelected(markerOvalButton, selected: markerDrawMode == .ellipse)
        markerColorPreview.layer?.backgroundColor = markerStyle.color.cgColor
    }

    @objc func markerBrushTapped(_ sender: NSButton) {
        markerStyle.brushWidth = MarkerStyle.nearestBrushPreset(CGFloat(sender.tag))
        markerDrawMode = .freehand
        refreshMarkerChrome()
        onEvent(.markerDrawModeChanged(markerDrawMode))
        onEvent(.markerStyleChanged(markerStyle))
    }

    @objc func markerRectTapped() {
        markerDrawMode = .rectangle
        refreshMarkerChrome()
        onEvent(.markerDrawModeChanged(markerDrawMode))
    }

    @objc func markerOvalTapped() {
        markerDrawMode = .ellipse
        refreshMarkerChrome()
        onEvent(.markerDrawModeChanged(markerDrawMode))
    }

}
