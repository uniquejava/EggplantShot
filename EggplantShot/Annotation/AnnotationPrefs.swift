import AppKit

// Persisted last-used styles for shape / arrow / mosaic / marker / eraser.

enum AnnotationPrefs {
    private static let strokeWidthKey = "annotate.strokeWidth"
    private static let isFilledKey = "annotate.isFilled"
    private static let lineStyleKey = "annotate.lineStyle"
    private static let paletteKey = "annotate.palette"
    private static let kindKey = "annotate.kind"
    private static let arrowStartCapKey = "annotate.arrow.startCap"
    private static let arrowEndCapKey = "annotate.arrow.endCap"
    private static let mosaicBrushWidthKey = "annotate.mosaic.brushWidth"
    private static let mosaicDrawModeKey = "annotate.mosaic.drawMode"
    private static let mosaicIntensityKey = "annotate.mosaic.intensity"
    /// Legacy tip-shape key; migrated into `mosaicDrawModeKey`.
    private static let mosaicBrushKindKey = "annotate.mosaic.brushKind"

    static func load() -> (style: AnnotationStyle, kind: ShapeKind) {
        let defaults = UserDefaults.standard
        var style = AnnotationStyle.default
        if defaults.object(forKey: strokeWidthKey) != nil {
            style.strokeWidth = CGFloat(defaults.double(forKey: strokeWidthKey))
        }
        style.isFilled = defaults.bool(forKey: isFilledKey)
        if defaults.object(forKey: lineStyleKey) != nil,
           let line = StrokeLineStyle(rawValue: defaults.integer(forKey: lineStyleKey)) {
            style.lineStyle = line
        }
        if defaults.object(forKey: paletteKey) != nil,
           let swatch = PaletteColor(rawValue: defaults.integer(forKey: paletteKey)) {
            style.strokeColor = swatch.color
        }
        let kind: ShapeKind = defaults.integer(forKey: kindKey) == 1 ? .ellipse : .rectangle
        return (style, kind)
    }

    static func loadArrowCaps() -> ArrowCaps {
        let defaults = UserDefaults.standard
        let start = ArrowCapStyle(rawValue: defaults.integer(forKey: arrowStartCapKey)) ?? .none
        let end: ArrowCapStyle
        if defaults.object(forKey: arrowEndCapKey) != nil {
            end = ArrowCapStyle(rawValue: defaults.integer(forKey: arrowEndCapKey)) ?? .openArrow
        } else {
            end = .openArrow
        }
        return ArrowCaps(start: start, end: end)
    }

    static func save(style: AnnotationStyle, kind: ShapeKind) {
        let defaults = UserDefaults.standard
        defaults.set(Double(style.strokeWidth), forKey: strokeWidthKey)
        defaults.set(style.isFilled, forKey: isFilledKey)
        defaults.set(style.lineStyle.rawValue, forKey: lineStyleKey)
        defaults.set(PaletteColor.matching(style.strokeColor).rawValue, forKey: paletteKey)
        defaults.set(kind == .ellipse ? 1 : 0, forKey: kindKey)
    }

    static func saveArrowCaps(_ caps: ArrowCaps) {
        let defaults = UserDefaults.standard
        defaults.set(caps.start.rawValue, forKey: arrowStartCapKey)
        defaults.set(caps.end.rawValue, forKey: arrowEndCapKey)
    }

    static func loadMosaicStyle() -> MosaicStyle {
        let defaults = UserDefaults.standard
        var style = MosaicStyle.default
        if defaults.object(forKey: mosaicBrushWidthKey) != nil {
            style.brushWidth = MosaicStyle.nearestBrushPreset(
                CGFloat(defaults.double(forKey: mosaicBrushWidthKey))
            )
        }
        if defaults.object(forKey: mosaicIntensityKey) != nil {
            style.intensity = MosaicStyle.clampedIntensity(
                CGFloat(defaults.double(forKey: mosaicIntensityKey))
            )
        }
        return style
    }

