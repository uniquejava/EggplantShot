import AppKit

// Annotation hit-testing and hover.

@MainActor
extension SelectionOverlayController {
    func annotationPointerTarget(at point: CGPoint) -> AnnotationPointerTarget {
        // `.none` still hit-tests marks — a mark that exists stays grabbable — but its empty space
        // belongs to the crop, so the miss case below returns `.outside` instead of `.draw`.

        // Live editor chrome wins over the (possibly stale) mark rect.
        if let id = editingTextID, let live = editingTextGlobalRect() {
            // Corner badges (incl. close) sit on / outside the frame — check first.
            if let corner = hitTestTextCornerBadge(at: point, globalRect: live) {
                switch corner {
                case .close:
                    return .textClose(id: id)
                case .resize(let handle):
                    return .handle(id: id, handle: handle)
                }
            }
            switch textFrameHit(at: point, globalRect: live) {
            case .border:
                return .border(id: id)
            case .interior:
                return .interior(id: id)
            case .none:
                break
            }
        }

        // Text corner badges (Snipaste): visible on hover/selection; grab before body hit.
        // Under paint draw-through, only the selected mark’s badges stay live (same as shapes).
        if let textHit = hitTestTextCornerBadge(at: point) {
            let allowUnselected = !annotateTool.drawsThroughMarks
            if allowUnselected || textHit.id == selectedAnnotationID {
                switch textHit.corner {
                case .close:
                    return .textClose(id: textHit.id)
                case .resize(let handle):
                    return .handle(id: textHit.id, handle: handle)
                }
            }
        }

        if let id = selectedAnnotationID,
           id != editingTextID,
           let ann = annotations.first(where: { $0.id == id }),
           !ann.isText {
            if ann.isArrow, let endpoint = hitTestArrowEndpoint(at: point, annotation: ann) {
                return .arrowEndpoint(id: id, endpoint: endpoint)
            }
            if ann.isMagnifier, let hit = hitTestMagnifierHandle(at: point, annotation: ann) {
                return .handle(id: id, handle: hit.handle)
            }
            if let handle = hitTestAnnotationHandle(at: point, annotation: ann) {
                return .handle(id: id, handle: handle)
            }
        }

        let commandHeld = NSEvent.modifierFlags.contains(.command)

        // Paint tools (pencil / marker / mosaic / eraser): always draw-through. Move via **V**.
        // Selected handles still work (checked above).
        if annotateTool.drawsThroughMarks {
            // …except in a rect / oval draw mode, where the tool drags out a region like the shape
            // tool rather than brushing. There an existing region mark is grabbable by its whole
            // **body** (move), so a highlight keeps its handles after losing selection instead of
            // becoming permanently inert. Body — not border-only like shapes — because these marks
            // have no interior to nest-draw into; the trade is that starting a new region *inside*
            // an existing one needs V, Esc, or a start point outside it.
            // Brush strokes stay draw-through in every mode: never steal freehand work.
            if armedPaintRegionMode != nil {
                for ann in annotations.reversed() where ann.isPaintRegionMark {
                    if isInsidePaintRegion(ann, at: point) {
                        return .border(id: ann.id)
                    }
                }
            }
            return .draw
        }

        // Step is click-to-stamp: place through shapes / arrows / text / etc. Existing step
        // badges stay moveable so you can rearrange numbers without ⌘.
        if annotateTool == .step, !commandHeld {
            for ann in annotations.reversed() {
                guard ann.isStep else { continue }
                if toGlobal(ann.boundingRect).insetBy(dx: -2, dy: -2).contains(point) {
                    return .border(id: ann.id)
                }
            }
            return .draw
        }

        // Non-drawing modes — Move (V) and `.none` — grab any mark by its whole body.
        let editsMarksOnly = annotateTool.editsMarksOnly

        for ann in annotations.reversed() {
            if ann.id == editingTextID { continue }
            if ann.isText {
                let global = toGlobal(ann.boundingRect)
                switch textFrameHit(at: point, globalRect: global) {
                case .none:
                    break
                case .border:
                    return .border(id: ann.id)
                case .interior:
                    // Text tool: interior is edit. Select / other tools: whole body moves.
                    if annotateTool == .text {
                        return .interior(id: ann.id)
                    }
                    return .border(id: ann.id)
                }
                continue
            }
            if ann.isStep {
                // Entire badge is a move target (no interior edit / no resize).
                if toGlobal(ann.boundingRect).insetBy(dx: -2, dy: -2).contains(point) {
                    return .border(id: ann.id)
                }
                continue
            }
            if ann.isMagnifier {
                // Source / lens body moves that part (no nested draw into the frames).
                if magnifierMovePart(at: point, annotation: ann) != nil {
                    return .border(id: ann.id)
                }
                continue
            }
            // Under drawing tools, paint-like marks always draw-through — move via **V** / `.none`.
            if !editsMarksOnly, ann.isPaintLikeMark {
                continue
            }
            // Non-drawing modes: whole shape body is grabable (not just the stroke ring).
            // Shape tool keeps border-only so interior can still nest-draw.
            if editsMarksOnly, ann.isShape, isInsideAnnotationShape(ann, at: point) {
                return .border(id: ann.id)
            }
            if isOnAnnotationStroke(ann, at: point) {
                return .border(id: ann.id)
            }
        }

        // Any point on the overlay is a draw target while a drawing tool is active.
        // Select tool (V): `.draw` means empty space (deselect; no create) — see mouseDown.
        // `.none`: empty space is the crop's — border resize / outside expand.
        return annotateTool == .none ? .outside : .draw
    }

