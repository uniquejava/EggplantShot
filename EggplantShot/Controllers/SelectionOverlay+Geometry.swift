import AppKit

// Selection resize / expand geometry.

extension SelectionOverlayController.Handle {
    /// Which rect edge this handle drives on each axis; `.mid` means the axis is not driven.
    /// Single source for `handleCenter` / `resizedRect` / `resizedRectKeepingAspect` / `expandedRect` —
    /// the aspect-locked resize pivots on `opposite`. Coordinates are y-up, so `.top` is y `.max`.
    var drivenEdges: (x: RectEdgeAnchor, y: RectEdgeAnchor) {
        switch self {
        case .topLeft: return (.min, .max)
        case .top: return (.mid, .max)
        case .topRight: return (.max, .max)
        case .left: return (.min, .mid)
        case .right: return (.max, .mid)
        case .bottomLeft: return (.min, .min)
        case .bottom: return (.mid, .min)
        case .bottomRight: return (.max, .min)
        }
    }
}

@MainActor
extension SelectionOverlayController {
    // MARK: - Geometry

    /// Snipaste-style zones: deep interior → `nil` (move); border strip → resize handle.
    /// When `allowOutsideExpand` is true, the whole outside octant map also returns a handle
    /// (click-outside expand). When false (annotate tool armed), only the border band hits.
    func refineResizeHandle(at point: CGPoint, allowOutsideExpand: Bool) -> Handle? {
        guard !currentRect.isNull, currentRect.width > 0, currentRect.height > 0 else { return nil }
        let r = currentRect
        let t = selectionEdgeHit

        let inner = r.insetBy(dx: t, dy: t)
        if inner.width > 0, inner.height > 0, inner.contains(point) {
            return nil
        }

        if !allowOutsideExpand {
            // Keep a thin outward slop so circular handles remain grabable; reject far outside.
            let outer = r.insetBy(dx: -t, dy: -t)
            guard outer.contains(point) else { return nil }
        }

        let onLeft = point.x < r.minX + t
        let onRight = point.x > r.maxX - t
        let onBottom = point.y < r.minY + t
        let onTop = point.y > r.maxY - t

        if onTop && onLeft { return .topLeft }
        if onTop && onRight { return .topRight }
        if onBottom && onLeft { return .bottomLeft }
        if onBottom && onRight { return .bottomRight }
        if onTop { return .top }
        if onBottom { return .bottom }
        if onLeft { return .left }
        if onRight { return .right }
        return nil
    }

    func handleCenter(_ handle: Handle, in rect: CGRect) -> CGPoint {
        let edges = handle.drivenEdges
        return CGPoint(
            x: edges.x.coordinate(min: rect.minX, max: rect.maxX),
            y: edges.y.coordinate(min: rect.minY, max: rect.maxY)
        )
    }

    func handleHitRect(_ handle: Handle, in rect: CGRect) -> CGRect {
        let c = handleCenter(handle, in: rect)
        return CGRect(
            x: c.x - handleHitSize / 2,
            y: c.y - handleHitSize / 2,
            width: handleHitSize,
            height: handleHitSize
        )
    }

    func resizedRect(
        handle: Handle,
        startRect: CGRect,
        startPoint: CGPoint,
        point: CGPoint,
        minSize: CGFloat? = nil
    ) -> CGRect {
        let floor = minSize ?? minSelection
        var minX = startRect.minX
        var maxX = startRect.maxX
        var minY = startRect.minY
        var maxY = startRect.maxY

        let edges = handle.drivenEdges
        edges.x.shift(min: &minX, max: &maxX, by: point.x - startPoint.x)
        edges.y.shift(min: &minY, max: &maxY, by: point.y - startPoint.y)

        if minX > maxX { swap(&minX, &maxX) }
        if minY > maxY { swap(&minY, &maxY) }

        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if rect.width < floor { rect.size.width = floor }
        if rect.height < floor { rect.size.height = floor }
        return rect
    }

