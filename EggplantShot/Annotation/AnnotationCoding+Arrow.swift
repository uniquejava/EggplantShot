import AppKit

extension AnnotationCoding {
    static func encodeArrow(
        id: UUID,
        start: CGPoint,
        end: CGPoint,
        style: AnnotationStyle,
        caps: ArrowCaps,
        hull: CGRect
    ) -> MarkDTO {
        MarkDTO(
            id: id.uuidString,
            type: "arrow",
            rect: RectDTO(hull),
            points: [PointDTO(start), PointDTO(end)],
            style: encode(style),
            startCap: caps.start.rawValue,
            endCap: caps.end.rawValue
        )
    }

    static func decodeArrow(id: UUID, dto: MarkDTO) -> Annotation? {
        guard let points = dto.points, points.count >= 2, let styleDTO = dto.style else {
            NSLog("SnipHistory: skipping arrow mark without points/style")
            return nil
        }
        let caps = ArrowCaps(
            start: ArrowCapStyle(rawValue: dto.startCap ?? 0) ?? .none,
            end: ArrowCapStyle(rawValue: dto.endCap ?? ArrowCapStyle.openArrow.rawValue) ?? .openArrow
        )
        return Annotation(
            id: id,
            payload: .arrow(
                start: points[0].cgPoint,
                end: points[1].cgPoint,
                style: decode(styleDTO),
                caps: caps
            )
        )
    }
}