    enum TextFrameHit {
        case border
        case interior
    }

    /// Border strip is the move handle; interior is for typing.
    /// Inward strip (~3pt) plus a small outward slop so the hairline is easy to grab.
    func textFrameHit(at point: CGPoint, globalRect: CGRect) -> TextFrameHit? {
        let hitBounds = globalRect.insetBy(dx: -textBorderOutwardSlop, dy: -textBorderOutwardSlop)
        guard hitBounds.contains(point) else { return nil }
        let inset = min(3, min(globalRect.width, globalRect.height) / 4)
        if globalRect.width <= inset * 2 || globalRect.height <= inset * 2 {
            return .border
        }
        if !globalRect.contains(point) {
            return .border
        }
        let inner = globalRect.insetBy(dx: inset, dy: inset)
        return inner.contains(point) ? .interior : .border
    }

    func textMarkID(at point: CGPoint) -> UUID? {
        if let id = editingTextID, let live = editingTextGlobalRect() {
            let c = AnnotationDrawing.textCornerBadgeCenters(in: live)
            let pad = AnnotationDrawing.textCornerBadgeSize / 2 + 2
            let hoverBounds = live
                .union(CGRect(x: c.topLeft.x - pad, y: c.topLeft.y - pad, width: pad * 2, height: pad * 2))
                .union(CGRect(x: c.topRight.x - pad, y: c.topRight.y - pad, width: pad * 2, height: pad * 2))
                .union(CGRect(x: c.bottomLeft.x - pad, y: c.bottomLeft.y - pad, width: pad * 2, height: pad * 2))
                .union(CGRect(x: c.bottomRight.x - pad, y: c.bottomRight.y - pad, width: pad * 2, height: pad * 2))
            if hoverBounds.contains(point) {
                return id
            }
        }
        for ann in annotations.reversed() {
            if ann.id == editingTextID { continue }
            guard ann.isText else { continue }
            let global = toGlobal(ann.boundingRect)
            if global.contains(point) { return ann.id }
            // Corner badges sit outside the glyph box — still count as hover.
            if hitTestTextCornerBadge(at: point, globalRect: global) != nil {
                return ann.id
            }
        }
        return nil
    }

