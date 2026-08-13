import AppKit
import CoreImage
import QuartzCore

// Magnifier sub-toolbar + actions.

extension RefineToolbarController {
    func buildMagnifierSubToolbar() -> NSView {
        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        magnifierStrokeButtons = StrokeWidthOption.allCases.map { option in
            let button = NSButton(frame: .zero)
            button.bezelStyle = .inline
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.imagePosition = .imageOnly
            button.toolTip = "Stroke"
            button.target = self
            button.action = #selector(magnifierStrokeTapped(_:))
            button.tag = option.rawValue
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22),
            ])
            button.image = strokeDotImage(diameter: option.previewDiameter, selected: false)
            return button
        }
        for button in magnifierStrokeButtons {
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(miniDivider())

        magnifierRectButton = iconButton(
            systemName: "rectangle",
            tooltip: "Rectangle",
            enabled: true,
            action: #selector(magnifierRectTapped)
        )
        magnifierOvalButton = iconButton(
            systemName: "oval",
            tooltip: "Ellipse / Circle",
            enabled: true,
            action: #selector(magnifierOvalTapped)
        )
        stack.addArrangedSubview(magnifierRectButton)
        stack.addArrangedSubview(magnifierOvalButton)
        stack.addArrangedSubview(miniDivider())

        magnifierIncludeButton = iconButton(
            systemName: "rectangle.on.rectangle",
            tooltip: "Include annotations in magnifier",
            enabled: true,
            action: #selector(magnifierIncludeTapped)
        )
        stack.addArrangedSubview(magnifierIncludeButton)
        stack.addArrangedSubview(miniDivider())

        magnifierScalePreview = MagnifierScalePreviewView(frame: .zero)
        magnifierScalePreview.scale = magnifierStyle.scale
        let scaleControls = appendValueSlider(
            to: stack,
            preview: magnifierScalePreview,
            minValue: Double(MagnifierStyle.scaleRange.lowerBound),
            maxValue: Double(MagnifierStyle.scaleRange.upperBound),
            value: Double(magnifierStyle.scale),
            labelText: Self.formatMagnifierScale(magnifierStyle.scale),
            labelWidth: 28,
            action: #selector(magnifierScaleChanged(_:))
        )
        magnifierScaleSlider = scaleControls.slider
        magnifierScaleLabel = scaleControls.label
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
        magnifierColorPreview = preview
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
                    self.magnifierStyle.color = picked.color
                    self.refreshSelectionChrome()
                    self.emitMagnifierChanged()
                }
                row.addArrangedSubview(control)
            }
            swatchGrid.addArrangedSubview(row)
        }
        stack.addArrangedSubview(swatchGrid)

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    @objc func magnifierRectTapped() {
        magnifierKind = .rectangle
        refreshSelectionChrome()
        emitMagnifierChanged()
    }

    @objc func magnifierOvalTapped() {
        magnifierKind = .ellipse
        refreshSelectionChrome()
        emitMagnifierChanged()
    }

    @objc func magnifierStrokeTapped(_ sender: NSButton) {
        let option = StrokeWidthOption(rawValue: sender.tag) ?? .medium
        magnifierStyle.strokeWidth = option.points
        refreshSelectionChrome()
        emitMagnifierChanged()
    }

    @objc func magnifierIncludeTapped() {
        magnifierStyle.includeAnnotations.toggle()
        refreshSelectionChrome()
        emitMagnifierChanged()
    }

    @objc func magnifierScaleChanged(_ sender: MosaicIntensitySlider) {
        magnifierStyle.scale = MagnifierStyle.clampedScale(CGFloat(sender.doubleValue))
        magnifierScaleLabel.stringValue = Self.formatMagnifierScale(magnifierStyle.scale)
        magnifierScalePreview.scale = magnifierStyle.scale
        magnifierScalePreview.needsDisplay = true
        emitMagnifierChanged()
    }

    static func formatMagnifierScale(_ scale: CGFloat) -> String {
        String(format: "%.2f", MagnifierStyle.clampedScale(scale))
    }

    func emitMagnifierChanged() {
        onEvent(.magnifierChanged(kind: magnifierKind, style: magnifierStyle))
    }

}
