import AppKit

extension AnnotationCoding {
    static func encodeMarker(id: UUID, geometry: MosaicGeometry, style: MarkerStyle, hull: CGRect) -> MarkDTO {
        let encoded = encodeBrushGeometry(geometry, hull: hull)
        return MarkDTO(
            id: id.uuidString,
            type: "marker",
            kind: encoded.kind,
            rect: encoded.rect,
            points: encoded.points,
            markerStyle: encode(style)
        )
    }

    static func decodeMarker(id: UUID, dto: MarkDTO) -> Annotation? {
        guard let markerDTO = dto.markerStyle else {
            NSLog("SnipHistory: skipping marker mark without markerStyle")
            return nil
        }
        guard let geometry = decodeBrushGeometry(points: dto.points, kind: dto.kind, rect: dto.rect) else {
            NSLog("SnipHistory: skipping marker mark without points or rect")
            return nil
        }
        return Annotation(id: id, payload: .marker(geometry, style: decode(markerDTO)))
    }

    static func encode(_ style: MarkerStyle) -> MarkerStyleDTO {
        MarkerStyleDTO(
            brushWidth: Double(style.brushWidth),
            color: encode(style.color)
        )
    }

    static func decode(_ dto: MarkerStyleDTO) -> MarkerStyle {
        var style = MarkerStyle(
            brushWidth: CGFloat(dto.brushWidth),
            color: decode(dto.color)
        )
        style.clamp()
        return style
    }
}
