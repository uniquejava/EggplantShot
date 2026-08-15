import AppKit

extension AnnotationCoding {
    static func encodeMosaic(id: UUID, geometry: MosaicGeometry, style: MosaicStyle, hull: CGRect) -> MarkDTO {
        let encoded = encodeBrushGeometry(geometry, hull: hull)
        return MarkDTO(
            id: id.uuidString,
            type: "mosaic",
            kind: encoded.kind,
            rect: encoded.rect,
            points: encoded.points,
            mosaicStyle: encode(style)
        )
    }

    static func decodeMosaic(id: UUID, dto: MarkDTO) -> Annotation? {
        guard let mosaicDTO = dto.mosaicStyle else {
            NSLog("SnipHistory: skipping mosaic mark without mosaicStyle")
            return nil
        }
        guard let geometry = decodeBrushGeometry(points: dto.points, kind: dto.kind, rect: dto.rect) else {
            NSLog("SnipHistory: skipping mosaic mark without points or rect")
            return nil
        }
        return Annotation(id: id, payload: .mosaic(geometry, style: decode(mosaicDTO)))
    }

    static func encode(_ style: MosaicStyle) -> MosaicStyleDTO {
        MosaicStyleDTO(
            brushWidth: Double(style.brushWidth),
            intensity: nil,
            blurSigma: Double(style.blurSigma),
            blockSize: Double(style.blockSize),
            brushKind: nil,
            effect: effectString(style.effect)
        )
    }

    /// Physical fields win; a record with only the legacy `intensity` is run back through the curves
    /// that used to derive both quantities at draw time, so an old snip reopens rendering the same.
    static func decode(_ dto: MosaicStyleDTO) -> MosaicStyle {
        let legacy = dto.intensity.map { CGFloat($0) }
        var style = MosaicStyle(
            brushWidth: CGFloat(dto.brushWidth),
            blurSigma: dto.blurSigma.map { CGFloat($0) }
                ?? legacy.map { MosaicStyle.blurSigma(forLegacyIntensity: $0) }
                ?? MosaicStyle.defaultBlurSigma,
            blockSize: dto.blockSize.map { CGFloat($0) }
                ?? legacy.map { MosaicStyle.blockSize(forLegacyIntensity: $0) }
                ?? MosaicStyle.defaultBlockSize,
            effect: effectFromString(dto.effect)
        )
        style.clamp()
        return style
    }

    static func effectString(_ effect: MosaicEffect) -> String {
        switch effect {
        case .blur: return "blur"
        case .pixelate: return "pixelate"
        }
    }

    /// Unknown / missing → `.blur`, so older records and future values stay loadable.
    static func effectFromString(_ raw: String?) -> MosaicEffect {
        raw == "pixelate" ? .pixelate : .blur
    }
}
