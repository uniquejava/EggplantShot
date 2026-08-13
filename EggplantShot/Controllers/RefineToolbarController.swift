import AppKit
import CoreImage
import QuartzCore

// MARK: - Toolbar

@MainActor
final class RefineToolbarController: NSObject {
    enum ConfirmAction {
        case pin
        case copy
        case save
        case cancel
    }

    enum Event {
        case confirm(ConfirmAction)
        case selectTool(AnnotateTool)
        case styleChanged(AnnotationStyle)
        case textStyleChanged(TextStyle)
        case mosaicStyleChanged(MosaicStyle)
        case mosaicDrawModeChanged(MosaicDrawMode)
        case kindChanged(ShapeKind)
        case arrowCapsChanged(ArrowCaps)
        case undo
        case redo
    }

    private let panel: NSPanel
    private let onEvent: (Event) -> Void
    private var style: AnnotationStyle
    private var textStyle: TextStyle
    private var mosaicStyle: MosaicStyle
    private var mosaicDrawMode: MosaicDrawMode
    private var tool: AnnotateTool
    private var kind: ShapeKind
    private var arrowCaps: ArrowCaps

    private let rootStack = NSStackView()
    private var shapeButton: NSButton!
    private var arrowButton: NSButton!
    private var pencilButton: NSButton!
    private var mosaicButton: NSButton!
    private var textButton: NSButton!
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var subToolbarContainer: NSView!
    /// Shape/pencil/arrow options row (stroke / fill / kind / line / palette).
    private var strokeOptionsRow: NSView!
    /// Text options row (B / I / bg / size / palette).
    private var textOptionsRow: NSView!
    /// Mosaic options row (brush / kind / intensity).
    private var mosaicOptionsRow: NSView!
    /// Shape-only chrome (fill + rect/oval). Hidden for pencil / arrow.
    private var shapeOnlyViews: [NSView] = []
    /// Divider after shape kind group; visible for shape/pencil, hidden for arrow.
    private var afterKindDivider: NSView!
    /// Arrow-only chrome (start / end caps + double Switch). Hidden for shape / pencil.
    private var arrowOnlyViews: [NSView] = []
    private var strokeButtons: [NSButton] = []
    private var fillButton: NSButton!
    private var rectKindButton: NSButton!
    private var ovalKindButton: NSButton!
    private var lineStyleButton: NSButton!
    private var arrowStartCapButton: NSButton!
    private var arrowEndCapButton: NSButton!
    private var arrowDoubleButton: NSButton!
    /// Caps to restore when Switch toggles arrows back on (Snipaste memory).
    private var lastArrowedCaps: ArrowCaps = .default
    private var colorPreview: NSView!
    private var textBoldButton: NSButton!
    private var textItalicButton: NSButton!
    private var textBackgroundButton: NSButton!
    private var textSizeButton: NSButton!
    private var textColorPreview: NSView!
    private var mosaicBrushButtons: [NSButton] = []
    private var mosaicRectButton: NSButton!
    private var mosaicOvalButton: NSButton!
    private var mosaicIntensityPreview: MosaicIntensityPreviewView!
    private var mosaicIntensitySlider: NSSlider!
    private var mosaicIntensityLabel: NSTextField!

    init(
        primaryAction: SelectionOverlayController.ConfirmAction,
        initialTool: AnnotateTool,
        initialStyle: AnnotationStyle,
        initialKind: ShapeKind,
        initialArrowCaps: ArrowCaps,
        initialTextStyle: TextStyle,
        initialMosaicStyle: MosaicStyle = .default,
        initialMosaicDrawMode: MosaicDrawMode = .freehand,
        onEvent: @escaping (Event) -> Void
    ) {
        self.onEvent = onEvent
        self.style = initialStyle
        self.textStyle = initialTextStyle
        self.mosaicStyle = initialMosaicStyle
        self.mosaicDrawMode = initialMosaicDrawMode
        self.tool = initialTool
        self.kind = initialKind
        self.arrowCaps = initialArrowCaps
        if initialArrowCaps.hasCaps {
            self.lastArrowedCaps = initialArrowCaps
        }
        self.panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let content = RefineToolbarView(frame: .zero)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        // Snipaste: two separate chrome cards with a small gap (~4pt).
        rootStack.spacing = 4
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let mainCard = makeChromeCard()
        let mainRow = buildMainRow(primaryAction: primaryAction)
        embed(mainRow, in: mainCard)

        let optionsCard = makeChromeCard()
        let optionsStack = NSStackView(views: [])
        optionsStack.orientation = .vertical
        optionsStack.alignment = .leading
        optionsStack.spacing = 0
        strokeOptionsRow = buildSubToolbar()
        textOptionsRow = buildTextSubToolbar()
        mosaicOptionsRow = buildMosaicSubToolbar()
        optionsStack.addArrangedSubview(strokeOptionsRow)
        optionsStack.addArrangedSubview(textOptionsRow)
        optionsStack.addArrangedSubview(mosaicOptionsRow)
        embed(optionsStack, in: optionsCard)
        subToolbarContainer = optionsCard
        subToolbarContainer.isHidden = (initialTool == .none)

        rootStack.addArrangedSubview(mainCard)
        rootStack.addArrangedSubview(subToolbarContainer)

        content.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: content.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        refreshSelectionChrome()
        layoutPanel(content: content)

        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = content
    }

