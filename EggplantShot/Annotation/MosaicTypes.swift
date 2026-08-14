import AppKit

// Shared mosaic / marker / eraser draw modes and mosaic style.

enum MosaicDrawMode: Int, CaseIterable {
    case freehand = 0
    case rectangle = 1
    case ellipse = 2
}

/// Geometry for a mosaic mark (stroke polyline or region rect/oval).
enum MosaicGeometry: Equatable {
    case stroke(points: [CGPoint])
    case region(MosaicDrawMode, rect: CGRect) // `.rectangle` / `.ellipse` only

    func translated(by delta: CGSize) -> MosaicGeometry {
        switch self {
        case .stroke(let points):
            return .stroke(points: points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) })
        case .region(let mode, let rect):
            return .region(mode, rect: rect.offsetBy(dx: delta.width, dy: delta.height))
        }
    }

    /// Axis-aligned bounds; stroke hull is padded by half the brush width.
    func boundingRect(brushWidth: CGFloat) -> CGRect {
        switch self {
        case .stroke(let points):
            let hull = Annotation.bounds(of: points)
            let pad = brushWidth / 2
            return hull.insetBy(dx: -pad, dy: -pad)
        case .region(_, let rect):
            return rect
        }
    }

    /// Maps stroke points (or the region rect) so the padded hull becomes `newBounds`.
    func mapped(from old: CGRect, to newBounds: CGRect, brushWidth: CGFloat) -> MosaicGeometry? {
        switch self {
        case .stroke(let points):
            let pad = brushWidth / 2
            let oldHull = old.insetBy(dx: pad, dy: pad)
            let newHull = newBounds.insetBy(dx: pad, dy: pad)
            guard oldHull.width > 0, oldHull.height > 0 else { return nil }
            let sx = newHull.width / oldHull.width
            let sy = newHull.height / oldHull.height
            let mapped = points.map { p in
                CGPoint(
                    x: newHull.minX + (p.x - oldHull.minX) * sx,
                    y: newHull.minY + (p.y - oldHull.minY) * sy
                )
            }
            return .stroke(points: mapped)
        case .region(let mode, _):
            return .region(mode, rect: newBounds)
        }
    }
}

/// Mosaic stroke style (brush size for freehand + blur intensity). Stored on the mark; prefs mirror last-used.
struct MosaicStyle: Equatable {
    var brushWidth: CGFloat
    /// `CIGaussianBlur` radius (Snipaste intensity); clamped to `intensityRange`.
    var intensity: CGFloat

    static let intensityRange: ClosedRange<CGFloat> = 3...24
    /// Brush diameters in points (≈ cover 14 / 18 / 24 pt glyphs — not Snipaste’s @2x 28/34/42 labels).
    static let brushPresets: [CGFloat] = [14, 18, 24]
    /// Toolbar dot diameters (visual only; distinct sizes, not numbers).
    static let brushPreviewDiameters: [CGFloat] = [4, 6.5, 9]

    static let `default` = MosaicStyle(
        brushWidth: brushPresets[0],
        intensity: 10
    )

    mutating func clamp() {
        intensity = min(max(intensity, Self.intensityRange.lowerBound), Self.intensityRange.upperBound)
        brushWidth = Self.nearestBrushPreset(brushWidth)
    }

    static func nearestBrushPreset(_ width: CGFloat) -> CGFloat {
        brushPresets.min(by: { abs($0 - width) < abs($1 - width) }) ?? brushPresets[0]
    }

    static func clampedIntensity(_ value: CGFloat) -> CGFloat {
        min(max(value, intensityRange.lowerBound), intensityRange.upperBound)
    }

    /// Maps intensity 3…24 → gaussian **sigma** in points (linear, like Photoshop's radius field).
    ///
    /// `CIGaussianBlur.inputRadius` is sigma, so a thin stroke smears over roughly ±2…3 sigma.
    /// The old 0.7…14 range ignored that: the default sigma of ~5 pt turned a 2 pt pencil line
    /// into a ~15 pt blob (≈6–8× thicker), and everything above intensity ~6 bloomed past the
    /// brush and got clipped to it — so half the slider did nothing except make the smear
    /// brush-width-shaped, and perceived thickness tracked the brush instead of the intensity.
    ///
    /// 0.8…3.2 pt keeps the spread inside every brush preset, so intensity means the same thing at
    /// 14 pt and 24 pt. Measured on a 2 pt stroke: 1.7× at minimum, ≈2.8× at the default, ≈5× at
    /// maximum. Fine detail is already gone by ~1.5 pt, so the default obscures more than the old
    /// one needed to while looking far less bloated. Radius stays absolute rather than scaling with
    /// the brush, matching Photoshop's blur tool.
    ///
    /// Note this is **not** security-grade redaction at any setting — blurred text is recoverable
    /// (Hill et al., PoPETs 2016). Solid fill is the only safe way to hide sensitive content.
    static func blurRadiusPoints(forIntensity intensity: CGFloat) -> CGFloat {
        let t = (clampedIntensity(intensity) - intensityRange.lowerBound)
            / (intensityRange.upperBound - intensityRange.lowerBound)
        return 0.8 + t * 2.4 // ≈ 0.8 … 3.2
    }
}