    static func loadMosaicDrawMode() -> MosaicDrawMode {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: mosaicDrawModeKey) != nil {
            return MosaicDrawMode(rawValue: defaults.integer(forKey: mosaicDrawModeKey)) ?? .rectangle
        }
        // One-shot migrate old tip-shape prefs, then drop the legacy key.
        if defaults.object(forKey: mosaicBrushKindKey) != nil {
            let mode: MosaicDrawMode
            switch defaults.integer(forKey: mosaicBrushKindKey) {
            case 1: mode = .ellipse
            default: mode = .rectangle
            }
            defaults.removeObject(forKey: mosaicBrushKindKey)
            defaults.set(mode.rawValue, forKey: mosaicDrawModeKey)
            return mode
        }
        return .rectangle
    }

    static func saveMosaicStyle(_ style: MosaicStyle) {
        var clamped = style
        clamped.clamp()
        let defaults = UserDefaults.standard
        defaults.set(Double(clamped.brushWidth), forKey: mosaicBrushWidthKey)
        defaults.set(Double(clamped.intensity), forKey: mosaicIntensityKey)
    }

    static func saveMosaicDrawMode(_ mode: MosaicDrawMode) {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: mosaicDrawModeKey)
        defaults.removeObject(forKey: mosaicBrushKindKey)
    }

    private static let markerBrushWidthKey = "annotate.marker.brushWidth"
    private static let markerDrawModeKey = "annotate.marker.drawMode"
    private static let markerColorKey = "annotate.marker.color"
    private static let eraserBrushWidthKey = "annotate.eraser.brushWidth"
    private static let eraserDrawModeKey = "annotate.eraser.drawMode"

    static func loadMarkerStyle() -> MarkerStyle {
        let defaults = UserDefaults.standard
        var style = MarkerStyle.default
        if defaults.object(forKey: markerBrushWidthKey) != nil {
            style.brushWidth = MarkerStyle.nearestBrushPreset(
                CGFloat(defaults.double(forKey: markerBrushWidthKey))
            )
        }
        if defaults.object(forKey: markerColorKey) != nil,
           let swatch = PaletteColor(rawValue: defaults.integer(forKey: markerColorKey)) {
            style.color = swatch.color
        }
        return style
    }

    static func loadMarkerDrawMode() -> MosaicDrawMode {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: markerDrawModeKey) != nil {
            return MosaicDrawMode(rawValue: defaults.integer(forKey: markerDrawModeKey)) ?? .rectangle
        }
        return .rectangle
    }

    static func saveMarkerStyle(_ style: MarkerStyle) {
        var clamped = style
        clamped.clamp()
        let defaults = UserDefaults.standard
        defaults.set(Double(clamped.brushWidth), forKey: markerBrushWidthKey)
        defaults.set(PaletteColor.matching(clamped.color).rawValue, forKey: markerColorKey)
    }

    static func saveMarkerDrawMode(_ mode: MosaicDrawMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: markerDrawModeKey)
    }

    static func loadEraserStyle() -> EraserStyle {
        let defaults = UserDefaults.standard
        var style = EraserStyle.default
        if defaults.object(forKey: eraserBrushWidthKey) != nil {
            style.brushWidth = EraserStyle.nearestBrushPreset(
                CGFloat(defaults.double(forKey: eraserBrushWidthKey))
            )
        }
        return style
    }

    static func loadEraserDrawMode() -> MosaicDrawMode {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: eraserDrawModeKey) != nil {
            return MosaicDrawMode(rawValue: defaults.integer(forKey: eraserDrawModeKey)) ?? .rectangle
        }
        return .rectangle
    }

    static func saveEraserStyle(_ style: EraserStyle) {
        var clamped = style
        clamped.clamp()
        UserDefaults.standard.set(Double(clamped.brushWidth), forKey: eraserBrushWidthKey)
    }

    static func saveEraserDrawMode(_ mode: MosaicDrawMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: eraserDrawModeKey)
    }
}

/// Border outline pattern for stroke shapes (Snipaste 5 styles).
