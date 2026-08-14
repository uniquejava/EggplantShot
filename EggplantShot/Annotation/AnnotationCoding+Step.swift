import AppKit

extension AnnotationCoding {
    static func encodeStep(id: UUID, number: Int, center: CGPoint, style: StepStyle) -> MarkDTO {
        MarkDTO(
            id: id.uuidString,
            type: "step",
            rect: RectDTO(style.bounds(around: center)),
            points: [PointDTO(center)],
            stepStyle: encode(style),
            number: number
        )
    }

    static func decodeStep(id: UUID, dto: MarkDTO) -> Annotation? {
        guard let stepDTO = dto.stepStyle else {
            NSLog("SnipHistory: skipping step mark without stepStyle")
            return nil
        }
        let center: CGPoint
        if let points = dto.points, let first = points.first {
            center = first.cgPoint
        } else if let rect = dto.rect?.cgRect {
            center = CGPoint(x: rect.midX, y: rect.midY)
        } else {
            NSLog("SnipHistory: skipping step mark without center")
            return nil
        }
        return Annotation(
            id: id,
            number: dto.number ?? 1,
            center: center,
            stepStyle: decode(stepDTO)
        )
    }

    static func encode(_ style: StepStyle) -> StepStyleDTO {
        StepStyleDTO(
            kind: style.kind.rawValue,
            size: Double(style.size),
            color: encode(style.color)
        )
    }

    static func decode(_ dto: StepStyleDTO) -> StepStyle {
        var style = StepStyle(
            kind: StepChromeKind(rawValue: dto.kind) ?? .filled,
            size: CGFloat(dto.size),
            color: decode(dto.color)
        )
        style.clamp()
        return style
    }
}
