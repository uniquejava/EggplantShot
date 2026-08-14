import AppKit

// Annotation draft create / update / delete.

@MainActor
extension SelectionOverlayController {
    // MARK: - Annotation helpers

    func toLocal(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - currentRect.minX, y: global.y - currentRect.minY)
    }

    func toLocal(_ global: CGRect) -> CGRect {
        CGRect(
            x: global.origin.x - currentRect.minX,
            y: global.origin.y - currentRect.minY,
            width: global.width,
            height: global.height
        )
    }

    func toGlobal(_ local: CGRect) -> CGRect {
        local.offsetBy(dx: currentRect.minX, dy: currentRect.minY)
    }

    /// Assigns `currentRect`, rebasing selection-local marks so they stay fixed on the freeze
    /// when the selection origin moves (crop move / resize / expand / clamp).
    func setSelectionRect(_ newRect: CGRect) {
        let old = currentRect
        currentRect = newRect
        guard !old.isNull, !newRect.isNull else { return }
        let delta = CGSize(width: old.minX - newRect.minX, height: old.minY - newRect.minY)
        annotationHistory.rebaseForSelectionOriginDelta(delta)
    }

    func clampLocal(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(p.x, 0), currentRect.width),
            y: min(max(p.y, 0), currentRect.height)
        )
    }

    func clampAnnotationRect(_ rect: CGRect) -> CGRect {
        var r = rect
        r.size.width = max(r.width, minAnnotation)
        r.size.height = max(r.height, minAnnotation)
        r.origin.x = min(max(r.origin.x, 0), max(0, currentRect.width - r.width))
        r.origin.y = min(max(r.origin.y, 0), max(0, currentRect.height - r.height))
        if r.maxX > currentRect.width { r.size.width = currentRect.width - r.origin.x }
        if r.maxY > currentRect.height { r.size.height = currentRect.height - r.origin.y }
        return r
    }

    /// Marks may live outside the blue selection (fullscreen annotate). No clamp.
    func clampAnnotationInSelection(_ annotation: inout Annotation) {
        _ = annotation
    }

    /// Axis-aligned square / circle bounding box from drag start toward `toward`.
    func constrainedSquare(from start: CGPoint, toward end: CGPoint) -> CGRect {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        let ox = dx < 0 ? -side : 0
        let oy = dy < 0 ? -side : 0
        return CGRect(x: start.x + ox, y: start.y + oy, width: side, height: side)
    }

    func syncToolbar(from annotation: Annotation) {
        if annotation.isText {
            textStyle = annotation.textStyle
            toolbar?.syncTextStyle(textStyle)
            return
        }
        if annotation.isStep {
            stepStyle = annotation.stepStyle
            toolbar?.syncStepStyle(stepStyle)
            return
        }
        if annotation.isMagnifier {
            magnifierStyle = annotation.magnifierStyle
            magnifierKind = annotation.magnifierKind
            toolbar?.syncMagnifier(kind: magnifierKind, style: magnifierStyle)
            return
        }
        if annotation.isMosaic {
            mosaicStyle = annotation.mosaicStyle
            if case .region(let mode, _) = annotation.mosaicGeometry {
                mosaicDrawMode = mode
            } else {
                mosaicDrawMode = .freehand
            }
            toolbar?.syncMosaicStyle(mosaicStyle)
            toolbar?.syncMosaicDrawMode(mosaicDrawMode)
            return
        }
        if annotation.isMarker {
            markerStyle = annotation.markerStyle
            if case .region(let mode, _) = annotation.markerGeometry {
                markerDrawMode = mode
            } else {
                markerDrawMode = .freehand
            }
            toolbar?.syncMarkerStyle(markerStyle)
            toolbar?.syncMarkerDrawMode(markerDrawMode)
            return
        }
        if annotation.isEraser {
            eraserStyle = annotation.eraserStyle
            if case .region(let mode, _) = annotation.eraserGeometry {
                eraserDrawMode = mode
            } else {
                eraserDrawMode = .freehand
            }
            toolbar?.syncEraserStyle(eraserStyle)
            toolbar?.syncEraserDrawMode(eraserDrawMode)
            return
        }
        annotationStyle = annotation.style
        if annotation.isShape {
            annotationKind = annotation.kind
        }
        if annotation.isArrow {
            arrowCaps = annotation.arrowCaps
        }
        toolbar?.syncStyle(annotation.style, kind: annotationKind, arrowCaps: arrowCaps)
    }

    func makeDraftAnnotation(startingAt local: CGPoint) -> Annotation {
        switch annotateTool {
        case .pencil:
            var style = annotationStyle
            style.isFilled = false
            return Annotation(points: [local], style: style)
        case .mosaic:
            switch mosaicDrawMode {
            case .freehand:
                return Annotation(mosaicPoints: [local], mosaicStyle: mosaicStyle)
            case .rectangle, .ellipse:
                return Annotation(
                    mosaicRegion: mosaicDrawMode,
                    rect: CGRect(origin: local, size: .zero),
                    mosaicStyle: mosaicStyle
                )
            }
        case .marker:
            switch markerDrawMode {
            case .freehand:
                return Annotation(markerPoints: [local], markerStyle: markerStyle)
            case .rectangle, .ellipse:
                return Annotation(
                    markerRegion: markerDrawMode,
                    rect: CGRect(origin: local, size: .zero),
                    markerStyle: markerStyle
                )
            }
        case .eraser:
            switch eraserDrawMode {
            case .freehand:
                return Annotation(eraserPoints: [local], eraserStyle: eraserStyle)
            case .rectangle, .ellipse:
                return Annotation(
                    eraserRegion: eraserDrawMode,
                    rect: CGRect(origin: local, size: .zero),
                    eraserStyle: eraserStyle
                )
            }
        case .arrow:
            var style = annotationStyle
            style.isFilled = false
            return Annotation(start: local, end: local, style: style, caps: arrowCaps)
        case .text:
            let rect = Annotation.fittedTextRect(
                string: "",
                style: textStyle,
                origin: local,
                anchor: .leadingMidY
            )
            return Annotation(string: "", rect: rect, style: textStyle)
        case .step:
            return Annotation(number: nextStepNumber(), center: local, stepStyle: stepStyle)
        case .magnifier:
            let source = CGRect(origin: local, size: .zero)
            // Lens appears on mouse-up only (avoids live concentric zoom while dragging).
            return Annotation(
                magnifierKind: magnifierKind,
                source: source,
                lens: .zero,
                magnifierStyle: magnifierStyle
            )
        case .rectangle, .none:
            return Annotation(
                kind: annotationKind,
                rect: CGRect(origin: local, size: .zero),
                style: annotationStyle
            )
        }
    }

    func appendPencilOrShapeDraft(startLocal: CGPoint, globalPoint: CGPoint) {
        // Selection-local, may extend outside the blue rect.
        let end = toLocal(globalPoint)
        draftAnnotation = updatedDraft(from: startLocal, to: end)
        updateHighlight(showHandles: true)
    }

    func updatedDraft(from start: CGPoint, to end: CGPoint) -> Annotation {
        switch annotateTool {
        case .pencil:
            var style = annotationStyle
            style.isFilled = false
            if NSEvent.modifierFlags.contains(.shift) {
                // Straight line at any angle (start → tip); no 45° quantization.
                return Annotation(points: [start, end], style: style)
            }
            // Append on mouse-drag (~2pt spacing) — not sub-pixel / high-Hz.
            var points = draftAnnotation?.points ?? [start]
            if points.isEmpty { points = [start] }
            if let last = points.last {
                let distance = hypot(end.x - last.x, end.y - last.y)
                if distance >= pencilSampleSpacing {
                    points.append(end)
                }
            } else {
                points.append(end)
            }
            return Annotation(points: points, style: style)

        case .mosaic:
            switch mosaicDrawMode {
            case .freehand:
                if NSEvent.modifierFlags.contains(.shift) {
                    return Annotation(mosaicPoints: [start, end], mosaicStyle: mosaicStyle)
                }
                var points = draftAnnotation?.points ?? [start]
                if points.isEmpty { points = [start] }
                if let last = points.last {
                    let distance = hypot(end.x - last.x, end.y - last.y)
                    if distance >= pencilSampleSpacing {
                        points.append(end)
                    }
                } else {
                    points.append(end)
                }
                return Annotation(mosaicPoints: points, mosaicStyle: mosaicStyle)

            case .rectangle, .ellipse:
                var draft = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                if NSEvent.modifierFlags.contains(.shift) {
                    draft = constrainedSquare(from: start, toward: end)
                }
                return Annotation(
                    mosaicRegion: mosaicDrawMode,
                    rect: draft,
                    mosaicStyle: mosaicStyle
                )
            }

        case .marker:
            switch markerDrawMode {
            case .freehand:
                if NSEvent.modifierFlags.contains(.shift) {
                    return Annotation(markerPoints: [start, end], markerStyle: markerStyle)
                }
                var points = draftAnnotation?.points ?? [start]
                if points.isEmpty { points = [start] }
                if let last = points.last {
                    let distance = hypot(end.x - last.x, end.y - last.y)
                    if distance >= pencilSampleSpacing {
                        points.append(end)
                    }
                } else {
                    points.append(end)
                }
                return Annotation(markerPoints: points, markerStyle: markerStyle)

            case .rectangle, .ellipse:
                var draft = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                if NSEvent.modifierFlags.contains(.shift) {
                    draft = constrainedSquare(from: start, toward: end)
                }
                return Annotation(
                    markerRegion: markerDrawMode,
                    rect: draft,
                    markerStyle: markerStyle
                )
            }

        case .eraser:
            switch eraserDrawMode {
            case .freehand:
                if NSEvent.modifierFlags.contains(.shift) {
                    return Annotation(eraserPoints: [start, end], eraserStyle: eraserStyle)
                }
                var points = draftAnnotation?.points ?? [start]
                if points.isEmpty { points = [start] }
                if let last = points.last {
                    let distance = hypot(end.x - last.x, end.y - last.y)
                    if distance >= pencilSampleSpacing {
                        points.append(end)
                    }
                } else {
                    points.append(end)
                }
                return Annotation(eraserPoints: points, eraserStyle: eraserStyle)

            case .rectangle, .ellipse:
                var draft = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                if NSEvent.modifierFlags.contains(.shift) {
                    draft = constrainedSquare(from: start, toward: end)
                }
                return Annotation(
                    eraserRegion: eraserDrawMode,
                    rect: draft,
                    eraserStyle: eraserStyle
                )
            }

        case .arrow:
            var style = annotationStyle
            style.isFilled = false
            let tip: CGPoint
            if NSEvent.modifierFlags.contains(.shift) {
                tip = snappedArrowPoint(from: start, toward: end)
            } else {
                tip = end
            }
            return Annotation(start: start, end: tip, style: style, caps: arrowCaps)

        case .text:
            // Text is click-to-place; drag-draw is unused.
            return makeDraftAnnotation(startingAt: start)

        case .step:
            // Step is click-to-place; drag-draw is unused.
            return makeDraftAnnotation(startingAt: start)

        case .magnifier:
            var source = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            if NSEvent.modifierFlags.contains(.shift) {
                source = constrainedSquare(from: start, toward: end)
            }
            // Source-only while dragging; concentric lens is created in `finalizedDraft`.
            return Annotation(
                magnifierKind: magnifierKind,
                source: source,
                lens: .zero,
                magnifierStyle: magnifierStyle
            )

        case .rectangle, .none:
            var draft = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            // Shift → square / circle from the drag start corner.
            if NSEvent.modifierFlags.contains(.shift) {
                draft = constrainedSquare(from: start, toward: end)
            }
            return Annotation(kind: annotationKind, rect: draft, style: annotationStyle)
        }
    }

    func isDraftWorthKeeping(_ draft: Annotation) -> Bool {
        switch draft.payload {
        case .shape(_, let rect, _):
            return rect.width >= minAnnotation && rect.height >= minAnnotation
        case .arrow(let start, let end, _, _):
            return hypot(end.x - start.x, end.y - start.y) >= minAnnotation
        case .pencil(let points, _):
            guard points.count >= 2, let first = points.first, let last = points.last else { return false }
            return hypot(last.x - first.x, last.y - first.y) >= minAnnotation
                || pathLength(points) >= minAnnotation
        case .mosaic(let geometry, _):
            switch geometry {
            case .stroke(let points):
                return !points.isEmpty
            case .region(_, let rect):
                return rect.width >= minAnnotation && rect.height >= minAnnotation
            }
        case .marker(let geometry, _):
            switch geometry {
            case .stroke(let points):
                return !points.isEmpty
            case .region(_, let rect):
                return rect.width >= minAnnotation && rect.height >= minAnnotation
            }
        case .eraser(let geometry, _):
            switch geometry {
            case .stroke(let points):
                return !points.isEmpty
            case .region(_, let rect):
                return rect.width >= minAnnotation && rect.height >= minAnnotation
            }
        case .text, .step:
            return true
        case .magnifier(_, let source, _, _):
            return source.width >= minAnnotation && source.height >= minAnnotation
        }
    }

    func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 0..<(points.count - 1) {
            total += hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
        }
        return total
    }

    func finalizedDraft(_ draft: Annotation) -> Annotation {
        switch draft.payload {
        case .shape(let kind, let rect, let style):
            return Annotation(kind: kind, rect: rect, style: style)
        case .arrow(let start, let end, let style, let caps):
            return Annotation(start: start, end: end, style: style, caps: caps)
        case .pencil(let points, let style):
            // Live: ~2pt on mouse-drag. Commit: RDP so many strokes don’t bloat mosaic re-samples.
            let epsilon = max(style.strokeWidth * 0.15, 0.5)
            return Annotation(points: PolylineSimplifier.simplify(points, epsilon: epsilon), style: style)
        case .mosaic(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                let epsilon = max(style.brushWidth * 0.04, 0.6)
                return Annotation(
                    mosaicPoints: PolylineSimplifier.simplify(points, epsilon: epsilon),
                    mosaicStyle: style
                )
            case .region(let mode, let rect):
                return Annotation(mosaicRegion: mode, rect: rect, mosaicStyle: style)
            }
        case .marker(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                let epsilon = max(style.brushWidth * 0.04, 0.6)
                return Annotation(
                    markerPoints: PolylineSimplifier.simplify(points, epsilon: epsilon),
                    markerStyle: style
                )
            case .region(let mode, let rect):
                return Annotation(markerRegion: mode, rect: rect, markerStyle: style)
            }
        case .eraser(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                let epsilon = max(style.brushWidth * 0.04, 0.6)
                return Annotation(
                    eraserPoints: PolylineSimplifier.simplify(points, epsilon: epsilon),
                    eraserStyle: style
                )
            case .region(let mode, let rect):
                return Annotation(eraserRegion: mode, rect: rect, eraserStyle: style)
            }
        case .text(let string, let rect, let style):
            return Annotation(string: string, rect: rect, style: style)
        case .step(let number, let center, let style):
            return Annotation(number: number, center: center, stepStyle: style)
        case .magnifier(let kind, let source, _, let style):
            return Annotation(
                magnifierKind: kind,
                source: source,
                lens: Annotation.concentricMagnifierLens(for: source, scale: style.scale),
                magnifierStyle: style
            )
        }
    }

    /// Snap `toward` onto the nearest 45° ray from `origin`.
    func snappedArrowPoint(from origin: CGPoint, toward point: CGPoint) -> CGPoint {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let length = hypot(dx, dy)
        guard length > 0.01 else { return point }
        let angle = atan2(dy, dx)
        let step = CGFloat.pi / 4
        let snapped = (angle / step).rounded() * step
        return CGPoint(x: origin.x + cos(snapped) * length, y: origin.y + sin(snapped) * length)
    }

    func updateAnnotation(id: UUID, mutate: (inout Annotation) -> Void) {
        annotationHistory.mutateLive { doc in
            guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
            mutate(&doc.marks[idx])
        }
    }

    func deleteSelectedAnnotation() {
        endTextEditing(commit: false)
        guard let id = selectedAnnotationID else { return }
        annotationHistory.commit { doc in
            doc.marks.removeAll { $0.id == id }
            doc.selectedID = nil
        }
        updateHighlight(showHandles: true)
        refreshHistoryChrome()
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    /// Priority: editing text frame → selected handles → text interior/border → any stroke/border (topmost) → draw.
    /// Annotate tools work fullscreen (Snipaste), not only inside the blue selection.
}
