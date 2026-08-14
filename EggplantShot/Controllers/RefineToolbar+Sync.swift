import AppKit

extension RefineToolbarController {
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

}
