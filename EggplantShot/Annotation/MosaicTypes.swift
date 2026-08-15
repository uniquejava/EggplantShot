import AppKit

// Shared mosaic / marker / eraser draw modes and mosaic style.

enum MosaicDrawMode: Int, CaseIterable {
    case freehand = 0
    case rectangle = 1
    case ellipse = 2
}

/// What a mosaic mark does to the pixels under it. Geometry, brushes and sampling are shared;
/// only the Core Image filter differs, which is why both live on the one Mosaic tool.
enum MosaicEffect: Int, CaseIterable {
    /// Gaussian smear (`CIGaussianBlur`) — soft blur brush.
    case blur = 0
    /// Coarse colour squares (`CIPixellate`) — the block mosaic people mean by “mosaic”.
    case pixelate = 1
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

/// Mosaic stroke style (brush size for freehand + effect and its strength). Stored on the mark;
/// prefs mirror last-used.
///
/// Strength is stored as the **actual filter parameter**, one per effect, rather than as an abstract
/// "intensity" mapped through a curve. Snipaste's single 3…24 scale was inherited early and fits
/// neither effect: 21 integer steps across sigma 0.8…3.2 pt is 0.114 pt (≈¼ device pixel) per step,
/// so most adjacent settings were indistinguishable, and the number itself said nothing. Naming the
/// quantity fixes both — the label reads what the filter will do, and each effect keeps its own
/// value, so switching modes no longer clobbers the other one's setting.
struct MosaicStyle: Equatable {
    var brushWidth: CGFloat
    /// `CIGaussianBlur` sigma in points, used when `effect` is `.blur`.
    var blurSigma: CGFloat = MosaicStyle.defaultBlurSigma
    /// `CIPixellate` block edge in points, used when `effect` is `.pixelate`.
    var blockSize: CGFloat = MosaicStyle.defaultBlockSize
    /// Blur smear or pixel blocks. Defaults to `.blur`: the mode that shipped first, and what
    /// records written before pixelate existed decode to.
    var effect: MosaicEffect = .blur

    /// Gaussian sigma bounds, in points.
    ///
    /// `CIGaussianBlur.inputRadius` is sigma, so a thin stroke smears over roughly ±2…3 sigma —
    /// sigma has to stay small or a pencil line turns into a blob. An earlier 0.7…14 pt range
    /// ignored that: a default of ~5 pt turned a 2 pt line into a ~15 pt blob (≈6–8× thicker), and
    /// anything past ~3 pt bloomed beyond the brush and got clipped to it, so perceived thickness
    /// tracked the brush width instead of the setting. 0.8…3.2 keeps the spread inside every brush
    /// preset, so a value means the same thing at 14 pt and 24 pt — absolute, like Photoshop's blur.
    ///
    /// Measured on a 2 pt stroke: 1.7× thickening at 0.8, ≈2.8× at the 1.6 default, ≈5× at 3.2.
    /// Fine detail is gone by ~1.5 pt, which is why the default sits just past it.
    ///
    /// **Not** security-grade redaction at any setting — blurred text is recoverable
    /// (Hill et al., PoPETs 2016). Solid fill is the only safe way to hide sensitive content.
    static let blurSigmaRange: ClosedRange<CGFloat> = 0.8...3.2
    /// 0.4 pt per step (≈0.8 device px at 2×): 7 stops, every one of them visible. The old scale's
    /// 0.114 pt steps were a quarter of a device pixel.
    static let blurSigmaStep: CGFloat = 0.4
    static let defaultBlurSigma: CGFloat = 1.6

    /// `CIPixellate` block edge bounds, in points — the same quantity Photoshop calls Mosaic "Cell
    /// Size" and ShareX calls "Pixel size", so the number on the row is directly meaningful.
    ///
    /// Absolute rather than scaled by brush width, matching blur. That brings the mirror image of
    /// blur bloom: blocks *larger* than the brush can't tile it, so a stroke under ~3 blocks wide
    /// reads as a flat smudge instead of a mosaic. Drawing wider or switching to region mode is the
    /// fix; clamping the block to the brush would make one value mean different things per brush.
    ///
    /// 2 pt is a light texture; the 6 pt default is chunky on a region, ~2 blocks across the 14 pt
    /// brush, and past what body text survives; 16 pt buries a face in a large region.
    ///
    /// Like blur, **not** security-grade redaction: pixelated text is recoverable too
    /// (Hill et al., PoPETs 2016).
    static let blockSizeRange: ClosedRange<CGFloat> = 2...16
    /// Whole points: 15 stops, each ≈1.3 device px at 2×.
    static let blockSizeStep: CGFloat = 1
    static let defaultBlockSize: CGFloat = 6

