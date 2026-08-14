import AppKit

extension AnnotationCoding {
    static func encodeText(id: UUID, string: String, rect: CGRect, style: TextStyle) -> MarkDTO {
        MarkDTO(
            id: id.uuidString,
            type: "text",
            rect: RectDTO(rect),
            string: string,
            textStyle: encode(style)
        )
    }

    static func decodeText(id: UUID, dto: MarkDTO) -> Annotation? {
        guard let rect = dto.rect?.cgRect, let textDTO = dto.textStyle else {
            NSLog("SnipHistory: skipping text mark without rect/textStyle")
            return nil
        }
        return Annotation(
            id: id,
            payload: .text(string: dto.string ?? "", rect: rect, style: decode(textDTO))
        )
    }

    static func encode(_ style: TextStyle) -> TextStyleDTO {
        TextStyleDTO(
            fontSize: Double(style.fontSize),
            isBold: style.isBold,
            isItalic: style.isItalic,
            hasBackground: style.hasBackground,
            color: encode(style.color)
        )
    }

    static func decode(_ dto: TextStyleDTO) -> TextStyle {
        TextStyle(
            color: decode(dto.color),
            fontSize: CGFloat(dto.fontSize),
            isBold: dto.isBold,
            isItalic: dto.isItalic,
            hasBackground: dto.hasBackground
        )
    }
}
