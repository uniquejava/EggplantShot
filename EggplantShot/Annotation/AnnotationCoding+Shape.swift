import AppKit

extension AnnotationCoding {
    static func encodeShape(id: UUID, kind: ShapeKind, rect: CGRect, style: AnnotationStyle) -> MarkDTO {
        MarkDTO(
            id: id.uuidString,
            type: "shape",
            kind: kindString(kind),
            rect: RectDTO(rect),
            style: encode(style)
        )
    }

    static func decodeShape(id: UUID, dto: MarkDTO) -> Annotation? {
        guard let rect = dto.rect?.cgRect, let styleDTO = dto.style else {
            NSLog("SnipHistory: skipping shape mark without rect/style")
            return nil
        }
        return Annotation(
            id: id,
            payload: .shape(kindFromString(dto.kind) ?? .rectangle, rect: rect, style: decode(styleDTO))
        )
    }
}
