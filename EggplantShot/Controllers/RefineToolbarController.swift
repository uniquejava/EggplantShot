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
}
