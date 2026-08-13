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

    private let panel: NSPanel
    private let onEvent: (Event) -> Void
    private var style: AnnotationStyle
    private var textStyle: TextStyle
    private var mosaicStyle: MosaicStyle
    private var mosaicDrawMode: MosaicDrawMode
    private var markerStyle: MarkerStyle
    private var markerDrawMode: MosaicDrawMode
    private var eraserStyle: EraserStyle
    private var eraserDrawMode: MosaicDrawMode
    private var stepStyle: StepStyle
    private var magnifierStyle: MagnifierStyle
    private var magnifierKind: ShapeKind
    private var tool: AnnotateTool
    private var kind: ShapeKind
    private var arrowCaps: ArrowCaps

    private let rootStack = NSStackView()
    private var shapeButton: NSButton!
    private var arrowButton: NSButton!
    private var pencilButton: NSButton!
    private var markerButton: NSButton!
    private var mosaicButton: NSButton!
    private var textButton: NSButton!
    private var stepButton: NSButton!
    private var magnifierButton: NSButton!
    private var eraserButton: NSButton!
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var subToolbarContainer: NSView!
    /// Shape/pencil/arrow options row (stroke / fill / kind / line / palette).
    private var strokeOptionsRow: NSView!
    /// Text options row (B / I / bg / size / palette).
    private var textOptionsRow: NSView!
    /// Mosaic options row (brush / kind / intensity).
    private var mosaicOptionsRow: NSView!
    /// Marker options row (brush / kind / color card).
    private var markerOptionsRow: NSView!
    /// Eraser options row (brush / rect / oval — same first 5 as mosaic).
    private var eraserOptionsRow: NSView!
    /// Step options row (chrome kind / size / palette).
    private var stepOptionsRow: NSView!
    /// Magnifier options row (stroke / rect-oval / includeAnnotations / scale / palette).
    private var magnifierOptionsRow: NSView!
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
    private var mosaicIntensitySlider: MosaicIntensitySlider!
    private var mosaicIntensityLabel: NSTextField!
    private var markerBrushButtons: [NSButton] = []
    private var markerRectButton: NSButton!
    private var markerOvalButton: NSButton!
    private var markerColorPreview: NSView!
    private var eraserBrushButtons: [NSButton] = []
    private var eraserRectButton: NSButton!
    private var eraserOvalButton: NSButton!
    private var stepKindButtons: [NSButton] = []
    private var stepSizeButton: NSButton!
    private var stepColorPreview: NSView!
    private var magnifierRectButton: NSButton!
    private var magnifierOvalButton: NSButton!
    private var magnifierStrokeButtons: [NSButton] = []
    private var magnifierIncludeButton: NSButton!
    private var magnifierScalePreview: MagnifierScalePreviewView!
    private var magnifierScaleSlider: MosaicIntensitySlider!
    private var magnifierScaleLabel: NSTextField!
    private var magnifierColorPreview: NSView!

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
                tooltip: "Recognize Text",
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
        mosaicIntensityPreview.intensity = mosaicStyle.intensity
        let intensityControls = appendValueSlider(
            to: stack,
            preview: mosaicIntensityPreview,
            minValue: Double(MosaicStyle.intensityRange.lowerBound),
            maxValue: Double(MosaicStyle.intensityRange.upperBound),
            value: Double(mosaicStyle.intensity),
            labelText: "\(Int(mosaicStyle.intensity.rounded()))",
            labelWidth: 18,
            action: #selector(mosaicIntensityChanged(_:))
        )
        mosaicIntensitySlider = intensityControls.slider
        mosaicIntensityLabel = intensityControls.label

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// Marker = mosaic layout with color card instead of blur intensity.
    private func buildMarkerSubToolbar() -> NSView {
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
    private func buildEraserSubToolbar() -> NSView {
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
            button.toolTip = "Brush \(Int(width))"
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
            return button
        }
        for button in eraserBrushButtons {
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(miniDivider())

        eraserRectButton = iconButton(
            image: mosaicBrushKindIcon(kind: .rectangle),
            tooltip: "Rectangle region",
            enabled: true,
            action: #selector(eraserRectTapped)
        )
        eraserOvalButton = iconButton(
            image: mosaicBrushKindIcon(kind: .ellipse),
            tooltip: "Oval region",
            enabled: true,
            action: #selector(eraserOvalTapped)
        )
        stack.addArrangedSubview(eraserRectButton)
        stack.addArrangedSubview(eraserOvalButton)

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func buildStepSubToolbar() -> NSView {
        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        stepKindButtons = StepChromeKind.allCases.map { kind in
            let button = NSButton(frame: .zero)
            button.bezelStyle = .inline
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.imagePosition = .imageOnly
            button.toolTip = stepKindTooltip(kind)
            button.target = self
            button.action = #selector(stepKindTapped(_:))
            button.tag = kind.rawValue
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 24),
                button.heightAnchor.constraint(equalToConstant: 24),
            ])
            button.image = stepChromeIcon(kind: kind, selected: false)
            return button
        }
        for button in stepKindButtons {
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(miniDivider())

        stepSizeButton = NSButton(frame: .zero)
        stepSizeButton.bezelStyle = .inline
        stepSizeButton.isBordered = false
        stepSizeButton.setButtonType(.momentaryChange)
        stepSizeButton.toolTip = "Size"
        stepSizeButton.target = self
        stepSizeButton.action = #selector(stepSizeTapped(_:))
        stepSizeButton.translatesAutoresizingMaskIntoConstraints = false
        stepSizeButton.wantsLayer = true
        stepSizeButton.layer?.cornerRadius = 4
        stepSizeButton.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        stepSizeButton.layer?.borderWidth = 1
        stepSizeButton.layer?.borderColor = NSColor(calibratedWhite: 0.78, alpha: 1).cgColor
        stepSizeButton.font = NSFont.systemFont(ofSize: 11)
        NSLayoutConstraint.activate([
            stepSizeButton.widthAnchor.constraint(equalToConstant: 44),
            stepSizeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        stack.addArrangedSubview(stepSizeButton)
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
        stepColorPreview = preview
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
                    self.stepStyle.color = picked.color
                    self.refreshSelectionChrome()
                    self.onEvent(.stepStyleChanged(self.stepStyle))
                }
                row.addArrangedSubview(control)
            }
            swatchGrid.addArrangedSubview(row)
        }
        stack.addArrangedSubview(swatchGrid)

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func buildMagnifierSubToolbar() -> NSView {
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

    private func makeChromeCard() -> HoverChromeCard {
        HoverChromeCard()
    }

    private func embed(_ child: NSView, in card: HoverChromeCard) {
        card.installContent(child)
    }

    /// Shared mosaic / magnifier control: preview chip + slider + value (tight slider→label gap).
    private func appendValueSlider(
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
        refreshMarkerChrome()
        refreshEraserChrome()
        refreshStepChrome()
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

    private func refreshMarkerChrome() {
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

    private func refreshEraserChrome() {
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

    private func refreshStepChrome() {
        for button in stepKindButtons {
            let kind = StepChromeKind(rawValue: button.tag) ?? .filled
            let on = kind == stepStyle.kind
            button.image = stepChromeIcon(kind: kind, selected: on)
            tintSelected(button, selected: on)
        }
        stepSizeButton.title = "\(Int(stepStyle.size.rounded()))"
        stepColorPreview.layer?.backgroundColor = stepStyle.color.cgColor
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

    /// Snipaste-like pencil: twin shaft lines, pointed tip, semi-ellipse eraser (~mosaic size).
    private func pencilToolIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            // Axis tip (bottom-left) → eraser (top-right); a touch larger than mosaic.
            let tip = CGPoint(x: 2.6, y: 2.6)
            let end = CGPoint(x: 13.4, y: 13.4)
            let dx = end.x - tip.x
            let dy = end.y - tip.y
            let len = hypot(dx, dy)
            guard len > 1 else { return false }
            let ux = dx / len
            let uy = dy / len
            let px = -uy
            let py = ux

            let halfGap: CGFloat = 1.45
            let tipLen: CGFloat = 3.0
            let ferruleGap: CGFloat = 1.15 // air between shaft and eraser (metal-band read)
            let eraserLen: CGFloat = 2.35
            let lineW: CGFloat = 1.35

            func along(_ t: CGFloat) -> CGPoint {
                CGPoint(x: tip.x + ux * t, y: tip.y + uy * t)
            }
            func offset(_ p: CGPoint, by s: CGFloat) -> CGPoint {
                CGPoint(x: p.x + px * s, y: p.y + py * s)
            }

            let shaftA = along(tipLen)
            let shaftB = along(len - eraserLen - ferruleGap)
            let leftA = offset(shaftA, by: halfGap)
            let leftB = offset(shaftB, by: halfGap)
            let rightA = offset(shaftA, by: -halfGap)
            let rightB = offset(shaftB, by: -halfGap)

            NSColor.black.setStroke()

            let shaft = NSBezierPath()
            shaft.move(to: leftA)
            shaft.line(to: leftB)
            shaft.move(to: rightA)
            shaft.line(to: rightB)
            shaft.lineWidth = lineW
            shaft.lineCapStyle = .butt
            shaft.stroke()

            let tipPath = NSBezierPath()
            tipPath.move(to: tip)
            tipPath.line(to: leftA)
            tipPath.move(to: tip)
            tipPath.line(to: rightA)
            tipPath.lineWidth = lineW
            tipPath.lineCapStyle = .round
            tipPath.stroke()

            // Half-capsule eraser: flat face toward shaft, with a small ferrule gap.
            let flat = along(len - eraserLen)
            let eraserHalfW = halfGap + 0.2
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.saveGState()
            ctx.translateBy(x: flat.x, y: flat.y)
            ctx.rotate(by: atan2(uy, ux))
            // Capsule half: straight sides + semicircular dome on +X.
            let body = max(eraserLen - eraserHalfW, 0.35)
            let cap = NSBezierPath()
            cap.move(to: CGPoint(x: 0, y: -eraserHalfW))
            cap.line(to: CGPoint(x: body, y: -eraserHalfW))
            cap.appendArc(
                withCenter: CGPoint(x: body, y: 0),
                radius: eraserHalfW,
                startAngle: -90,
                endAngle: 90,
                clockwise: false
            )
            cap.line(to: CGPoint(x: 0, y: eraserHalfW))
            cap.close()
            NSColor.black.setFill()
            cap.fill()
            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Snipaste-like 2×2 pixel block: rounded outer frame, large cells tight to the border.
    private func mosaicToolIcon() -> NSImage {
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
    private func stepToolIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let oval = rect.insetBy(dx: 1.5, dy: 1.5)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: oval).fill()
            // Cut out the digit so tintSelected keeps a white-looking “1”.
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.saveGState()
            ctx.setBlendMode(.destinationOut)
            AnnotationDrawing.drawCenteredDigit(
                "1",
                at: CGPoint(x: rect.midX, y: rect.midY),
                font: NSFont.systemFont(ofSize: 9, weight: .bold),
                color: .black
            )
            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func stepKindTooltip(_ kind: StepChromeKind) -> String {
        switch kind {
        case .filled: return "Filled"
        case .outline: return "Outline"
        case .plain: return "Number only"
        }
    }

    /// Sub-toolbar chrome previews (filled / outline / plain).
    private func stepChromeIcon(kind: StepChromeKind, selected: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let accent = selected ? NSColor.systemBlue : NSColor(calibratedWhite: 0.28, alpha: 1)
        return NSImage(size: size, flipped: false) { rect in
            let d: CGFloat = 14
            let disk = CGRect(
                x: (rect.width - d) / 2,
                y: (rect.height - d) / 2,
                width: d,
                height: d
            )
            let digitColor: NSColor
            switch kind {
            case .filled:
                accent.setFill()
                NSBezierPath(ovalIn: disk).fill()
                digitColor = .white
            case .outline:
                let path = NSBezierPath(ovalIn: disk.insetBy(dx: 0.75, dy: 0.75))
                path.lineWidth = 1.5
                accent.setStroke()
                path.stroke()
                digitColor = accent
            case .plain:
                // Dashed rounded plate so a bare “1” still reads as a tool chip.
                let plate = disk.insetBy(dx: 0.5, dy: 0.5)
                let frame = NSBezierPath(roundedRect: plate, xRadius: 3, yRadius: 3)
                frame.lineWidth = 1.25
                let dash: [CGFloat] = [2.5, 1.5]
                frame.setLineDash(dash, count: dash.count, phase: 0)
                accent.setStroke()
                frame.stroke()
                digitColor = accent
            }
            let font = NSFont.systemFont(ofSize: 9, weight: .bold)
            AnnotationDrawing.drawCenteredDigit(
                "1",
                at: CGPoint(x: rect.midX, y: rect.midY),
                font: font,
                color: digitColor
            )
            return true
        }
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

    @objc private func markerTapped() {
        selectTool(tool == .marker ? .none : .marker)
    }

    @objc private func textTapped() {
        selectTool(tool == .text ? .none : .text)
    }

    @objc private func stepTapped() {
        selectTool(tool == .step ? .none : .step)
    }

    @objc private func magnifierTapped() {
        selectTool(tool == .magnifier ? .none : .magnifier)
    }

    @objc private func eraserTapped() {
        selectTool(tool == .eraser ? .none : .eraser)
    }

    @objc private func magnifierRectTapped() {
        magnifierKind = .rectangle
        refreshSelectionChrome()
        emitMagnifierChanged()
    }

    @objc private func magnifierOvalTapped() {
        magnifierKind = .ellipse
        refreshSelectionChrome()
        emitMagnifierChanged()
    }

    @objc private func magnifierStrokeTapped(_ sender: NSButton) {
        let option = StrokeWidthOption(rawValue: sender.tag) ?? .medium
        magnifierStyle.strokeWidth = option.points
        refreshSelectionChrome()
        emitMagnifierChanged()
    }

    @objc private func magnifierIncludeTapped() {
        magnifierStyle.includeAnnotations.toggle()
        refreshSelectionChrome()
        emitMagnifierChanged()
    }

    @objc private func magnifierScaleChanged(_ sender: MosaicIntensitySlider) {
        magnifierStyle.scale = MagnifierStyle.clampedScale(CGFloat(sender.doubleValue))
        magnifierScaleLabel.stringValue = Self.formatMagnifierScale(magnifierStyle.scale)
        magnifierScalePreview.scale = magnifierStyle.scale
        magnifierScalePreview.needsDisplay = true
        emitMagnifierChanged()
    }

    private static func formatMagnifierScale(_ scale: CGFloat) -> String {
        String(format: "%.2f", MagnifierStyle.clampedScale(scale))
    }

    private func emitMagnifierChanged() {
        onEvent(.magnifierChanged(kind: magnifierKind, style: magnifierStyle))
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

    @objc private func mosaicIntensityChanged(_ sender: MosaicIntensitySlider) {
        mosaicStyle.intensity = MosaicStyle.clampedIntensity(CGFloat(sender.doubleValue))
        mosaicIntensityLabel.stringValue = "\(Int(mosaicStyle.intensity.rounded()))"
        mosaicIntensityPreview.intensity = mosaicStyle.intensity
        mosaicIntensityPreview.needsDisplay = true
        onEvent(.mosaicStyleChanged(mosaicStyle))
    }

    @objc private func markerBrushTapped(_ sender: NSButton) {
        markerStyle.brushWidth = MarkerStyle.nearestBrushPreset(CGFloat(sender.tag))
        markerDrawMode = .freehand
        refreshMarkerChrome()
        onEvent(.markerDrawModeChanged(markerDrawMode))
        onEvent(.markerStyleChanged(markerStyle))
    }

    @objc private func markerRectTapped() {
        markerDrawMode = .rectangle
        refreshMarkerChrome()
        onEvent(.markerDrawModeChanged(markerDrawMode))
    }

    @objc private func markerOvalTapped() {
        markerDrawMode = .ellipse
        refreshMarkerChrome()
        onEvent(.markerDrawModeChanged(markerDrawMode))
    }

    @objc private func eraserBrushTapped(_ sender: NSButton) {
        eraserStyle.brushWidth = EraserStyle.nearestBrushPreset(CGFloat(sender.tag))
        eraserDrawMode = .freehand
        refreshEraserChrome()
        onEvent(.eraserDrawModeChanged(eraserDrawMode))
        onEvent(.eraserStyleChanged(eraserStyle))
    }

    @objc private func eraserRectTapped() {
        eraserDrawMode = .rectangle
        refreshEraserChrome()
        onEvent(.eraserDrawModeChanged(eraserDrawMode))
    }

    @objc private func eraserOvalTapped() {
        eraserDrawMode = .ellipse
        refreshEraserChrome()
        onEvent(.eraserDrawModeChanged(eraserDrawMode))
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

    @objc private func stepKindTapped(_ sender: NSButton) {
        stepStyle.kind = StepChromeKind(rawValue: sender.tag) ?? .filled
        refreshSelectionChrome()
        onEvent(.stepStyleChanged(stepStyle))
    }

    @objc private func stepSizeTapped(_ sender: NSButton) {
        let menu = NSMenu()
        for size in StepStyle.sizeChoices {
            let item = NSMenuItem(
                title: "\(Int(size))",
                action: #selector(stepSizeMenuPicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Int(size)
            item.state = (abs(size - stepStyle.size) < 0.5) ? .on : .off
            menu.addItem(item)
        }
        let point = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func stepSizeMenuPicked(_ sender: NSMenuItem) {
        stepStyle.size = StepStyle.nearestSize(CGFloat(sender.tag))
        refreshSelectionChrome()
        onEvent(.stepStyleChanged(stepStyle))
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
    @objc private func ocrTapped() { onEvent(.ocr) }
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

/// White rounded chrome card; Snipaste-like blue accent under the hovered tool button.
final class HoverChromeCard: NSView {
    private static let cornerRadius: CGFloat = 6
    private static let accentHeight: CGFloat = 2
    /// If the tool sits within this inset of a side, extend the bar into that rounded corner.
    private static let edgeExtendSlop: CGFloat = 10

    private let chrome = NSView(frame: .zero)
    private let accent = NSView(frame: .zero)
    private var trackingArea: NSTrackingArea?
    private weak var hoveredButton: NSButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        translatesAutoresizingMaskIntoConstraints = false

        chrome.wantsLayer = true
        chrome.layer?.backgroundColor = NSColor.white.cgColor
        chrome.layer?.cornerRadius = Self.cornerRadius
        chrome.layer?.masksToBounds = true
        chrome.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chrome)

        accent.wantsLayer = true
        accent.layer?.backgroundColor = NSColor.systemBlue.cgColor
        accent.alphaValue = 0
        // Frame-positioned under the hovered tool (not Auto Layout).
        accent.translatesAutoresizingMaskIntoConstraints = true
        chrome.addSubview(accent)

        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            chrome.topAnchor.constraint(equalTo: topAnchor),
            chrome.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func installContent(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        chrome.addSubview(child, positioned: .below, relativeTo: accent)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: chrome.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: chrome.trailingAnchor),
            child.topAnchor.constraint(equalTo: chrome.topAnchor),
            child.bottomAnchor.constraint(equalTo: chrome.bottomAnchor),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // Nonactivating toolbar panel — same as palette / mosaic slider.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        syncHover(from: event)
    }

    override func mouseMoved(with event: NSEvent) {
        syncHover(from: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredButton(nil)
    }

    override func layout() {
        super.layout()
        if let hoveredButton {
            positionAccent(under: hoveredButton, animated: false)
        }
    }

    private func syncHover(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setHoveredButton(toolButton(at: point))
    }

    private func toolButton(at point: CGPoint) -> NSButton? {
        let local = chrome.convert(point, from: self)
        guard let hit = chrome.hitTest(local) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== chrome {
            if let button = current as? NSButton {
                return button
            }
            view = current.superview
        }
        return nil
    }

    private func setHoveredButton(_ button: NSButton?) {
        if hoveredButton === button { return }
        hoveredButton = button
        if let button {
            positionAccent(under: button, animated: true)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                accent.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                accent.animator().alphaValue = 0
            }
        }
    }

    private func positionAccent(under button: NSButton, animated: Bool) {
        let buttonRect = button.convert(button.bounds, to: chrome)
        var x = buttonRect.minX
        var width = buttonRect.width
        let bounds = chrome.bounds

        // Snipaste: first / last tools extend the bar into the card’s rounded corners.
        if buttonRect.minX <= Self.edgeExtendSlop {
            width += x
            x = 0
        }
        if buttonRect.maxX >= bounds.width - Self.edgeExtendSlop {
            width = bounds.width - x
        }

        let target = CGRect(
            x: x,
            y: 0,
            width: max(width, 1),
            height: Self.accentHeight
        )
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                accent.animator().frame = target
            }
        } else {
            accent.frame = target
        }
    }
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

/// Snipaste-like value slider (mosaic intensity / magnifier scale): blue filled track
/// to the left of the knob, gray remainder; circular knob is hollow until hover / drag.
final class MosaicIntensitySlider: NSView {
    var minValue: Double = 3
    var maxValue: Double = 24
    var doubleValue: Double = 10 {
        didSet {
            let clamped = min(max(doubleValue, minValue), maxValue)
            if clamped != doubleValue {
                doubleValue = clamped
                return
            }
            needsDisplay = true
        }
    }

    weak var target: AnyObject?
    var action: Selector?

    private var isHovered = false
    private var isDragging = false
    private var trackingArea: NSTrackingArea?

    private static let accent = NSColor.systemBlue
    private static let trackGray = NSColor(calibratedWhite: 0.72, alpha: 1)
    private static let knobDiameter: CGFloat = 12
    private static let trackHeight: CGFloat = 3

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // Toolbar is a nonactivating panel — must use `.activeAlways` (same as palette chips).
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        syncHoverFromMouseLocation()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            setHovered(false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        setHovered(true)
        updateValue(from: event, notify: true)
        // Keep receiving drag/up even if the pointer leaves the view.
        var keepGoing = true
        while keepGoing {
            guard let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { break }
            switch next.type {
            case .leftMouseDragged:
                updateValue(from: next, notify: true)
            default:
                keepGoing = false
            }
        }
        isDragging = false
        syncHoverFromMouseLocation()
        needsDisplay = true
    }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        needsDisplay = true
    }

    private func syncHoverFromMouseLocation() {
        guard let window else { return }
        let loc = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(loc))
    }

    private func updateValue(from event: NSEvent, notify: Bool) {
        let x = convert(event.locationInWindow, from: nil).x
        let inset = Self.knobDiameter / 2
        let usable = max(bounds.width - Self.knobDiameter, 1)
        let t = min(max((x - inset) / usable, 0), 1)
        let next = minValue + t * (maxValue - minValue)
        guard abs(next - doubleValue) > 0.0001 else { return }
        doubleValue = next
        guard notify, let target, let action else { return }
        _ = target.perform(action, with: self)
    }

    private var knobCenterX: CGFloat {
        let inset = Self.knobDiameter / 2
        let usable = max(bounds.width - Self.knobDiameter, 1)
        let t = (doubleValue - minValue) / max(maxValue - minValue, 0.0001)
        return inset + CGFloat(t) * usable
    }

    override func draw(_ dirtyRect: NSRect) {
        let midY = bounds.midY
        let inset = Self.knobDiameter / 2
        let trackY = midY - Self.trackHeight / 2
        let trackRect = CGRect(
            x: inset,
            y: trackY,
            width: max(bounds.width - Self.knobDiameter, 0),
            height: Self.trackHeight
        )
        let radius = Self.trackHeight / 2
        let cx = knobCenterX

        // Right (unfilled) track.
        let grayPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
        Self.trackGray.setFill()
        grayPath.fill()

        // Left (filled) track through the knob center.
        let filledWidth = max(cx - trackRect.minX, 0)
        if filledWidth > 0 {
            let filled = CGRect(
                x: trackRect.minX,
                y: trackRect.minY,
                width: filledWidth,
                height: trackRect.height
            )
            let bluePath = NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius)
            Self.accent.setFill()
            bluePath.fill()
        }

        // Circular knob: hollow by default, filled on hover / drag.
        let knobRect = CGRect(
            x: cx - Self.knobDiameter / 2,
            y: midY - Self.knobDiameter / 2,
            width: Self.knobDiameter,
            height: Self.knobDiameter
        )
        let knobPath = NSBezierPath(ovalIn: knobRect.insetBy(dx: 0.5, dy: 0.5))
        let fillKnob = isHovered || isDragging
        if fillKnob {
            Self.accent.setFill()
            knobPath.fill()
        } else {
            // Punch a hole so the track doesn't show through the hollow ring.
            NSColor.white.setFill()
            knobPath.fill()
            Self.accent.setStroke()
            knobPath.lineWidth = 1.5
            knobPath.stroke()
        }
    }
}

/// Solid dot whose diameter tracks magnifier zoom (1×…6×) — Snipaste-style scale preview.
final class MagnifierScalePreviewView: NSView {
    var scale: CGFloat = MagnifierStyle.defaultScale {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let s = MagnifierStyle.clampedScale(scale)
        let t = (s - MagnifierStyle.scaleRange.lowerBound)
            / (MagnifierStyle.scaleRange.upperBound - MagnifierStyle.scaleRange.lowerBound)
        let diameter = 4 + t * 10 // 4pt @ 1× → 14pt @ 6×
        let rect = CGRect(
            x: (bounds.width - diameter) / 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect).fill()
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
        filter?.setValue(Self.sampleImage.clampedToExtent(), forKey: kCIInputImageKey)
        filter?.setValue(max(radius * 1.2, 0.35), forKey: kCIInputRadiusKey)

        let shapePath = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))

        NSGraphicsContext.current?.saveGraphicsState()
        shapePath.addClip()
        let extent = Self.sampleImage.extent
        if let blurred = filter?.outputImage?.cropped(to: extent),
           let cg = Self.ciContext.createCGImage(blurred, from: extent) {
            NSImage(cgImage: cg, size: bounds.size)
                .draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        } else {
            NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
            shapePath.fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
