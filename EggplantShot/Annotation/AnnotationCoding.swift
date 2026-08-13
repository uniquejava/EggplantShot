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
        var rect: RectDTO
        var style: StyleDTO
    }

    struct StyleDTO: Codable {
        var strokeWidth: Double
        var isFilled: Bool
        var lineStyle: Int
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
        MarkDTO(
            id: annotation.id.uuidString,
            type: "shape",
            kind: kindString(annotation.kind),
            rect: RectDTO(annotation.rect),
            style: encode(annotation.style)
        )
    }

    static func decodeMark(_ dto: MarkDTO) -> Annotation? {
        guard dto.type == "shape" else {
            NSLog("SnipHistory: skipping unknown mark type '%@'", dto.type)
            return nil
        }
        guard let id = UUID(uuidString: dto.id) else {
            NSLog("SnipHistory: skipping mark with invalid id")
            return nil
        }
        let kind = kindFromString(dto.kind) ?? .rectangle
        return Annotation(id: id, kind: kind, rect: dto.rect.cgRect, style: decode(dto.style))
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

    private static func kindString(_ kind: Annotation.Kind) -> String {
        switch kind {
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        }
    }

    private static func kindFromString(_ raw: String?) -> Annotation.Kind? {
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