    /// Resize while keeping `startRect`'s aspect (text marks — font is a single scalar).
    func resizedRectKeepingAspect(
        handle: Handle,
        startRect: CGRect,
        startPoint: CGPoint,
        point: CGPoint,
        minSize: CGFloat? = nil
    ) -> CGRect {
        let floor = minSize ?? minSelection
        let aspect = max(startRect.width / max(startRect.height, 0.001), 0.001)
        let free = resizedRect(
            handle: handle,
            startRect: startRect,
            startPoint: startPoint,
            point: point,
            minSize: floor
        )
        let scaleW = free.width / max(startRect.width, 0.001)
        let scaleH = free.height / max(startRect.height, 0.001)
        let edges = handle.drivenEdges
        let scale: CGFloat
        if edges.y == .mid {
            scale = scaleW  // side handle — width leads
        } else if edges.x == .mid {
            scale = scaleH  // top / bottom handle — height leads
        } else {
            // Corner: project the dragged corner onto the anchor→corner diagonal.
            //
            // Picking whichever axis deviated more (`abs(scaleW - 1) >= abs(scaleH - 1)`) is
            // *discontinuous*: drag a corner so one axis grows while the other shrinks and the two
            // deviations cross, flipping the winner between values on opposite sides of 1. On a
            // 200×100 box that swung the width 240 → 156 (fontSize 48 → 31) for 2 pt of mouse
            // movement. A projection is continuous and monotonic along the drag.
            let anchorX = edges.x.opposite.coordinate(min: startRect.minX, max: startRect.maxX)
            let anchorY = edges.y.opposite.coordinate(min: startRect.minY, max: startRect.maxY)
            let cornerX = edges.x.coordinate(min: startRect.minX, max: startRect.maxX)
            let cornerY = edges.y.coordinate(min: startRect.minY, max: startRect.maxY)
            let baseX = cornerX - anchorX
            let baseY = cornerY - anchorY
            let dragX = baseX + (point.x - startPoint.x)
            let dragY = baseY + (point.y - startPoint.y)
            let baseLengthSquared = baseX * baseX + baseY * baseY
            scale = baseLengthSquared > 0.0001
                ? (dragX * baseX + dragY * baseY) / baseLengthSquared
                : scaleW
        }
        var width = max(floor, startRect.width * scale)
        var height = width / aspect
        if height < floor {
            height = floor
            width = height * aspect
        }

        // Pivot on the edges the handle does not drive, so those stay put.
        return Annotation.placed(
            size: CGSize(width: width, height: height),
            in: startRect,
            anchorX: edges.x.opposite,
            anchorY: edges.y.opposite
        )
    }

    /// Absolute edge placement for outside-click expand (opposite edges stay on `baseRect`).
    func expandedRect(handle: Handle, baseRect: CGRect, to point: CGPoint, minSize: CGFloat? = nil) -> CGRect {
        let floor = minSize ?? minSelection
        var minX = baseRect.minX
        var maxX = baseRect.maxX
        var minY = baseRect.minY
        var maxY = baseRect.maxY

        let edges = handle.drivenEdges
        edges.x.snap(min: &minX, max: &maxX, to: point.x)
        edges.y.snap(min: &minY, max: &maxY, to: point.y)

        if minX > maxX { swap(&minX, &maxX) }
        if minY > maxY { swap(&minY, &maxY) }

        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if rect.width < floor { rect.size.width = floor }
        if rect.height < floor { rect.size.height = floor }
        return rect
    }

    func clampRectToScreens() {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.intersects(currentRect)
        }) ?? NSScreen.main else { return }

        var r = currentRect
        // If the restored rect is larger than the screen, shrink to fit while keeping aspect.
        if r.width > screen.frame.width {
            r.size.width = screen.frame.width
        }
        if r.height > screen.frame.height {
            r.size.height = screen.frame.height
        }
        r.origin.x = min(max(r.origin.x, screen.frame.minX), screen.frame.maxX - r.width)
        r.origin.y = min(max(r.origin.y, screen.frame.minY), screen.frame.maxY - r.height)
        setSelectionRect(r)
    }

}
