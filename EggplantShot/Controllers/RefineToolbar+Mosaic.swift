import AppKit
import CoreImage
import QuartzCore

// Mosaic sub-toolbar + actions.

extension RefineToolbarController {
    func buildMosaicSubToolbar() -> NSView {
        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        mosaicBrushButtons = MosaicStyle.brushPresets.enumerated().map { index, width in
            let button = NSButton(frame: .zero)
            button.bezelStyle = .inline
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(mosaicBrushTapped(_:))
            button.tag = Int(width)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 24),
                button.heightAnchor.constraint(equalToConstant: 24),
            ])
            let preview = MosaicStyle.brushPreviewDiameters[index]
            button.image = strokeDotImage(diameter: preview, selected: false)
            tooltip.register(button, text: Self.brushSizeTooltip(index: index))
            return button
        }
        for button in mosaicBrushButtons {
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(miniDivider())

        mosaicRectButton = iconButton(
            image: mosaicBrushKindIcon(kind: .rectangle),
            tooltip: L10n.tr("Rectangular area"),
            enabled: true,
            action: #selector(mosaicRectTapped)
        )
        mosaicOvalButton = iconButton(
            image: mosaicBrushKindIcon(kind: .ellipse),
            tooltip: L10n.tr("Elliptical area"),
            enabled: true,
            action: #selector(mosaicOvalTapped)
        )
        stack.addArrangedSubview(mosaicRectButton)
        stack.addArrangedSubview(mosaicOvalButton)
        stack.addArrangedSubview(miniDivider())

        // The preview chip *is* the effect switch (Snipaste puts a toggle in this slot). It already
        // renders the armed effect, so it reads as a state readout you can click; the slider knob
        // squares up in Pixelate mode as the second, always-visible half of that readout.
        mosaicIntensityPreview = MosaicIntensityPreviewView(frame: .zero)
        mosaicIntensityPreview.blurSigma = mosaicStyle.blurSigma
        mosaicIntensityPreview.blockSize = mosaicStyle.blockSize
        mosaicIntensityPreview.effect = mosaicStyle.effect
        mosaicIntensityPreview.target = self
        mosaicIntensityPreview.action = #selector(mosaicEffectToggled)
        tooltip.register(mosaicIntensityPreview, text: L10n.tr("Toggle blur / pixelate"))
        let range = MosaicStyle.strengthRange(for: mosaicStyle.effect)
        let intensityControls = appendValueSlider(
            to: stack,
            preview: mosaicIntensityPreview,
            minValue: Double(range.lowerBound),
            maxValue: Double(range.upperBound),
            value: Double(mosaicStyle.strength),
            labelText: MosaicStyle.formatStrength(mosaicStyle.strength, effect: mosaicStyle.effect),
            // Fits "16" and "0.8" alike — the label swaps units with the effect.
            labelWidth: 24,
            action: #selector(mosaicIntensityChanged(_:))
        )
        mosaicIntensitySlider = intensityControls.slider
        mosaicIntensityLabel = intensityControls.label

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// Marker = mosaic layout with color card instead of blur intensity.
    func refreshMosaicChrome() {
        let selectedWidth = MosaicStyle.nearestBrushPreset(mosaicStyle.brushWidth)
        let isFreehand = (mosaicDrawMode == .freehand)
        for (index, button) in mosaicBrushButtons.enumerated() {
            let width = MosaicStyle.brushPresets[index]
            let on = isFreehand && abs(width - selectedWidth) < 0.5
            let preview = MosaicStyle.brushPreviewDiameters[index]
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = strokeDotImage(diameter: preview, selected: on)
            tintSelected(button, selected: on)
        }
        tintSelected(mosaicRectButton, selected: mosaicDrawMode == .rectangle)
        tintSelected(mosaicOvalButton, selected: mosaicDrawMode == .ellipse)

        // The slider changes units with the effect, so its bounds and snap move too.
        let range = MosaicStyle.strengthRange(for: mosaicStyle.effect)
        mosaicIntensitySlider.minValue = Double(range.lowerBound)
        mosaicIntensitySlider.maxValue = Double(range.upperBound)
        mosaicIntensitySlider.step = Double(MosaicStyle.strengthStep(for: mosaicStyle.effect))
        mosaicIntensitySlider.doubleValue = Double(mosaicStyle.strength)
        mosaicIntensitySlider.knobIsSquare = (mosaicStyle.effect == .pixelate)
        mosaicIntensityLabel.stringValue = MosaicStyle.formatStrength(
            mosaicStyle.strength, effect: mosaicStyle.effect)
        mosaicIntensityPreview.blurSigma = mosaicStyle.blurSigma
        mosaicIntensityPreview.blockSize = mosaicStyle.blockSize
        mosaicIntensityPreview.effect = mosaicStyle.effect
        mosaicIntensityPreview.needsDisplay = true
    }

    func mosaicToolIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let frame = rect.insetBy(dx: 1.25, dy: 1.25)
            let border = NSBezierPath(roundedRect: frame, xRadius: 2.0, yRadius: 2.0)
            border.lineWidth = 1.2
            NSColor.black.setStroke()
            border.stroke()

            // Cells hug the inner edge of the stroke (almost flush).
            let edge: CGFloat = 0.85
            let gap: CGFloat = 0.9
            let inner = frame.insetBy(dx: edge, dy: edge)
            let cell = (inner.width - gap) / 2
            let darkCells = [
                CGRect(x: inner.minX, y: inner.maxY - cell, width: cell, height: cell), // top-left
                CGRect(x: inner.maxX - cell, y: inner.minY, width: cell, height: cell), // bottom-right
            ]
            NSColor.black.setFill()
            for cellRect in darkCells {
                NSBezierPath(roundedRect: cellRect, xRadius: 0.9, yRadius: 0.9).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Filled disk + punched “1” — same chrome as the first step-style option.
    func mosaicBrushKindIcon(kind: MosaicDrawMode) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let outer = rect.insetBy(dx: 2.5, dy: 2.5)
            let path: NSBezierPath
            switch kind {
            case .rectangle, .freehand:
                path = NSBezierPath(rect: outer)
            case .ellipse:
                path = NSBezierPath(ovalIn: outer)
            }
            path.lineWidth = 1.5
            path.lineJoinStyle = .miter
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc func mosaicBrushTapped(_ sender: NSButton) {
        mosaicStyle.brushWidth = MosaicStyle.nearestBrushPreset(CGFloat(sender.tag))
        mosaicDrawMode = .freehand
        refreshMosaicChrome()
        onEvent(.mosaicDrawModeChanged(mosaicDrawMode))
        onEvent(.mosaicStyleChanged(mosaicStyle))
    }

    @objc func mosaicRectTapped() {
        mosaicDrawMode = .rectangle
        refreshMosaicChrome()
        onEvent(.mosaicDrawModeChanged(mosaicDrawMode))
    }

    @objc func mosaicOvalTapped() {
        mosaicDrawMode = .ellipse
        refreshMosaicChrome()
        onEvent(.mosaicDrawModeChanged(mosaicDrawMode))
    }

    /// Writes through `strength`, which routes to `blurSigma` or `blockSize` by armed effect — so
    /// each mode keeps its own value and switching back restores it.
    @objc func mosaicIntensityChanged(_ sender: MosaicIntensitySlider) {
        mosaicStyle.strength = CGFloat(sender.doubleValue)
        mosaicIntensityLabel.stringValue = MosaicStyle.formatStrength(
            mosaicStyle.strength, effect: mosaicStyle.effect)
        mosaicIntensityPreview.blurSigma = mosaicStyle.blurSigma
        mosaicIntensityPreview.blockSize = mosaicStyle.blockSize
        mosaicIntensityPreview.needsDisplay = true
        onEvent(.mosaicStyleChanged(mosaicStyle))
    }

    @objc func mosaicEffectToggled() {
        setMosaicEffect(mosaicStyle.effect == .blur ? .pixelate : .blur)
    }

    /// Effect rides on `MosaicStyle`, so this reuses `mosaicStyleChanged` — which also re-styles a
    /// selected mosaic mark, letting you convert an existing blur to blocks the way strength does.
    func setMosaicEffect(_ effect: MosaicEffect) {
        guard mosaicStyle.effect != effect else { return }
        mosaicStyle.effect = effect
        refreshMosaicChrome()
        onEvent(.mosaicStyleChanged(mosaicStyle))
    }
}
