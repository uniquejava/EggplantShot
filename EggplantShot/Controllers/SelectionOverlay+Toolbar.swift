import AppKit

// Overlay highlight chrome + refine toolbar.

@MainActor
extension SelectionOverlayController {
    // MARK: - Drawing / toolbar

    var isDraggingEditingText: Bool {
        guard let id = editingTextID,
              case .annotateMove(let moveID, _, _, _) = dragKind
        else { return false }
        return moveID == id
    }

    /// Live chrome frame in Cocoa global coordinates while editing.
    func editingTextGlobalRect() -> CGRect? {
        guard let chrome = textChromeView, let host = textEditorHost else { return nil }
        return CGRect(
            x: chrome.frame.minX + host.screenFrame.minX,
            y: chrome.frame.minY + host.screenFrame.minY,
            width: chrome.frame.width,
            height: chrome.frame.height
        )
    }

    /// Pass mouse events to `NSTextView` only for interior typing/selection — not border move.
    func shouldPassThroughToTextEditor(at point: CGPoint, event: NSEvent) -> Bool {
        guard let id = editingTextID else { return false }
        if dragKind != nil { return false }
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            if case .interior(let hitID) = annotationPointerTarget(at: point), hitID == id {
                return true
            }
            return false
        case .mouseMoved:
            // Cursor already updated by the monitor; let the field editor see moves over interior.
            if case .interior(let hitID) = annotationPointerTarget(at: point), hitID == id {
                return true
            }
            return false
        default:
            return false
        }
    }

    func repositionEditingChrome(dragDelta: CGSize) {
        guard let chrome = textChromeView,
              let host = textEditorHost,
              let startFrame = textChromeDragStartFrame
        else { return }
        var frame = startFrame
        frame.origin.x += dragDelta.width
        frame.origin.y += dragDelta.height
        let screen = host.screenFrame
        frame.origin.x = min(max(frame.origin.x, 0), max(0, screen.width - frame.width))
        frame.origin.y = min(max(frame.origin.y, 0), max(0, screen.height - frame.height))
        chrome.frame = frame
        textEditor?.frame = chrome.bounds
        chrome.needsDisplay = true
    }

    func updateHighlight(showHandles: Bool) {
        let selected = selectedAnnotationID.flatMap { id in annotations.first(where: { $0.id == id }) }
        if let hid = hoveredMarkerRegionID, hid == selectedAnnotationID {
            hoveredMarkerRegionID = nil
        }
        let movingOrResizingMarkerRegion: Bool = {
            switch dragKind {
            case .annotateResize(_, _, let start, _, _), .annotateMove(_, let start, _, _):
                return start.isMarkerRegion
            default:
                return false
            }
        }()
        for panel in panels {
            panel.setSelection(
                currentRect,
                // Crop resize chrome stays while any annotate tool is active (export size).
                showHandles: showHandles,
                handleVisualSize: handleVisualSize,
                annotations: annotations,
                draftAnnotation: draftAnnotation,
                selectedAnnotation: selected,
                annotationHandleSize: annotationHandleVisualSize,
                playbackImage: playbackBaseImage,
                editingAnnotationID: editingTextID,
                hoveredTextID: hoveredTextID,
                hoveredMarkerRegionID: hoveredMarkerRegionID,
                showSolidMarkerRegionBorder: movingOrResizingMarkerRegion,
                hiddenMagnifierSourceIDs: hiddenMagnifierSourceIDs()
            )
        }
    }

    func showToolbar() {
        toolbar?.close()
        let bar = RefineToolbarController(
            primaryAction: primaryAction,
            initialTool: annotateTool,
            initialStyle: annotationStyle,
            initialKind: annotationKind,
            initialArrowCaps: arrowCaps,
            initialTextStyle: textStyle,
            initialMosaicStyle: mosaicStyle,
            initialMosaicDrawMode: mosaicDrawMode,
            initialMarkerStyle: markerStyle,
            initialMarkerDrawMode: markerDrawMode,
            initialEraserStyle: eraserStyle,
            initialEraserDrawMode: eraserDrawMode,
            initialStepStyle: stepStyle,
            initialMagnifierKind: magnifierKind,
            initialMagnifierStyle: magnifierStyle
        ) { [weak self] event in
            guard let self else { return }
            switch event {
            case .confirm(let action):
                switch action {
                case .pin: self.confirm(.pin)
                case .copy: self.confirm(.copy)
                case .save: self.confirm(.save)
                case .cancel:
                    self.tearDownOverlays()
                    self.finish(.cancelled)
                }
            case .selectTool(let tool):
                self.setAnnotateTool(tool)
            case .styleChanged(let style):
                self.applyStyle(style)
            case .textStyleChanged(let style):
                self.applyTextStyle(style)
            case .mosaicStyleChanged(let style):
                self.applyMosaicStyle(style)
            case .mosaicDrawModeChanged(let mode):
                self.applyMosaicDrawMode(mode)
            case .markerStyleChanged(let style):
                self.applyMarkerStyle(style)
            case .markerDrawModeChanged(let mode):
                self.applyMarkerDrawMode(mode)
            case .eraserStyleChanged(let style):
                self.applyEraserStyle(style)
            case .eraserDrawModeChanged(let mode):
                self.applyEraserDrawMode(mode)
            case .stepStyleChanged(let style):
                self.applyStepStyle(style)
            case .magnifierChanged(let kind, let style):
                self.applyMagnifier(kind: kind, style: style)
            case .kindChanged(let kind):
                self.applyKind(kind)
            case .arrowCapsChanged(let caps):
                self.applyArrowCaps(caps)
            case .ocr:
                self.performOCR()
            case .undo:
                self.performUndo()
            case .redo:
                self.performRedo()
            }
        }
        toolbar = bar
        refreshHistoryChrome()
        repositionToolbar()
        bar.orderFront()
    }

    func repositionToolbar() {
        guard let toolbar, !currentRect.isNull else { return }
        toolbar.reposition(around: currentRect)
        // Dragging on the full-screen overlay can raise it above the toolbar;
        // keep the bar strictly in front after every move/resize.
        toolbar.orderFront()
    }
}