    func updateHoveredText(at point: CGPoint) {
        let id = textMarkID(at: point)
        let changed = id != hoveredTextID
        if changed {
            hoveredTextID = id
            updateHighlight(showHandles: true)
        }
        // Editing chrome draws its own badges above the field editor — hide only after a real drag.
        let showEditBadges = !suppressTextCornerBadges && editingTextID != nil && id == editingTextID
        if textChromeView?.showsCornerBadges != showEditBadges {
            textChromeView?.showsCornerBadges = showEditBadges
        }
    }

    /// Non-selected rect / oval paint region (marker / mosaic / eraser) under the pointer.
    func paintRegionID(at point: CGPoint) -> UUID? {
        // Only advertise a grab the click will honor: a non-drawing mode (V / `.none`) or a
        // rect / oval paint mode. Under a brush (or any object tool) the pointer draws through, so
        // a dashed outline there would promise a move that never happens.
        guard annotateTool.editsMarksOnly || armedPaintRegionMode != nil else { return nil }
        for ann in annotations.reversed() {
            guard ann.isPaintRegionMark else { continue }
            // Selected mark uses handles chrome, not hover dashed.
            if ann.id == selectedAnnotationID { continue }
            if isInsidePaintRegion(ann, at: point) {
                return ann.id
            }
        }
        return nil
    }

    func updateHoveredPaintRegion(at point: CGPoint) {
        let id = paintRegionID(at: point)
        guard id != hoveredPaintRegionID else { return }
        hoveredPaintRegionID = id
        updateHighlight(showHandles: true)
    }

    /// Reveal nested magnifier source frames while the pointer is over their lens.
    func updateHoveredMagnifier(at point: CGPoint) {
        let next = magnifierLensIDs(containing: point)
        guard next != hoveredMagnifierLensIDs else { return }
        hoveredMagnifierLensIDs = next
        updateHighlight(showHandles: true)
    }

    func magnifierLensIDs(containing point: CGPoint) -> Set<UUID> {
        let mags = annotations.filter(\.isMagnifier)
        guard mags.count >= 2 else { return [] }

        var ids = Set<UUID>()
        for ann in mags {
            guard case .magnifier(let kind, let source, let lens, let style) = ann.payload else {
                continue
            }
            // Only track hover for marks whose source would otherwise be hidden.
            guard AnnotationDrawing.isMagnifierSourceNestedInLens(
                kind: kind,
                source: source,
                lens: lens
            ) else { continue }
            let tolerance = max(style.strokeWidth / 2 + 2, annotationBorderHitSlop)
            if magnifierShapeContains(
                kind: kind,
                globalRect: toGlobal(lens),
                point: point,
                tolerance: tolerance
            ) {
                ids.insert(ann.id)
            }
        }
        return ids
    }

    /// Nested source borders hidden for declutter (≥2 magnifiers); hover / selection reveals them.
    func hiddenMagnifierSourceIDs() -> Set<UUID> {
        var revealed = hoveredMagnifierLensIDs
        if let selectedAnnotationID {
            revealed.insert(selectedAnnotationID)
        }
        // Keep source visible while actively moving / resizing that magnifier.
        switch dragKind {
        case .annotateMove(let id, _, _, _), .annotateResize(let id, _, _, _, _):
            revealed.insert(id)
        default:
            break
        }
        if let draft = draftAnnotation, draft.isMagnifier {
            revealed.insert(draft.id)
        }
        return AnnotationDrawing.nestedMagnifierSourceIDsToHide(
            in: annotations,
            revealedIDs: revealed
        )
    }

