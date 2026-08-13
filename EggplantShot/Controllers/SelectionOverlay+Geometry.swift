import AppKit

// Selection resize / expand geometry.

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
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        }
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
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y

        switch handle {
        case .topLeft:
            minX += dx
            maxY += dy
        case .top:
            maxY += dy
        case .topRight:
            maxX += dx
            maxY += dy
        case .left:
            minX += dx
        case .right:
            maxX += dx
        case .bottomLeft:
            minX += dx
            minY += dy
        case .bottom:
            minY += dy
        case .bottomRight:
            maxX += dx
            minY += dy
        }

        if minX > maxX { swap(&minX, &maxX) }
        if minY > maxY { swap(&minY, &maxY) }

        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if rect.width < floor { rect.size.width = floor }
        if rect.height < floor { rect.size.height = floor }
        return rect
    }

    /// Absolute edge placement for outside-click expand (opposite edges stay on `baseRect`).
    func expandedRect(handle: Handle, baseRect: CGRect, to point: CGPoint, minSize: CGFloat? = nil) -> CGRect {
        let floor = minSize ?? minSelection
        var minX = baseRect.minX
        var maxX = baseRect.maxX
        var minY = baseRect.minY
        var maxY = baseRect.maxY

        switch handle {
        case .topLeft:
            minX = point.x
            maxY = point.y
        case .top:
            maxY = point.y
        case .topRight:
            maxX = point.x
            maxY = point.y
        case .left:
            minX = point.x
        case .right:
            maxX = point.x
        case .bottomLeft:
            minX = point.x
            minY = point.y
        case .bottom:
            minY = point.y
        case .bottomRight:
            maxX = point.x
            minY = point.y
        }

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
        currentRect = r
    }

}
