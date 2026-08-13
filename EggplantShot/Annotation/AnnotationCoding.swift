import AppKit
import Foundation

/// Codable DTOs for snip-history disk schema (version 1).
enum AnnotationCoding {
    static let schemaVersion = 1

    // MARK: - File payloads

    struct IndexFile: Codable {
        var schemaVersion: Int
        var maxCount: Int
        var ids: [String]
    }

    struct MetaFile: Codable {
        var schemaVersion: Int
        var id: String
        var createdAt: String
        var selection: RectDTO
        var imagePoints: SizeDTO
        var document: DocumentDTO
    }

    struct DocumentDTO: Codable {
        var selectedID: String?
        var marks: [MarkDTO]
    }

    struct MarkDTO: Codable {
        var id: String
        var type: String
        var kind: String?
        /// Shape / text bounding rect; also written for pencil / arrow as the path hull (optional on decode).
        var rect: RectDTO?
        var points: [PointDTO]?
        /// Text mark body (type == "text").
        var string: String?
        var style: StyleDTO?
        var textStyle: TextStyleDTO?
        /// Arrow start / end caps (type == "arrow"); omitted → defaults.
        var startCap: Int?
        var endCap: Int?
        /// Mosaic brush style (type == "mosaic").
        var mosaicStyle: MosaicStyleDTO?
        /// Marker / highlighter style (type == "marker").
        var markerStyle: MarkerStyleDTO?
        /// Eraser brush style (type == "eraser").
        var eraserStyle: EraserStyleDTO?
        /// Step / numbering style (type == "step").
        var stepStyle: StepStyleDTO?
        /// Step number (type == "step").
        var number: Int?
        /// Magnifier lens rect (type == "magnifier"); `rect` is the source sample.
        var lensRect: RectDTO?
        /// Magnifier style (type == "magnifier").
        var magnifierStyle: MagnifierStyleDTO?
    }

    struct MagnifierStyleDTO: Codable {
        var strokeWidth: Double
        var color: ColorDTO
        var includeAnnotations: Bool
        /// Optional for backward compatibility; geometry remains source of truth on load.
        var scale: Double?
    }

    struct MosaicStyleDTO: Codable {
        var brushWidth: Double
        var intensity: Double
        /// Legacy tip shape (0/1); ignored on decode for style (geometry carries region kind).
        var brushKind: Int?
    }

    struct MarkerStyleDTO: Codable {
        var brushWidth: Double
        var color: ColorDTO
    }

    struct EraserStyleDTO: Codable {
        var brushWidth: Double
    }

    struct StepStyleDTO: Codable {
        var kind: Int
        var size: Double
        var color: ColorDTO
    }

    struct PointDTO: Codable {
        var x: Double
        var y: Double

        init(_ point: CGPoint) {
            x = Double(point.x)
            y = Double(point.y)
        }

        var cgPoint: CGPoint {
            CGPoint(x: x, y: y)
        }
    }

    struct StyleDTO: Codable {
        var strokeWidth: Double
        var isFilled: Bool
        var lineStyle: Int
        var color: ColorDTO
    }

    struct TextStyleDTO: Codable {
        var fontSize: Double
        var isBold: Bool
        var isItalic: Bool
        var hasBackground: Bool
        var color: ColorDTO
    }

    struct ColorDTO: Codable {
        var r: Double
        var g: Double
        var b: Double
        var a: Double
    }

    struct RectDTO: Codable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double

        init(_ rect: CGRect) {
            x = rect.origin.x
            y = rect.origin.y
            w = rect.width
            h = rect.height
        }

