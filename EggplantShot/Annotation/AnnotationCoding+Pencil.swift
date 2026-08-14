import AppKit

extension AnnotationCoding {
    static func encodePencil(id: UUID, points: [CGPoint], style: AnnotationStyle, hull: CGRect) -> MarkDTO {
        MarkDTO(
            id: id.uuidString,
            type: "pencil",
            rect: RectDTO(hull),
            points: points.map(PointDTO.init),
            style: encode(style)
        )
    }

    static func decodePencil(id: UUID, dto: MarkDTO) -> Annotation? {
        guard let points = dto.points, points.count >= 2, let styleDTO = dto.style else {
            NSLog("SnipHistory: skipping pencil mark without points/style")
            return nil
        }
        return Annotation(
            id: id,
            payload: .pencil(points: points.map(\.cgPoint), style: decode(styleDTO))
        )
    }
}