    /// Brush diameters in points (≈ cover 14 / 18 / 24 pt glyphs — not Snipaste’s @2x 28/34/42 labels).
    static let brushPresets: [CGFloat] = [14, 18, 24]
    /// Toolbar dot diameters (visual only; distinct sizes, not numbers).
    static let brushPreviewDiameters: [CGFloat] = [4, 6.5, 9]

    static let `default` = MosaicStyle(brushWidth: brushPresets[0])

    /// The strength that `effect` actually reads, and its slider configuration.
    var strength: CGFloat {
        get { effect == .blur ? blurSigma : blockSize }
        set {
            switch effect {
            case .blur: blurSigma = Self.snappedBlurSigma(newValue)
            case .pixelate: blockSize = Self.snappedBlockSize(newValue)
            }
        }
    }

    static func strengthRange(for effect: MosaicEffect) -> ClosedRange<CGFloat> {
        effect == .blur ? blurSigmaRange : blockSizeRange
    }

    static func strengthStep(for effect: MosaicEffect) -> CGFloat {
        effect == .blur ? blurSigmaStep : blockSizeStep
    }

    /// Sigma carries a decimal; a block edge is a whole number of points. Rounds for display rather
    /// than snapping, so a legacy value between steps reads as its nearest label instead of jumping.
    static func formatStrength(_ value: CGFloat, effect: MosaicEffect) -> String {
        switch effect {
        case .blur: return String(format: "%.1f", clampedBlurSigma(value))
        case .pixelate: return "\(Int(clampedBlockSize(value).rounded()))"
        }
    }

    /// Range-clamps only — deliberately **not** snapped to the step grid. Snapping is a slider
    /// concern (see `strength` and `MosaicIntensitySlider.step`); applying it here would nudge
    /// legacy values derived from `intensity` by up to half a step and re-render saved snips.
    mutating func clamp() {
        brushWidth = Self.nearestBrushPreset(brushWidth)
        blurSigma = Self.clampedBlurSigma(blurSigma)
        blockSize = Self.clampedBlockSize(blockSize)
    }

    static func nearestBrushPreset(_ width: CGFloat) -> CGFloat {
        brushPresets.min(by: { abs($0 - width) < abs($1 - width) }) ?? brushPresets[0]
    }

    static func clampedBlurSigma(_ value: CGFloat) -> CGFloat {
        min(max(value, blurSigmaRange.lowerBound), blurSigmaRange.upperBound)
    }

    static func clampedBlockSize(_ value: CGFloat) -> CGFloat {
        min(max(value, blockSizeRange.lowerBound), blockSizeRange.upperBound)
    }

    static func snappedBlurSigma(_ value: CGFloat) -> CGFloat {
        snap(value, to: blurSigmaStep, within: blurSigmaRange)
    }

    static func snappedBlockSize(_ value: CGFloat) -> CGFloat {
        snap(value, to: blockSizeStep, within: blockSizeRange)
    }

    /// Snapped onto the step grid *measured from the lower bound*, so the bounds are always
    /// reachable and the label never shows a value the slider can't return to.
    private static func snap(
        _ value: CGFloat, to step: CGFloat, within range: ClosedRange<CGFloat>
    ) -> CGFloat {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard step > 0 else { return clamped }
        let steps = ((clamped - range.lowerBound) / step).rounded()
        return min(range.lowerBound + steps * step, range.upperBound)
    }

    // MARK: - Legacy decode

    /// Records written before the physical fields stored an abstract `intensity` in 3…24 and derived
    /// both quantities from it at draw time. These reproduce those two curves exactly, so reopening
    /// an old snip renders identically rather than shifting by a quantization step.
    static let legacyIntensityRange: ClosedRange<CGFloat> = 3...24

    static func blurSigma(forLegacyIntensity intensity: CGFloat) -> CGFloat {
        0.8 + legacyFraction(intensity) * 2.4 // ≈ 0.8 … 3.2
    }

    static func blockSize(forLegacyIntensity intensity: CGFloat) -> CGFloat {
        2 + legacyFraction(intensity) * 14 // ≈ 2 … 16
    }

    private static func legacyFraction(_ intensity: CGFloat) -> CGFloat {
        let clamped = min(
            max(intensity, legacyIntensityRange.lowerBound), legacyIntensityRange.upperBound)
        return (clamped - legacyIntensityRange.lowerBound)
            / (legacyIntensityRange.upperBound - legacyIntensityRange.lowerBound)
    }
}
