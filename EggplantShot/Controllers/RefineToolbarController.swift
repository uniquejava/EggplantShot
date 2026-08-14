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
        case markerStyleChanged(MarkerStyle)
        case markerDrawModeChanged(MosaicDrawMode)
        case eraserStyleChanged(EraserStyle)
        case eraserDrawModeChanged(MosaicDrawMode)
        case stepStyleChanged(StepStyle)
        case magnifierChanged(kind: ShapeKind, style: MagnifierStyle)
        case kindChanged(ShapeKind)
        case arrowCapsChanged(ArrowCaps)
        case ocr
        case undo
        case redo
    }

    let panel: NSPanel
    let onEvent: (Event) -> Void
    /// Custom tooltips — native `toolTip` fails on this non-activating panel.
    let tooltip = RefineToolbarTooltip()
    var style: AnnotationStyle
    var textStyle: TextStyle
    var mosaicStyle: MosaicStyle
    var mosaicDrawMode: MosaicDrawMode
    var markerStyle: MarkerStyle
    var markerDrawMode: MosaicDrawMode
    var eraserStyle: EraserStyle
    var eraserDrawMode: MosaicDrawMode
    var stepStyle: StepStyle
    var magnifierStyle: MagnifierStyle
    var magnifierKind: ShapeKind
    var tool: AnnotateTool
    var kind: ShapeKind
    var arrowCaps: ArrowCaps

    let rootStack = NSStackView()
    var shapeButton: NSButton!
    var arrowButton: NSButton!
    var pencilButton: NSButton!
    var markerButton: NSButton!
    var mosaicButton: NSButton!
    var textButton: NSButton!
    var stepButton: NSButton!
    var magnifierButton: NSButton!
    var eraserButton: NSButton!
    var undoButton: NSButton!
    var redoButton: NSButton!
    var subToolbarContainer: NSView!
    /// Shape/pencil/arrow options row (stroke / fill / kind / line / palette).
    var strokeOptionsRow: NSView!
    /// Text options row (B / I / bg / size / palette).
    var textOptionsRow: NSView!
    /// Mosaic options row (brush / kind / intensity).
    var mosaicOptionsRow: NSView!
    /// Marker options row (brush / kind / color card).
    var markerOptionsRow: NSView!
    /// Eraser options row (brush / rect / oval — same first 5 as mosaic).
    var eraserOptionsRow: NSView!
    /// Step options row (chrome kind / size / palette).
    var stepOptionsRow: NSView!
    /// Magnifier options row (stroke / rect-oval / includeAnnotations / scale / palette).
    var magnifierOptionsRow: NSView!
    /// Shape-only chrome (fill + rect/oval). Hidden for pencil / arrow.
    var shapeOnlyViews: [NSView] = []
    /// Divider after shape kind group; visible for shape/pencil, hidden for arrow.
    var afterKindDivider: NSView!
    /// Arrow-only chrome (start / end caps + double Switch). Hidden for shape / pencil.
    var arrowOnlyViews: [NSView] = []
    var strokeButtons: [NSButton] = []
    var fillButton: NSButton!
    var rectKindButton: NSButton!
    var ovalKindButton: NSButton!
    var lineStyleButton: NSButton!
    var arrowStartCapButton: NSButton!
    var arrowEndCapButton: NSButton!
    var arrowDoubleButton: NSButton!
    /// Caps to restore when Switch toggles arrows back on (Snipaste memory).
    var lastArrowedCaps: ArrowCaps = .default
    var colorPreview: NSView!
    var textBoldButton: NSButton!
    var textItalicButton: NSButton!
    var textBackgroundButton: NSButton!
    var textSizeButton: NSButton!
    var textColorPreview: NSView!
    var mosaicBrushButtons: [NSButton] = []
    var mosaicRectButton: NSButton!
    var mosaicOvalButton: NSButton!
    var mosaicIntensityPreview: MosaicIntensityPreviewView!
    var mosaicIntensitySlider: MosaicIntensitySlider!
    var mosaicIntensityLabel: NSTextField!
    var markerBrushButtons: [NSButton] = []
    var markerRectButton: NSButton!
    var markerOvalButton: NSButton!
    var markerColorPreview: NSView!
    var eraserBrushButtons: [NSButton] = []
    var eraserRectButton: NSButton!
    var eraserOvalButton: NSButton!
    var stepKindButtons: [NSButton] = []
    var stepSizeButton: NSButton!
    var stepColorPreview: NSView!
    var magnifierRectButton: NSButton!
    var magnifierOvalButton: NSButton!
    var magnifierStrokeButtons: [NSButton] = []
    var magnifierIncludeButton: NSButton!
    var magnifierScalePreview: MagnifierScalePreviewView!
    var magnifierScaleSlider: MosaicIntensitySlider!
    var magnifierScaleLabel: NSTextField!
    var magnifierColorPreview: NSView!

    init(
        primaryAction: SelectionOverlayController.ConfirmAction,
        initialTool: AnnotateTool,
        initialStyle: AnnotationStyle,
        initialKind: ShapeKind,
        initialArrowCaps: ArrowCaps,
        initialTextStyle: TextStyle,
        initialMosaicStyle: MosaicStyle = .default,
        initialMosaicDrawMode: MosaicDrawMode = .rectangle,
        initialMarkerStyle: MarkerStyle = .default,
        initialMarkerDrawMode: MosaicDrawMode = .rectangle,
        initialEraserStyle: EraserStyle = .default,
        initialEraserDrawMode: MosaicDrawMode = .rectangle,
        initialStepStyle: StepStyle = .default,
        initialMagnifierKind: ShapeKind = .rectangle,
        initialMagnifierStyle: MagnifierStyle = .default,
        onEvent: @escaping (Event) -> Void
    ) {
        self.onEvent = onEvent
        self.style = initialStyle
        self.textStyle = initialTextStyle
        self.mosaicStyle = initialMosaicStyle
        self.mosaicDrawMode = initialMosaicDrawMode
        self.markerStyle = initialMarkerStyle
        self.markerDrawMode = initialMarkerDrawMode
        self.eraserStyle = initialEraserStyle
        self.eraserDrawMode = initialEraserDrawMode
        self.stepStyle = initialStepStyle
        self.magnifierKind = initialMagnifierKind
        self.magnifierStyle = initialMagnifierStyle
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
        markerOptionsRow = buildMarkerSubToolbar()
        eraserOptionsRow = buildEraserSubToolbar()
        stepOptionsRow = buildStepSubToolbar()
        magnifierOptionsRow = buildMagnifierSubToolbar()
        optionsStack.addArrangedSubview(strokeOptionsRow)
        optionsStack.addArrangedSubview(textOptionsRow)
        optionsStack.addArrangedSubview(markerOptionsRow)
        optionsStack.addArrangedSubview(mosaicOptionsRow)
        optionsStack.addArrangedSubview(eraserOptionsRow)
        optionsStack.addArrangedSubview(stepOptionsRow)
        optionsStack.addArrangedSubview(magnifierOptionsRow)
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
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = content
    }

    func buildMainRow(primaryAction: SelectionOverlayController.ConfirmAction) -> NSView {
        shapeButton = iconButton(
            systemName: "rectangle",
            tooltip: "Shape",
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
            image: pencilToolIcon(),
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
        markerButton = iconButton(
            systemName: "paintbrush.pointed",
            tooltip: "Marker",
            enabled: true,
            action: #selector(markerTapped)
        )
        textButton = iconButton(
            image: textToolIcon(),
            tooltip: "Text",
            enabled: true,
            action: #selector(textTapped)
        )
        stepButton = iconButton(
            image: stepToolIcon(),
            tooltip: "Step",
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
            tooltip: "Eraser",
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
            iconButton(
                systemName: "doc.text.viewfinder",
                tooltip: "OCR",
                enabled: true,
                action: #selector(ocrTapped)
            ),
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
        tooltip.register(fillButton, text: "Fill")
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
            tooltip: "Ellipse",
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
            tooltip: "Start cap",
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
        tooltip.register(lineStyleButton, text: "Line style")
        stack.addArrangedSubview(lineStyleButton)

        // Arrow end-cap dropdown (Snipaste right picker).
        arrowEndCapButton = makeCapDropdownButton(
            tooltip: "End cap",
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
        tooltip.register(switchBtn, text: "Switch arrowheads")
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

    func selectTool(_ next: AnnotateTool) {
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

    @objc func pinTapped() { onEvent(.confirm(.pin)) }
    @objc func copyTapped() { onEvent(.confirm(.copy)) }
    @objc func saveTapped() { onEvent(.confirm(.save)) }
    @objc func cancelTapped() { onEvent(.confirm(.cancel)) }
    @objc func ocrTapped() { onEvent(.ocr) }
    @objc func undoTapped() { onEvent(.undo) }
    @objc func redoTapped() { onEvent(.redo) }

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

    func syncMarkerStyle(_ style: MarkerStyle) {
        var next = style
        next.clamp()
        self.markerStyle = next
        refreshSelectionChrome()
    }

    func syncMarkerDrawMode(_ mode: MosaicDrawMode) {
        markerDrawMode = mode
        refreshSelectionChrome()
    }

    func syncEraserStyle(_ style: EraserStyle) {
        var next = style
        next.clamp()
        self.eraserStyle = next
        refreshSelectionChrome()
    }

    func syncEraserDrawMode(_ mode: MosaicDrawMode) {
        eraserDrawMode = mode
        refreshSelectionChrome()
    }

    func syncStepStyle(_ style: StepStyle) {
        var next = style
        next.clamp()
        self.stepStyle = next
        refreshSelectionChrome()
    }

    func syncMagnifier(kind: ShapeKind, style: MagnifierStyle) {
        var next = style
        next.clamp()
        magnifierKind = kind
        magnifierStyle = next
        refreshSelectionChrome()
    }

    func setHistoryAvailability(canUndo: Bool, canRedo: Bool) {
        setHistoryButton(undoButton, enabled: canUndo)
        setHistoryButton(redoButton, enabled: canRedo)
    }

    func setHistoryButton(_ button: NSButton, enabled: Bool) {
        button.isEnabled = enabled
        button.contentTintColor = enabled
            ? NSColor(calibratedWhite: 0.22, alpha: 1)
            : NSColor(calibratedWhite: 0.55, alpha: 1)
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

/// Caps Switch: press nudges the stacked glyphs down; release restores (Snipaste press feel).
private final class ArrowCapsSwitchButton: NSButton {
    let pressTranslationY: CGFloat = -1.5

    override func mouseDown(with event: NSEvent) {
        wantsLayer = true
        applyPressOffset(pressTranslationY, animated: true)
        // Blocks until mouse-up, then sends the action.
        super.mouseDown(with: event)
        applyPressOffset(0, animated: true)
    }

    func applyPressOffset(_ y: CGFloat, animated: Bool) {
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