    private func buildMainRow(primaryAction: SelectionOverlayController.ConfirmAction) -> NSView {
        shapeButton = iconButton(
            systemName: "rectangle",
            tooltip: "Rectangle",
            enabled: true,
            action: #selector(shapeTapped)
        )
        arrowButton = iconButton(
            systemName: "arrow.up.right",
            tooltip: "Arrow",
            enabled: true,
            action: #selector(arrowTapped)
        )
        pencilButton = iconButton(
            systemName: "pencil",
            tooltip: "Pen",
            enabled: true,
            action: #selector(pencilTapped)
        )
        mosaicButton = iconButton(
            image: mosaicToolIcon(),
            tooltip: "Mosaic",
            enabled: true,
            action: #selector(mosaicTapped)
        )
        textButton = iconButton(
            image: textToolIcon(),
            tooltip: "Text",
            enabled: true,
            action: #selector(textTapped)
        )

        let annotateViews: [NSView] = [
            shapeButton,
            arrowButton,
            pencilButton,
            iconButton(systemName: "paintbrush.pointed", tooltip: "Marker", enabled: false, action: nil),
            mosaicButton,
            textButton,
            iconButton(systemName: "1.circle", tooltip: "Step", enabled: false, action: nil),
            iconButton(systemName: "magnifyingglass", tooltip: "Magnifier", enabled: false, action: nil),
            iconButton(systemName: "eraser", tooltip: "Eraser", enabled: false, action: nil),
        ]
        undoButton = iconButton(
            systemName: "arrow.uturn.backward",
            tooltip: "Undo",
            enabled: false,
            action: #selector(undoTapped)
        )
        redoButton = iconButton(
            systemName: "arrow.uturn.forward",
            tooltip: "Redo",
            enabled: false,
            action: #selector(redoTapped)
        )
        let editViews: [NSView] = [
            iconButton(systemName: "doc.text.viewfinder", tooltip: "OCR", enabled: false, action: nil),
            undoButton,
            redoButton,
        ]

        let cancel = iconButton(systemName: "xmark", tooltip: "Cancel", enabled: true, action: #selector(cancelTapped))
        let pin = iconButton(systemName: "pin.fill", tooltip: "Pin", enabled: true, action: #selector(pinTapped))
        let save = iconButton(systemName: "square.and.arrow.down", tooltip: "Save", enabled: true, action: #selector(saveTapped))
        let copy = iconButton(systemName: "doc.on.doc", tooltip: "Copy", enabled: true, action: #selector(copyTapped))
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

    private func buildSubToolbar() -> NSView {
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
            button.toolTip = "Stroke"
            button.target = self
            button.action = #selector(strokeTapped(_:))
            button.tag = option.rawValue
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22),
            ])
            button.image = strokeDotImage(diameter: option.previewDiameter, selected: false)
            return button
        }
        for b in strokeButtons { stack.addArrangedSubview(b) }

        fillButton = NSButton(frame: .zero)
        fillButton.bezelStyle = .inline
        fillButton.isBordered = false
        fillButton.setButtonType(.momentaryChange)
        fillButton.imagePosition = .imageOnly
        fillButton.toolTip = "Fill"
        fillButton.target = self
        fillButton.action = #selector(fillTapped)
        fillButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fillButton.widthAnchor.constraint(equalToConstant: 22),
            fillButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        fillButton.image = fillSwatchImage(selected: false)
        stack.addArrangedSubview(fillButton)

        let afterFillDivider = miniDivider()
        stack.addArrangedSubview(afterFillDivider)

        // Switch group 2: rectangle ↔ ellipse / circle.
        rectKindButton = iconButton(
            systemName: "rectangle",
            tooltip: "Rectangle",
            enabled: true,
            action: #selector(rectKindTapped)
        )
        ovalKindButton = iconButton(
            systemName: "oval",
            tooltip: "Ellipse / Circle",
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
            tooltip: "Start style",
            action: #selector(arrowStartCapTapped(_:))
        )
        stack.addArrangedSubview(arrowStartCapButton)

        // Body / border line style dropdown (Snipaste middle picker + shape/pen).
        lineStyleButton = NSButton(frame: .zero)
        lineStyleButton.bezelStyle = .inline
        lineStyleButton.isBordered = false
        lineStyleButton.setButtonType(.momentaryChange)
        lineStyleButton.imagePosition = .imageOnly
        lineStyleButton.toolTip = "Line style"
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
        stack.addArrangedSubview(lineStyleButton)

        // Arrow end-cap dropdown (Snipaste right picker).
        arrowEndCapButton = makeCapDropdownButton(
            tooltip: "End style",
            action: #selector(arrowEndCapTapped(_:))
        )
        stack.addArrangedSubview(arrowEndCapButton)

        // Caps on/off Switch: stacked “current” / “plain” previews (Snipaste).
        let switchBtn = ArrowCapsSwitchButton(frame: .zero)
        switchBtn.bezelStyle = .inline
        switchBtn.isBordered = false
        switchBtn.setButtonType(.momentaryChange)
        switchBtn.imagePosition = .imageOnly
        switchBtn.toolTip = "Toggle arrowheads"
        switchBtn.target = self
        switchBtn.action = #selector(arrowDoubleTapped)
        switchBtn.translatesAutoresizingMaskIntoConstraints = false
        switchBtn.wantsLayer = true
        NSLayoutConstraint.activate([
            switchBtn.widthAnchor.constraint(equalToConstant: 24),
            switchBtn.heightAnchor.constraint(equalToConstant: 24),
        ])
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

    private func buildTextSubToolbar() -> NSView {
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
        textSizeButton.toolTip = "Font size"
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

    private func buildMosaicSubToolbar() -> NSView {
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
            button.toolTip = "Brush \(Int(width))"
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
            return button
        }
        for button in mosaicBrushButtons {
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(miniDivider())

        mosaicRectButton = iconButton(
            image: mosaicBrushKindIcon(kind: .rectangle),
            tooltip: "Rectangle region",
            enabled: true,
            action: #selector(mosaicRectTapped)
        )
        mosaicOvalButton = iconButton(
            image: mosaicBrushKindIcon(kind: .ellipse),
            tooltip: "Oval region",
            enabled: true,
            action: #selector(mosaicOvalTapped)
        )
        stack.addArrangedSubview(mosaicRectButton)
        stack.addArrangedSubview(mosaicOvalButton)
        stack.addArrangedSubview(miniDivider())

        mosaicIntensityPreview = MosaicIntensityPreviewView(frame: .zero)
        mosaicIntensityPreview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mosaicIntensityPreview.widthAnchor.constraint(equalToConstant: 24),
            mosaicIntensityPreview.heightAnchor.constraint(equalToConstant: 24),
        ])
        stack.addArrangedSubview(mosaicIntensityPreview)

        mosaicIntensitySlider = NSSlider(value: Double(mosaicStyle.intensity),
                                         minValue: Double(MosaicStyle.intensityRange.lowerBound),
                                         maxValue: Double(MosaicStyle.intensityRange.upperBound),
                                         target: self,
                                         action: #selector(mosaicIntensityChanged(_:)))
        mosaicIntensitySlider.isContinuous = true
        mosaicIntensitySlider.controlSize = .small
        mosaicIntensitySlider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mosaicIntensitySlider.widthAnchor.constraint(equalToConstant: 90),
            mosaicIntensitySlider.heightAnchor.constraint(equalToConstant: 18),
        ])
        stack.addArrangedSubview(mosaicIntensitySlider)

        mosaicIntensityLabel = NSTextField(labelWithString: "\(Int(mosaicStyle.intensity.rounded()))")
        mosaicIntensityLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        mosaicIntensityLabel.textColor = NSColor(calibratedWhite: 0.28, alpha: 1)
        mosaicIntensityLabel.alignment = .right
        mosaicIntensityLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mosaicIntensityLabel.widthAnchor.constraint(equalToConstant: 22),
        ])
        stack.addArrangedSubview(mosaicIntensityLabel)

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func textStyleToggleButton(title: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.title = title
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
        return button
    }

    private func makeChromeCard() -> NSView {
        let card = NSView(frame: .zero)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 6
        card.layer?.masksToBounds = false
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.18
        card.layer?.shadowRadius = 6
        card.layer?.shadowOffset = CGSize(width: 0, height: -1)
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func embed(_ child: NSView, in card: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            child.topAnchor.constraint(equalTo: card.topAnchor),
            child.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
    }

    private func layoutPanel(content: NSView) {
        content.layoutSubtreeIfNeeded()
        let fitting = rootStack.fittingSize
        let size = CGSize(width: max(fitting.width, 280), height: max(fitting.height, 28))
        content.frame = CGRect(origin: .zero, size: size)
        panel.setContentSize(size)
    }

    private func refreshSelectionChrome() {
        tintSelected(shapeButton, selected: tool == .rectangle)
        tintSelected(arrowButton, selected: tool == .arrow)
        tintSelected(pencilButton, selected: tool == .pencil)
        tintSelected(mosaicButton, selected: tool == .mosaic)
        tintSelected(textButton, selected: tool == .text)
        colorPreview.layer?.backgroundColor = style.strokeColor.cgColor
        textColorPreview.layer?.backgroundColor = textStyle.color.cgColor

        let isText = (tool == .text)
        let isMosaic = (tool == .mosaic)
        strokeOptionsRow.isHidden = isText || isMosaic
        textOptionsRow.isHidden = !isText
        mosaicOptionsRow.isHidden = !isMosaic

        let isArrow = (tool == .arrow)
        let shapeExtrasVisible = (tool == .rectangle)
        for view in shapeOnlyViews {
            view.isHidden = !shapeExtrasVisible
        }
        afterKindDivider.isHidden = isArrow || isText || isMosaic
        for view in arrowOnlyViews {
            view.isHidden = !isArrow
        }

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
        lineStyleButton.toolTip = isArrow ? "Line style" : "Border style"
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
    }

    private func refreshMosaicChrome() {
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
        mosaicIntensitySlider.doubleValue = Double(mosaicStyle.intensity)
        mosaicIntensityLabel.stringValue = "\(Int(mosaicStyle.intensity.rounded()))"
        mosaicIntensityPreview.intensity = mosaicStyle.intensity
        mosaicIntensityPreview.needsDisplay = true
    }

    private func tintSelected(_ button: NSButton, selected: Bool) {
        button.contentTintColor = selected
            ? NSColor.systemBlue
            : NSColor(calibratedWhite: 0.22, alpha: 1)
        if selected {
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.12).cgColor
            button.layer?.cornerRadius = 4
        } else {
            button.layer?.backgroundColor = nil
        }
    }

    private func strokeDotImage(diameter: CGFloat, selected: Bool) -> NSImage {
        let size = CGSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let color = selected ? NSColor.systemBlue : NSColor(calibratedWhite: 0.25, alpha: 1)
            color.setFill()
            let r = CGRect(
                x: (rect.width - diameter) / 2,
                y: (rect.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            NSBezierPath(ovalIn: r).fill()
            return true
        }
    }

    private func fillSwatchImage(selected: Bool) -> NSImage {
        let size = CGSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let color = selected ? NSColor.systemBlue : NSColor(calibratedWhite: 0.25, alpha: 1)
            color.setFill()
            let r = CGRect(x: 3, y: 3, width: 12, height: 12)
            NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
    }

    /// Compact pill preview: line pattern + chevron (Snipaste-like).
    private func lineStylePreviewImage(_ lineStyle: StrokeLineStyle) -> NSImage {
        let size = CGSize(width: 52, height: 18)
        let previewStroke: CGFloat = 2
        return NSImage(size: size, flipped: false) { rect in
            let ink = NSColor(calibratedWhite: 0.28, alpha: 1)
            ink.setStroke()

            let y = rect.midY
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 6, y: y))
            line.line(to: NSPoint(x: 34, y: y))
            line.lineWidth = previewStroke
            line.lineCapStyle = .butt
            let dash = lineStyle.dashPattern(strokeWidth: previewStroke)
            if !dash.isEmpty {
                line.setLineDash(dash, count: dash.count, phase: 0)
            }
            line.stroke()

            // Up / down chevrons on the trailing edge.
            let chevronX: CGFloat = 42
            let chevron = NSBezierPath()
            chevron.move(to: NSPoint(x: chevronX, y: y + 4.5))
            chevron.line(to: NSPoint(x: chevronX + 3.5, y: y + 1.5))
            chevron.line(to: NSPoint(x: chevronX + 7, y: y + 4.5))
            chevron.move(to: NSPoint(x: chevronX, y: y - 4.5))
            chevron.line(to: NSPoint(x: chevronX + 3.5, y: y - 1.5))
            chevron.line(to: NSPoint(x: chevronX + 7, y: y - 4.5))
            chevron.lineWidth = 1.2
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            ink.setStroke()
            chevron.stroke()
            return true
        }
    }

    private func iconButton(
        systemName: String,
        tooltip: String,
        enabled: Bool,
        action: Selector?
    ) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        return iconButton(image: image, tooltip: tooltip, enabled: enabled, action: action)
    }

    private func iconButton(
        image: NSImage?,
        tooltip: String,
        enabled: Bool,
        action: Selector?
    ) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.isEnabled = enabled
        button.target = action == nil ? nil : self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        button.image = image
        button.contentTintColor = enabled
            ? NSColor(calibratedWhite: 0.22, alpha: 1)
            : NSColor(calibratedWhite: 0.55, alpha: 1)
        return button
    }

    /// Lucide [`type`](https://lucide.dev/icons/type) (ISC) — capital T with top/bottom bars.
    private func textToolIcon() -> NSImage {
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

    /// Snipaste-like 2×2 pixel block (checkerboard mosaic).
    private func mosaicToolIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset: CGFloat = 2.5
            let gap: CGFloat = 1.25
            let cell = (rect.width - inset * 2 - gap) / 2
            let origin = CGPoint(x: inset, y: inset)
            // Top-left + bottom-right filled (classic pixel-block read).
            let cells = [
                CGRect(x: origin.x, y: origin.y + cell + gap, width: cell, height: cell),
                CGRect(x: origin.x + cell + gap, y: origin.y, width: cell, height: cell),
            ]
            NSColor.black.setFill()
            for cellRect in cells {
                NSBezierPath(roundedRect: cellRect, xRadius: 0.75, yRadius: 0.75).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func mosaicBrushKindIcon(kind: MosaicDrawMode) -> NSImage {
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

    private func divider() -> NSView {
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

    private func miniDivider() -> NSView {
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

    @objc private func shapeTapped() {
        selectTool(tool == .rectangle ? .none : .rectangle)
    }

    @objc private func arrowTapped() {
        selectTool(tool == .arrow ? .none : .arrow)
    }

    @objc private func pencilTapped() {
        selectTool(tool == .pencil ? .none : .pencil)
    }

    @objc private func mosaicTapped() {
        selectTool(tool == .mosaic ? .none : .mosaic)
    }

    @objc private func textTapped() {
        selectTool(tool == .text ? .none : .text)
    }

    private func selectTool(_ next: AnnotateTool) {
        tool = next
        if next == .pencil || next == .arrow {
            style.isFilled = false
        }
        subToolbarContainer.isHidden = (next == .none)
        refreshSelectionChrome()
        if let content = panel.contentView {
            layoutPanel(content: content)
        }
        onEvent(.selectTool(next))
    }

    @objc private func mosaicBrushTapped(_ sender: NSButton) {
        mosaicStyle.brushWidth = MosaicStyle.nearestBrushPreset(CGFloat(sender.tag))
        mosaicDrawMode = .freehand
        refreshMosaicChrome()
        onEvent(.mosaicDrawModeChanged(mosaicDrawMode))
        onEvent(.mosaicStyleChanged(mosaicStyle))
    }

    @objc private func mosaicRectTapped() {
        mosaicDrawMode = .rectangle
        refreshMosaicChrome()
        onEvent(.mosaicDrawModeChanged(mosaicDrawMode))
    }

    @objc private func mosaicOvalTapped() {
        mosaicDrawMode = .ellipse
        refreshMosaicChrome()
        onEvent(.mosaicDrawModeChanged(mosaicDrawMode))
    }

    @objc private func mosaicIntensityChanged(_ sender: NSSlider) {
        mosaicStyle.intensity = MosaicStyle.clampedIntensity(CGFloat(sender.doubleValue))
        mosaicIntensityLabel.stringValue = "\(Int(mosaicStyle.intensity.rounded()))"
        mosaicIntensityPreview.intensity = mosaicStyle.intensity
        mosaicIntensityPreview.needsDisplay = true
        onEvent(.mosaicStyleChanged(mosaicStyle))
    }

    @objc private func textBoldTapped() {
        textStyle.isBold.toggle()
        refreshSelectionChrome()
        onEvent(.textStyleChanged(textStyle))
    }

    @objc private func textItalicTapped() {
        textStyle.isItalic.toggle()
        refreshSelectionChrome()
        onEvent(.textStyleChanged(textStyle))
    }

    @objc private func textBackgroundTapped() {
        textStyle.hasBackground.toggle()
        refreshSelectionChrome()
        onEvent(.textStyleChanged(textStyle))
    }

    @objc private func textSizeTapped(_ sender: NSButton) {
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

    @objc private func textSizeMenuPicked(_ sender: NSMenuItem) {
        textStyle.fontSize = CGFloat(sender.tag)
        refreshSelectionChrome()
        onEvent(.textStyleChanged(textStyle))
    }

    @objc private func strokeTapped(_ sender: NSButton) {
        let option = StrokeWidthOption(rawValue: sender.tag) ?? .medium
        style.strokeWidth = option.points
        style.isFilled = false
        refreshSelectionChrome()
        onEvent(.styleChanged(style))
    }

    @objc private func fillTapped() {
        guard tool == .rectangle else { return }
        style.isFilled = true
        refreshSelectionChrome()
        onEvent(.styleChanged(style))
    }

    @objc private func rectKindTapped() {
        kind = .rectangle
        refreshSelectionChrome()
        onEvent(.kindChanged(kind))
    }

    @objc private func ovalKindTapped() {
        kind = .ellipse
        refreshSelectionChrome()
        onEvent(.kindChanged(kind))
    }

    @objc private func lineStyleTapped(_ sender: NSButton) {
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

    @objc private func lineStyleMenuPicked(_ sender: NSMenuItem) {
        guard let option = StrokeLineStyle(rawValue: sender.tag) else { return }
        style.lineStyle = option
        style.isFilled = false
        refreshSelectionChrome()
        onEvent(.styleChanged(style))
    }

    private func makeCapDropdownButton(tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        // Cap chips are narrower than the body line-style pill; leave room for padding.
        button.layer?.cornerRadius = 5
        button.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor(calibratedWhite: 0.78, alpha: 1).cgColor
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
        return button
    }

    private enum CapPreviewDirection {
        case left
        case right
    }

    /// Chip icon: short stub + small tip, inset so the glyph isn’t edge-to-edge.
    private func arrowCapPreviewImage(cap: ArrowCapStyle, pointing: CapPreviewDirection) -> NSImage {
        let size = CGSize(width: 26, height: 14)
        return NSImage(size: size, flipped: false) { rect in
            AnnotationDrawing.drawCapPreview(
                cap,
                in: rect.insetBy(dx: 3, dy: 2),
                pointingLeft: pointing == .left,
                color: NSColor(calibratedWhite: 0.28, alpha: 1),
                strokeWidth: 1.5
            )
            return true
        }
    }

    @objc private func arrowStartCapTapped(_ sender: NSButton) {
        presentCapMenu(for: .start, from: sender)
    }

    @objc private func arrowEndCapTapped(_ sender: NSButton) {
        presentCapMenu(for: .end, from: sender)
    }

    private func presentCapMenu(for endpoint: ArrowEndpoint, from sender: NSButton) {
        let menu = NSMenu()
        let current = endpoint == .start ? arrowCaps.start : arrowCaps.end
        for option in ArrowCapStyle.menuCases {
            let item = NSMenuItem(
                title: "",
                action: #selector(arrowCapMenuPicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = option.rawValue
            item.representedObject = endpoint == .start ? "start" : "end"
            item.state = (option == current) ? .on : .off
            item.image = arrowCapMenuImage(
                option,
                pointing: endpoint == .start ? .left : .right
            )
            menu.addItem(item)
        }
        let point = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func arrowCapMenuPicked(_ sender: NSMenuItem) {
        guard let option = ArrowCapStyle(rawValue: sender.tag),
              let which = sender.representedObject as? String
        else { return }
        if which == "start" {
            arrowCaps.start = option
        } else {
            arrowCaps.end = option
        }
        refreshSelectionChrome()
        onEvent(.arrowCapsChanged(arrowCaps))
    }

    private func arrowCapMenuImage(_ cap: ArrowCapStyle, pointing: CapPreviewDirection) -> NSImage {
        // Same footprint for every row; inset so glyphs don’t touch the menu edges.
        let size = CGSize(width: 28, height: 14)
        return NSImage(size: size, flipped: false) { rect in
            AnnotationDrawing.drawCapPreview(
                cap,
                in: rect.insetBy(dx: 3, dy: 2),
                pointingLeft: pointing == .left,
                color: NSColor(calibratedWhite: 0.25, alpha: 1),
                strokeWidth: 1.5
            )
            return true
        }
    }

    @objc private func arrowDoubleTapped() {
        // Toggle: strip arrowheads ↔ restore last arrowed caps (not force double-ended).
        if arrowCaps.hasCaps {
            lastArrowedCaps = arrowCaps
            arrowCaps = .plainLine()
        } else {
            arrowCaps = lastArrowedCaps.hasCaps ? lastArrowedCaps : .default
        }
        refreshSelectionChrome()
        onEvent(.arrowCapsChanged(arrowCaps))
    }

    /// Snipaste-like stacked Switch: top = armed caps preview, bottom = plain line.
    /// Active row is dark; inactive row is light gray.
    private func arrowCapsSwitchImage() -> NSImage {
        let size = CGSize(width: 20, height: 20)
        let arrowsActive = arrowCaps.hasCaps
        let armed = arrowCaps.hasCaps ? arrowCaps : lastArrowedCaps
        let active = NSColor(calibratedWhite: 0.18, alpha: 1)
        let inactive = NSColor(calibratedWhite: 0.62, alpha: 1)
        return NSImage(size: size, flipped: false) { rect in
            // Pack the two shafts tightly around the vertical center (Snipaste-like).
            let rowH: CGFloat = 5
            let rowGap: CGFloat = 1.5
            let stackH = rowH * 2 + rowGap
            let bottomOriginY = (rect.height - stackH) / 2
            let bottom = CGRect(x: 2, y: bottomOriginY, width: rect.width - 4, height: rowH)
            let top = CGRect(x: 2, y: bottomOriginY + rowH + rowGap, width: rect.width - 4, height: rowH)
            AnnotationDrawing.drawCapsPairPreview(
                armed,
                in: top,
                color: arrowsActive ? active : inactive,
                strokeWidth: 1.15
            )
            AnnotationDrawing.drawCapsPairPreview(
                .plainLine(),
                in: bottom,
                color: arrowsActive ? inactive : active,
                strokeWidth: 1.15
            )
            return true
        }
    }

    private func lineStyleMenuImage(_ lineStyle: StrokeLineStyle) -> NSImage {
        let size = CGSize(width: 56, height: 14)
        let previewStroke: CGFloat = 2
        return NSImage(size: size, flipped: false) { rect in
            NSColor(calibratedWhite: 0.25, alpha: 1).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 2, y: rect.midY))
            line.line(to: NSPoint(x: rect.width - 2, y: rect.midY))
            line.lineWidth = previewStroke
            line.lineCapStyle = .butt
            let dash = lineStyle.dashPattern(strokeWidth: previewStroke)
            if !dash.isEmpty {
                line.setLineDash(dash, count: dash.count, phase: 0)
            }
            line.stroke()
            return true
        }
    }

    @objc private func pinTapped() { onEvent(.confirm(.pin)) }
    @objc private func copyTapped() { onEvent(.confirm(.copy)) }
    @objc private func saveTapped() { onEvent(.confirm(.save)) }
    @objc private func cancelTapped() { onEvent(.confirm(.cancel)) }
    @objc private func undoTapped() { onEvent(.undo) }
    @objc private func redoTapped() { onEvent(.redo) }

    func setAnnotateTool(_ tool: AnnotateTool) {
        self.tool = tool
        if tool == .pencil || tool == .arrow {
            style.isFilled = false
        }
        subToolbarContainer.isHidden = (tool == .none)
        refreshSelectionChrome()
        if let content = panel.contentView {
            layoutPanel(content: content)
        }
    }

    func syncStyle(_ style: AnnotationStyle, kind: ShapeKind, arrowCaps: ArrowCaps = .default) {
        self.style = style
        self.kind = kind
        self.arrowCaps = arrowCaps
        if arrowCaps.hasCaps {
            lastArrowedCaps = arrowCaps
        }
        refreshSelectionChrome()
    }

    func syncTextStyle(_ style: TextStyle) {
        self.textStyle = style
        refreshSelectionChrome()
    }

    func syncMosaicStyle(_ style: MosaicStyle) {
        var next = style
        next.clamp()
        self.mosaicStyle = next
        refreshSelectionChrome()
    }

    func syncMosaicDrawMode(_ mode: MosaicDrawMode) {
        mosaicDrawMode = mode
        refreshSelectionChrome()
    }

    func setHistoryAvailability(canUndo: Bool, canRedo: Bool) {
        setHistoryButton(undoButton, enabled: canUndo)
        setHistoryButton(redoButton, enabled: canRedo)
    }

    private func setHistoryButton(_ button: NSButton, enabled: Bool) {
        button.isEnabled = enabled
        button.contentTintColor = enabled
            ? NSColor(calibratedWhite: 0.22, alpha: 1)
            : NSColor(calibratedWhite: 0.55, alpha: 1)
    }

    func orderFront() {
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    func containsGlobalPoint(_ point: CGPoint) -> Bool {
        panel.frame.contains(point)
    }

    func reposition(around selection: CGRect) {
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

/// Caps Switch: press nudges the stacked glyphs down; release restores (Snipaste press feel).
private final class ArrowCapsSwitchButton: NSButton {
    private let pressTranslationY: CGFloat = -1.5

    override func mouseDown(with event: NSEvent) {
        wantsLayer = true
        applyPressOffset(pressTranslationY, animated: true)
        // Blocks until mouse-up, then sends the action.
        super.mouseDown(with: event)
        applyPressOffset(0, animated: true)
    }

    private func applyPressOffset(_ y: CGFloat, animated: Bool) {
        wantsLayer = true
        let apply = {
            self.layer?.transform = CATransform3DMakeTranslation(0, y, 0)
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.07
                ctx.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }
    }
}

final class RefineToolbarView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
}

// MARK: - Palette swatch (Snipaste-like hover grow)

/// Fixed layout cell; chip starts small and scales up on hover.
/// Fill is drawn flush to the 1pt border (no CALayer inset gap).
final class PaletteSwatchControl: NSView {
    /// Snipaste @2x: 22 device-px → 11pt chip; 4px gap → 2pt (via stack spacing).
    static let cellSize: CGFloat = 11
    private static let restSize: CGFloat = 11
    private static let hoverSize: CGFloat = 13.5

    private let swatch: PaletteColor
    private let onPick: (PaletteColor) -> Void
    private let chip = PaletteSwatchChip()
    private var trackingArea: NSTrackingArea?

    init(swatch: PaletteColor, onPick: @escaping (PaletteColor) -> Void) {
        self.swatch = swatch
        self.onPick = onPick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.cellSize),
            heightAnchor.constraint(equalToConstant: Self.cellSize),
        ])

        chip.swatchColor = swatch.color
        addSubview(chip)
        layoutChip(size: Self.restSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        animateChip(size: Self.hoverSize)
    }

    override func mouseExited(with event: NSEvent) {
        animateChip(size: Self.restSize)
    }

    override func mouseDown(with event: NSEvent) {
        onPick(swatch)
    }

    private func animateChip(size: CGFloat) {
        let origin = (Self.cellSize - size) / 2
        let target = CGRect(x: origin, y: origin, width: size, height: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.09
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            chip.animator().frame = target
        }
        chip.needsDisplay = true
    }

    private func layoutChip(size: CGFloat) {
        let origin = (Self.cellSize - size) / 2
        chip.frame = CGRect(x: origin, y: origin, width: size, height: size)
        chip.needsDisplay = true
    }
}

final class PaletteSwatchChip: NSView {
    var swatchColor: NSColor = .black

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = max(1.75, bounds.width * 0.22)
        let fillPath = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        swatchColor.setFill()
        fillPath.fill()

        // Stroke on the same rect edge — no gap between fill and border.
        let strokePath = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: max(radius - 0.5, 0.5),
            yRadius: max(radius - 0.5, 0.5)
        )
        strokePath.lineWidth = 1
        NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
        strokePath.stroke()
    }
}

/// Intensity chip: soft circle (no rim); interior softens with blur radius.
final class MosaicIntensityPreviewView: NSView {
    var intensity: CGFloat = 10

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private static let sampleImage: CIImage = {
        let px = 64
        let size = CGSize(width: px, height: px)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: px,
            pixelsHigh: px,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 10, y: 10, width: 44, height: 44)).fill()
        NSColor(calibratedWhite: 0.75, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 22, y: 22, width: 20, height: 20)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let ns = NSImage(size: size)
        ns.addRepresentation(rep)
        return CIImage(data: ns.tiffRepresentation!) ?? CIImage.empty()
    }()

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let intensity = MosaicStyle.clampedIntensity(intensity)
        let radius = MosaicStyle.blurRadiusPoints(forIntensity: intensity)

        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(Self.sampleImage, forKey: kCIInputImageKey)
        filter?.setValue(radius * 1.2, forKey: kCIInputRadiusKey)

        let shapePath = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))

        NSGraphicsContext.current?.saveGraphicsState()
        shapePath.addClip()
        if let output = filter?.outputImage?.cropped(to: Self.sampleImage.extent),
           let cg = Self.ciContext.createCGImage(output, from: Self.sampleImage.extent) {
            NSImage(cgImage: cg, size: bounds.size)
                .draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        } else {
            NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
            shapePath.fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