    func isOnAnnotationStroke(_ annotation: Annotation, at globalPoint: CGPoint) -> Bool {
        switch annotation.payload {
        case .shape(let kind, let localRect, let style):
            let rect = toGlobal(localRect)
            let halfStroke = style.isFilled ? 0 : style.strokeWidth / 2
            let tolerance = max(halfStroke + 2, annotationBorderHitSlop)
            let local = CGPoint(x: globalPoint.x - rect.minX, y: globalPoint.y - rect.minY)

            switch kind {
            case .rectangle:
                let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
                guard outer.contains(globalPoint) else { return false }
                if rect.width <= tolerance * 2 || rect.height <= tolerance * 2 {
                    return true
                }
                let inner = rect.insetBy(dx: tolerance, dy: tolerance)
                return !inner.contains(globalPoint)

            case .ellipse:
                return isOnEllipseRing(size: rect.size, localPoint: local, tolerance: tolerance)
            }

        case .pencil(let points, let style):
            let local = toLocal(globalPoint)
            let tolerance = max(style.strokeWidth / 2 + 2, annotationBorderHitSlop)
            return AnnotationDrawing.distance(from: local, toPolyline: points) <= tolerance

        case .mosaic(let geometry, let style):
            let local = toLocal(globalPoint)
            switch geometry {
            case .stroke(let points):
                let tolerance = max(style.brushWidth / 2 + 2, annotationBorderHitSlop)
                return AnnotationDrawing.distance(from: local, toPolyline: points) <= tolerance
            case .region(let mode, let rect):
                let global = toGlobal(rect)
                switch mode {
                case .ellipse:
                    let localIn = CGPoint(x: globalPoint.x - global.minX, y: globalPoint.y - global.minY)
                    let nx = (localIn.x - global.width / 2) / max(global.width / 2, 0.5)
                    let ny = (localIn.y - global.height / 2) / max(global.height / 2, 0.5)
                    return nx * nx + ny * ny <= 1
                case .rectangle, .freehand:
                    return global.contains(globalPoint)
                }
            }

        case .marker(let geometry, let style):
            let local = toLocal(globalPoint)
            switch geometry {
            case .stroke(let points):
                let tolerance = max(style.brushWidth / 2 + 2, annotationBorderHitSlop)
                return AnnotationDrawing.distance(from: local, toPolyline: points) <= tolerance
            case .region(let mode, let rect):
                let global = toGlobal(rect)
                switch mode {
                case .ellipse:
                    let localIn = CGPoint(x: globalPoint.x - global.minX, y: globalPoint.y - global.minY)
                    let nx = (localIn.x - global.width / 2) / max(global.width / 2, 0.5)
                    let ny = (localIn.y - global.height / 2) / max(global.height / 2, 0.5)
                    return nx * nx + ny * ny <= 1
                case .rectangle, .freehand:
                    return global.contains(globalPoint)
                }
            }

        case .eraser(let geometry, let style):
            let local = toLocal(globalPoint)
            switch geometry {
            case .stroke(let points):
                let tolerance = max(style.brushWidth / 2 + 2, annotationBorderHitSlop)
                return AnnotationDrawing.distance(from: local, toPolyline: points) <= tolerance
            case .region(let mode, let rect):
                let global = toGlobal(rect)
                switch mode {
                case .ellipse:
                    let localIn = CGPoint(x: globalPoint.x - global.minX, y: globalPoint.y - global.minY)
                    let nx = (localIn.x - global.width / 2) / max(global.width / 2, 0.5)
                    let ny = (localIn.y - global.height / 2) / max(global.height / 2, 0.5)
                    return nx * nx + ny * ny <= 1
                case .rectangle, .freehand:
                    return global.contains(globalPoint)
                }
            }

        case .arrow(let start, let end, let style, let caps):
            let local = toLocal(globalPoint)
            let tolerance = max(style.strokeWidth / 2 + 2, annotationBorderHitSlop)
            return AnnotationDrawing.hitsArrow(
                point: local,
                start: start,
                end: end,
                style: style,
                caps: caps,
                tolerance: tolerance
            )

        case .text, .step:
            return false

        case .magnifier(let kind, let source, let lens, let style):
            let tolerance = max(style.strokeWidth / 2 + 2, annotationBorderHitSlop)
            return magnifierShapeContains(
                kind: kind,
                globalRect: toGlobal(source),
                point: globalPoint,
                tolerance: tolerance
            ) || magnifierShapeContains(
                kind: kind,
                globalRect: toGlobal(lens),
                point: globalPoint,
                tolerance: tolerance
            )
        }
    }

