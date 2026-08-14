import AppKit

extension AnnotationCoding {
    static func encodeEraser(id: UUID, geometry: MosaicGeometry, style: EraserStyle, hull: CGRect) -> MarkDTO {
        let encoded = encodeBrushGeometry(geometry, hull: hull)
        return MarkDTO(
            id: id.uuidString,
            type: "eraser",
            kind: encoded.kind,
            rect: encoded.rect,
            points: encoded.points,
            eraserStyle: encode(style)
        )
    }

    static func decodeEraser(id: UUID, dto: MarkDTO) -> Annotation? {
        guard let eraserDTO = dto.eraserStyle else {
            NSLog("SnipHistory: skipping eraser mark without eraserStyle")
            return nil
        }
        guard let geometry = decodeBrushGeometry(points: dto.points, kind: dto.kind, rect: dto.rect) else {
            NSLog("SnipHistory: skipping eraser mark without points or rect")
            return nil
        }
        return Annotation(id: id, payload: .eraser(geometry, style: decode(eraserDTO)))
    }

    static func encode(_ style: EraserStyle) -> EraserStyleDTO {
        EraserStyleDTO(brushWidth: Double(style.brushWidth))
    }

    static func decode(_ dto: EraserStyleDTO) -> EraserStyle {
        var style = EraserStyle(brushWidth: CGFloat(dto.brushWidth))
        style.clamp()
        return style
    }
}
