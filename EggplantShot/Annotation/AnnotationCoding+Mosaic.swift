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
            intensity: Double(style.intensity),
            brushKind: nil,
            effect: effectString(style.effect)
        )
    }

    static func decode(_ dto: MosaicStyleDTO) -> MosaicStyle {
        var style = MosaicStyle(
            brushWidth: CGFloat(dto.brushWidth),
            intensity: CGFloat(dto.intensity),
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