    /// Rect / oval draw mode of the armed paint tool; `nil` for freehand and non-paint tools.
    /// In these modes the paint tool behaves like the shape tool (drag out a region), which is why
    /// existing region marks stay grabbable instead of being drawn through.
    var armedPaintRegionMode: MosaicDrawMode? {
        let mode: MosaicDrawMode
        switch annotateTool {
        case .marker: mode = markerDrawMode
        case .mosaic: mode = mosaicDrawMode
        case .eraser: mode = eraserDrawMode
        case .none, .select, .rectangle, .arrow, .pencil, .text, .step, .magnifier:
            return nil
        }
        return mode == .freehand ? nil : mode
    }

    /// Whole body (interior + border, plus grab slop) of a rect / oval paint mark.
    func isInsidePaintRegion(_ annotation: Annotation, at globalPoint: CGPoint) -> Bool {
        guard let region = annotation.paintRegion else { return false }
        return magnifierShapeContains(
            kind: region.mode == .ellipse ? .ellipse : .rectangle,
            globalRect: toGlobal(region.rect),
            point: globalPoint,
            tolerance: annotationBorderHitSlop
        )
    }

    /// Full shape body (rect / oval interior + border). Used by Move (V) so hollow frames
    /// are easy to grab without hunting the stroke ring.
    func isInsideAnnotationShape(_ annotation: Annotation, at globalPoint: CGPoint) -> Bool {
        guard case .shape(let kind, let localRect, _) = annotation.payload else { return false }
        return magnifierShapeContains(
            kind: kind,
            globalRect: toGlobal(localRect),
            point: globalPoint,
            tolerance: annotationBorderHitSlop
        )
    }

    func hitTestAnnotationHandle(at point: CGPoint, annotation: Annotation) -> Handle? {
        // Pencil / freehand mosaic / marker / eraser / text / arrow / step: no 8-handle resize chrome.
        // Text uses dedicated 4-corner badges (`hitTestTextCornerBadge`).
        // Magnifier uses dedicated dual-frame handle hit-testing.
        // Mosaic / marker / eraser region (rect/oval) uses the same 8 handles as shapes.
        guard !annotation.isPencil, !annotation.isMosaicStroke, !annotation.isMarkerStroke,
              !annotation.isEraserStroke, !annotation.isText, !annotation.isArrow, !annotation.isStep,
              !annotation.isMagnifier else {
            return nil
        }
        let global = toGlobal(annotation.boundingRect)
        for handle in Handle.allCases {
            if handleHitRect(handle, in: global).contains(point) {
                return handle
            }
        }
        return nil
    }

    /// Snipaste text corner: top-right = close; other three = aspect-locked resize.
    enum TextCornerBadgeHit {
        case resize(Handle)
        case close
    }

    /// Snipaste text badges on any non-editing text mark.
    func hitTestTextCornerBadge(at point: CGPoint) -> (id: UUID, corner: TextCornerBadgeHit)? {
        for ann in annotations.reversed() {
            if ann.id == editingTextID { continue }
            guard ann.isText else { continue }
            if let corner = hitTestTextCornerBadge(at: point, globalRect: toGlobal(ann.boundingRect)) {
                return (ann.id, corner)
            }
        }
        return nil
    }

    func hitTestTextCornerBadge(at point: CGPoint, globalRect: CGRect) -> TextCornerBadgeHit? {
        let hit = max(handleHitSize, AnnotationDrawing.textCornerBadgeSize + 4)
        let c = AnnotationDrawing.textCornerBadgeCenters(in: globalRect)
        let corners: [(TextCornerBadgeHit, CGPoint)] = [
            (.resize(.topLeft), c.topLeft),
            (.close, c.topRight),
            (.resize(.bottomLeft), c.bottomLeft),
            (.resize(.bottomRight), c.bottomRight),
        ]
        for (corner, center) in corners {
            let r = CGRect(
                x: center.x - hit / 2,
                y: center.y - hit / 2,
                width: hit,
                height: hit
            )
            if r.contains(point) { return corner }
        }
        return nil
    }

