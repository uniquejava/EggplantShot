import AppKit

extension AnnotationCoding {
    static func encodeMagnifier(
        id: UUID,
        kind: ShapeKind,
        source: CGRect,
        lens: CGRect,
        style: MagnifierStyle
    ) -> MarkDTO {
        MarkDTO(
            id: id.uuidString,
            type: "magnifier",
            kind: kindString(kind),
            rect: RectDTO(source),
            lensRect: RectDTO(lens),
            magnifierStyle: encode(style)
        )
    }

    static func decodeMagnifier(id: UUID, dto: MarkDTO) -> Annotation? {
        guard let source = dto.rect?.cgRect,
              let lens = dto.lensRect?.cgRect,
              let magDTO = dto.magnifierStyle else {
            NSLog("SnipHistory: skipping magnifier mark without source/lens/style")
            return nil
        }
        var style = decode(magDTO)
        // Prefer stored scale; derive from geometry only for legacy records without scale.
        if magDTO.scale == nil {
            style.scale = Annotation.magnifierScale(source: source, lens: lens)
        }
        return Annotation(
            id: id,
            magnifierKind: kindFromString(dto.kind) ?? .rectangle,
            source: source,
            lens: lens,
            magnifierStyle: style
        )
    }

    static func encode(_ style: MagnifierStyle) -> MagnifierStyleDTO {
        MagnifierStyleDTO(
            strokeWidth: Double(style.strokeWidth),
            color: encode(style.color),
            includeAnnotations: style.includeAnnotations,
            scale: Double(style.scale)
        )
    }

    static func decode(_ dto: MagnifierStyleDTO) -> MagnifierStyle {
        var style = MagnifierStyle(
            strokeWidth: CGFloat(dto.strokeWidth),
            color: decode(dto.color),
            includeAnnotations: dto.includeAnnotations,
            scale: dto.scale.map { MagnifierStyle.clampedScale(CGFloat($0)) } ?? MagnifierStyle.defaultScale
        )
        style.clamp()
        return style
    }
}
