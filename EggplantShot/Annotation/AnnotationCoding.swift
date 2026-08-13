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
                endCap: nil
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
                endCap: caps.end.rawValue
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
                endCap: nil
            )
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
                endCap: nil
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
        case "text":
            guard let rect = dto.rect?.cgRect, let textDTO = dto.textStyle else {
                NSLog("SnipHistory: skipping text mark without rect/textStyle")
                return nil
            }
            return Annotation(
                id: id,
                payload: .text(string: dto.string ?? "", rect: rect, style: decode(textDTO))
            )
        default:
            NSLog("SnipHistory: skipping unknown mark type '%@'", dto.type)
            return nil
        }
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