        var cgRect: CGRect {
            CGRect(x: x, y: y, width: w, height: h)
        }
    }

    struct SizeDTO: Codable {
        var w: Double
        var h: Double

        init(_ size: CGSize) {
            w = size.width
            h = size.height
        }

        var cgSize: CGSize {
            CGSize(width: w, height: h)
        }
    }

    // MARK: - Encode / decode

    static func encode(_ document: AnnotationDocument) -> DocumentDTO {
        DocumentDTO(
            selectedID: document.selectedID?.uuidString,
            marks: document.marks.map { encode($0) }
        )
    }

    static func decode(_ dto: DocumentDTO) -> AnnotationDocument {
        var marks: [Annotation] = []
        marks.reserveCapacity(dto.marks.count)
        for markDTO in dto.marks {
            if let mark = decodeMark(markDTO) {
                marks.append(mark)
            }
        }
        let selected: UUID? = dto.selectedID.flatMap(UUID.init(uuidString:))
        let selectedID = selected.flatMap { id in marks.contains(where: { $0.id == id }) ? id : nil }
        return AnnotationDocument(marks: marks, selectedID: selectedID)
    }

    static func encode(_ annotation: Annotation) -> MarkDTO {
        switch annotation.payload {
        case .shape(let kind, let rect, let style):
            return MarkDTO(
                id: annotation.id.uuidString,
                type: "shape",
                kind: kindString(kind),
                rect: RectDTO(rect),
                points: nil,
                string: nil,
                style: encode(style),
                textStyle: nil,
                startCap: nil,
                endCap: nil,
                mosaicStyle: nil,
                markerStyle: nil,
                eraserStyle: nil,
                stepStyle: nil,
                number: nil,
                lensRect: nil,
                magnifierStyle: nil
            )
        case .arrow(let start, let end, let style, let caps):
            return MarkDTO(
                id: annotation.id.uuidString,
                type: "arrow",
                kind: nil,
                rect: RectDTO(annotation.boundingRect),
                points: [PointDTO(start), PointDTO(end)],
                string: nil,
                style: encode(style),
                textStyle: nil,
                startCap: caps.start.rawValue,
                endCap: caps.end.rawValue,
                mosaicStyle: nil,
                markerStyle: nil,
                eraserStyle: nil,
                stepStyle: nil,
                number: nil,
                lensRect: nil,
                magnifierStyle: nil
            )
        case .pencil(let points, let style):
            return MarkDTO(
                id: annotation.id.uuidString,
                type: "pencil",
                kind: nil,
                rect: RectDTO(annotation.boundingRect),
                points: points.map(PointDTO.init),
                string: nil,
                style: encode(style),
                textStyle: nil,
                startCap: nil,
                endCap: nil,
                mosaicStyle: nil,
                markerStyle: nil,
                eraserStyle: nil,
                stepStyle: nil,
                number: nil,
                lensRect: nil,
                magnifierStyle: nil
            )
        case .marker(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                return MarkDTO(
                    id: annotation.id.uuidString,
                    type: "marker",
                    kind: nil,
                    rect: RectDTO(annotation.boundingRect),
                    points: points.map(PointDTO.init),
                    string: nil,
                    style: nil,
                    textStyle: nil,
                    startCap: nil,
                    endCap: nil,
                    mosaicStyle: nil,
                    markerStyle: encode(style),
                    eraserStyle: nil,
                    stepStyle: nil,
                    number: nil,
                lensRect: nil,
                magnifierStyle: nil
                )
            case .region(let mode, let rect):
                return MarkDTO(
                    id: annotation.id.uuidString,
                    type: "marker",
                    kind: mode == .ellipse ? "ellipse" : "rectangle",
                    rect: RectDTO(rect),
                    points: nil,
                    string: nil,
                    style: nil,
                    textStyle: nil,
                    startCap: nil,
                    endCap: nil,
                    mosaicStyle: nil,
                    markerStyle: encode(style),
                    eraserStyle: nil,
                    stepStyle: nil,
                    number: nil,
                lensRect: nil,
                magnifierStyle: nil
                )
            }
        case .mosaic(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                return MarkDTO(
                    id: annotation.id.uuidString,
                    type: "mosaic",
                    kind: nil,
                    rect: RectDTO(annotation.boundingRect),
                    points: points.map(PointDTO.init),
                    string: nil,
                    style: nil,
                    textStyle: nil,
                    startCap: nil,
                    endCap: nil,
                    mosaicStyle: encode(style),
                    markerStyle: nil,
                    eraserStyle: nil,
                    stepStyle: nil,
                    number: nil,
                lensRect: nil,
                magnifierStyle: nil
                )
            case .region(let mode, let rect):
                return MarkDTO(
                    id: annotation.id.uuidString,
                    type: "mosaic",
                    kind: mode == .ellipse ? "ellipse" : "rectangle",
                    rect: RectDTO(rect),
                    points: nil,
                    string: nil,
                    style: nil,
                    textStyle: nil,
                    startCap: nil,
                    endCap: nil,
                    mosaicStyle: encode(style),
                    markerStyle: nil,
                    eraserStyle: nil,
                    stepStyle: nil,
                    number: nil,
                lensRect: nil,
                magnifierStyle: nil
                )
            }
        case .eraser(let geometry, let style):
            switch geometry {
            case .stroke(let points):
                return MarkDTO(
                    id: annotation.id.uuidString,
                    type: "eraser",
                    kind: nil,
                    rect: RectDTO(annotation.boundingRect),
                    points: points.map(PointDTO.init),
                    string: nil,
                    style: nil,
                    textStyle: nil,
                    startCap: nil,
                    endCap: nil,
                    mosaicStyle: nil,
                    markerStyle: nil,
                    eraserStyle: encode(style),
                    stepStyle: nil,
                    number: nil,
                lensRect: nil,
                magnifierStyle: nil
                )
            case .region(let mode, let rect):
                return MarkDTO(
                    id: annotation.id.uuidString,
                    type: "eraser",
                    kind: mode == .ellipse ? "ellipse" : "rectangle",
                    rect: RectDTO(rect),
                    points: nil,
                    string: nil,
                    style: nil,
                    textStyle: nil,
                    startCap: nil,
                    endCap: nil,
                    mosaicStyle: nil,
                    markerStyle: nil,
                    eraserStyle: encode(style),
                    stepStyle: nil,
                    number: nil,
                lensRect: nil,
                magnifierStyle: nil
                )
            }
        case .text(let string, let rect, let style):
            return MarkDTO(
                id: annotation.id.uuidString,
                type: "text",
                kind: nil,
                rect: RectDTO(rect),
                points: nil,
                string: string,
                style: nil,
                textStyle: encode(style),
                startCap: nil,
                endCap: nil,
                mosaicStyle: nil,
                markerStyle: nil,
                eraserStyle: nil,
                stepStyle: nil,
                number: nil,
                lensRect: nil,
                magnifierStyle: nil
            )
        case .step(let number, let center, let style):
            return MarkDTO(
                id: annotation.id.uuidString,
                type: "step",
                kind: nil,
                rect: RectDTO(style.bounds(around: center)),
                points: [PointDTO(center)],
                string: nil,
                style: nil,
                textStyle: nil,
                startCap: nil,
                endCap: nil,
                mosaicStyle: nil,
                markerStyle: nil,
                eraserStyle: nil,
                stepStyle: encode(style),
                number: number,
                lensRect: nil,
                magnifierStyle: nil
            )
        case .magnifier(let kind, let source, let lens, let style):
            return MarkDTO(
                id: annotation.id.uuidString,
                type: "magnifier",
                kind: kindString(kind),
                rect: RectDTO(source),
                points: nil,
                string: nil,
                style: nil,
                textStyle: nil,
                startCap: nil,
                endCap: nil,
                mosaicStyle: nil,
                markerStyle: nil,
                eraserStyle: nil,
                stepStyle: nil,
                number: nil,
                lensRect: RectDTO(lens),
                magnifierStyle: encode(style)
            )
        }
    }

    static func decodeMark(_ dto: MarkDTO) -> Annotation? {
        guard let id = UUID(uuidString: dto.id) else {
            NSLog("SnipHistory: skipping mark with invalid id")
            return nil
        }
        switch dto.type {
        case "shape":
            guard let rect = dto.rect?.cgRect, let styleDTO = dto.style else {
                NSLog("SnipHistory: skipping shape mark without rect/style")
                return nil
            }
            let kind = kindFromString(dto.kind) ?? .rectangle
            return Annotation(
                id: id,
                payload: .shape(kind, rect: rect, style: decode(styleDTO))
            )
        case "arrow":
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
        case "pencil":
            guard let points = dto.points, points.count >= 2, let styleDTO = dto.style else {
                NSLog("SnipHistory: skipping pencil mark without points/style")
                return nil
            }
            return Annotation(
                id: id,
                payload: .pencil(points: points.map(\.cgPoint), style: decode(styleDTO))
            )
        case "marker":
            guard let markerDTO = dto.markerStyle else {
                NSLog("SnipHistory: skipping marker mark without markerStyle")
                return nil
            }
            let style = decode(markerDTO)
            if let points = dto.points, !points.isEmpty {
                return Annotation(
                    id: id,
                    payload: .marker(.stroke(points: points.map(\.cgPoint)), style: style)
                )
            }
            if let rect = dto.rect?.cgRect {
                let mode: MosaicDrawMode = (dto.kind == "ellipse") ? .ellipse : .rectangle
                return Annotation(
                    id: id,
                    payload: .marker(.region(mode, rect: rect), style: style)
                )
            }
            NSLog("SnipHistory: skipping marker mark without points or rect")
            return nil
        case "mosaic":
            guard let mosaicDTO = dto.mosaicStyle else {
                NSLog("SnipHistory: skipping mosaic mark without mosaicStyle")
                return nil
            }
            let style = decode(mosaicDTO)
            if let points = dto.points, !points.isEmpty {
                return Annotation(
                    id: id,
                    payload: .mosaic(.stroke(points: points.map(\.cgPoint)), style: style)
                )
            }
            if let rect = dto.rect?.cgRect {
                let mode: MosaicDrawMode = (dto.kind == "ellipse") ? .ellipse : .rectangle
                return Annotation(
                    id: id,
                    payload: .mosaic(.region(mode, rect: rect), style: style)
                )
            }
            NSLog("SnipHistory: skipping mosaic mark without points or rect")
            return nil
        case "eraser":
            guard let eraserDTO = dto.eraserStyle else {
                NSLog("SnipHistory: skipping eraser mark without eraserStyle")
                return nil
            }
            let style = decode(eraserDTO)
            if let points = dto.points, !points.isEmpty {
                return Annotation(
                    id: id,
                    payload: .eraser(.stroke(points: points.map(\.cgPoint)), style: style)
                )
            }
            if let rect = dto.rect?.cgRect {
                let mode: MosaicDrawMode = (dto.kind == "ellipse") ? .ellipse : .rectangle
                return Annotation(
                    id: id,
                    payload: .eraser(.region(mode, rect: rect), style: style)
                )
            }
            NSLog("SnipHistory: skipping eraser mark without points or rect")
            return nil
        case "text":
            guard let rect = dto.rect?.cgRect, let textDTO = dto.textStyle else {
                NSLog("SnipHistory: skipping text mark without rect/textStyle")
                return nil
            }
            return Annotation(
                id: id,
                payload: .text(string: dto.string ?? "", rect: rect, style: decode(textDTO))
            )
        case "step":
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
        case "magnifier":
            guard let source = dto.rect?.cgRect,
                  let lens = dto.lensRect?.cgRect,
                  let magDTO = dto.magnifierStyle else {
                NSLog("SnipHistory: skipping magnifier mark without source/lens/style")
                return nil
            }
            var style = decode(magDTO)
            // Geometry is authoritative for zoom; keep style.scale in sync for toolbar / prefs.
            style.scale = Annotation.magnifierScale(source: source, lens: lens)
            return Annotation(
                id: id,
                magnifierKind: kindFromString(dto.kind) ?? .rectangle,
                source: source,
                lens: lens,
                magnifierStyle: style
            )
        default:
            NSLog("SnipHistory: skipping unknown mark type '%@'", dto.type)
            return nil
        }
    }

    static func encode(_ style: MosaicStyle) -> MosaicStyleDTO {
        MosaicStyleDTO(
            brushWidth: Double(style.brushWidth),
            intensity: Double(style.intensity),
            brushKind: nil
        )
    }

    static func decode(_ dto: MosaicStyleDTO) -> MosaicStyle {
        var style = MosaicStyle(
            brushWidth: CGFloat(dto.brushWidth),
            intensity: CGFloat(dto.intensity)
        )
        style.clamp()
        return style
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

    static func encode(_ style: EraserStyle) -> EraserStyleDTO {
        EraserStyleDTO(brushWidth: Double(style.brushWidth))
    }

    static func decode(_ dto: EraserStyleDTO) -> EraserStyle {
        var style = EraserStyle(brushWidth: CGFloat(dto.brushWidth))
        style.clamp()
        return style
    }

    static func encode(_ style: AnnotationStyle) -> StyleDTO {
        StyleDTO(
            strokeWidth: Double(style.strokeWidth),
            isFilled: style.isFilled,
            lineStyle: style.lineStyle.rawValue,
            color: encode(style.strokeColor)
        )
    }

    static func decode(_ dto: StyleDTO) -> AnnotationStyle {
        AnnotationStyle(
            strokeWidth: CGFloat(dto.strokeWidth),
            strokeColor: decode(dto.color),
            isFilled: dto.isFilled,
            lineStyle: StrokeLineStyle(rawValue: dto.lineStyle) ?? .solid
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

    static func encode(_ color: NSColor) -> ColorDTO {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        return ColorDTO(
            r: Double(rgb.redComponent),
            g: Double(rgb.greenComponent),
            b: Double(rgb.blueComponent),
            a: Double(rgb.alphaComponent)
        )
    }

    static func decode(_ dto: ColorDTO) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(dto.r),
            green: CGFloat(dto.g),
            blue: CGFloat(dto.b),
            alpha: CGFloat(dto.a)
        )
    }

    static func encodeMeta(for record: SnipRecord) -> MetaFile {
        MetaFile(
            schemaVersion: schemaVersion,
            id: record.id.uuidString,
            createdAt: dateString(record.createdAt),
            selection: RectDTO(record.selection),
            imagePoints: SizeDTO(record.baseImage.size),
            document: encode(record.document)
        )
    }

    static func decodeRecord(meta: MetaFile, baseImage: NSImage) -> SnipRecord? {
        guard meta.schemaVersion == schemaVersion else {
            NSLog("SnipHistory: unsupported schemaVersion %d", meta.schemaVersion)
            return nil
        }
        guard let id = UUID(uuidString: meta.id) else { return nil }
        let image = baseImage
        image.size = meta.imagePoints.cgSize
        return SnipRecord(
            id: id,
            createdAt: date(from: meta.createdAt) ?? Date(),
            baseImage: image,
            selection: meta.selection.cgRect,
            document: decode(meta.document)
        )
    }

    // MARK: - PNG helpers

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { return nil }
        return data
    }

    static func image(fromPNG data: Data, pointSize: CGSize) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        image.size = pointSize
        return image
    }

    // MARK: - Private

    private static func kindString(_ kind: ShapeKind) -> String {
        switch kind {
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        }
    }

    private static func kindFromString(_ raw: String?) -> ShapeKind? {
        switch raw {
        case "rectangle": return .rectangle
        case "ellipse": return .ellipse
        default: return nil
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func dateString(_ date: Date) -> String {
        isoFractional.string(from: date)
    }

    private static func date(from string: String) -> Date? {
        isoFractional.date(from: string) ?? isoBasic.date(from: string)
    }
}