    func hitTestMagnifierHandle(
        at point: CGPoint,
        annotation: Annotation
    ) -> (part: MagnifierPart, handle: Handle)? {
        guard case .magnifier(_, _, let lens, _) = annotation.payload else { return nil }
        // Source is move-only; lens handles resize selection area (source syncs at fixed scale).
        for handle in Handle.allCases {
            if handleHitRect(handle, in: toGlobal(lens)).contains(point) {
                return (.lens, handle)
            }
        }
        return nil
    }

    /// Which magnifier frame should move under `point` (source wins when nested overlap).
    func magnifierMovePart(at point: CGPoint, annotation: Annotation) -> MagnifierPart? {
        guard case .magnifier(let kind, let source, let lens, let style) = annotation.payload else {
            return nil
        }
        let tolerance = max(style.strokeWidth / 2 + 2, annotationBorderHitSlop)
        let sourceHidden = hiddenMagnifierSourceIDs().contains(annotation.id)
        let sourceHit = !sourceHidden && magnifierShapeContains(
            kind: kind,
            globalRect: toGlobal(source),
            point: point,
            tolerance: tolerance
        )
        let lensHit = magnifierShapeContains(
            kind: kind,
            globalRect: toGlobal(lens),
            point: point,
            tolerance: tolerance
        )
        if sourceHit { return .source }
        if lensHit { return .lens }
        return nil
    }

    func magnifierShapeContains(
        kind: ShapeKind,
        globalRect: CGRect,
        point: CGPoint,
        tolerance: CGFloat
    ) -> Bool {
        let outer = globalRect.insetBy(dx: -tolerance, dy: -tolerance)
        guard outer.contains(point) else { return false }
        switch kind {
        case .rectangle:
            return true
        case .ellipse:
            let local = CGPoint(x: point.x - globalRect.minX, y: point.y - globalRect.minY)
            let nx = (local.x - globalRect.width / 2) / max(globalRect.width / 2 + tolerance, 0.5)
            let ny = (local.y - globalRect.height / 2) / max(globalRect.height / 2 + tolerance, 0.5)
            return nx * nx + ny * ny <= 1
        }
    }

    func hitTestArrowEndpoint(at point: CGPoint, annotation: Annotation) -> ArrowEndpoint? {
        guard case .arrow(let start, let end, _, _) = annotation.payload else { return nil }
        let size = handleHitSize
        let startGlobal = toGlobal(CGRect(origin: start, size: .zero))
        let endGlobal = toGlobal(CGRect(origin: end, size: .zero))
        let startRect = CGRect(
            x: startGlobal.minX - size / 2,
            y: startGlobal.minY - size / 2,
            width: size,
            height: size
        )
        let endRect = CGRect(
            x: endGlobal.minX - size / 2,
            y: endGlobal.minY - size / 2,
            width: size,
            height: size
        )
        if startRect.contains(point) { return .start }
        if endRect.contains(point) { return .end }
        return nil
    }

    /// `localPoint` is relative to the ellipse bounding rect's origin.
    func isOnEllipseRing(size: CGSize, localPoint: CGPoint, tolerance: CGFloat) -> Bool {
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else { return false }

        let cx = w / 2
        let cy = h / 2
        let dx = localPoint.x - cx
        let dy = localPoint.y - cy

        // Avoid degenerate rings on tiny marks.
        let rxOuter = max(w / 2 + tolerance, 1)
        let ryOuter = max(h / 2 + tolerance, 1)
        let rxInner = max(w / 2 - tolerance, 0.5)
        let ryInner = max(h / 2 - tolerance, 0.5)

        let outer = (dx * dx) / (rxOuter * rxOuter) + (dy * dy) / (ryOuter * ryOuter)
        let inner = (dx * dx) / (rxInner * rxInner) + (dy * dy) / (ryInner * ryInner)
        return outer <= 1 && inner >= 1
    }

}
