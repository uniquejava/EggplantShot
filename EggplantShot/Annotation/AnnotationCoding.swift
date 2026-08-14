import AppKit
import Foundation

/// Codable DTOs for snip-history disk schema (version 1).
/// Per-tool encode/decode lives in `AnnotationCoding+{Tool}.swift`.
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

        /// Defaults every tool-specific field to `nil` so encode sites stay short.
        init(
            id: String,
            type: String,
            kind: String? = nil,
            rect: RectDTO? = nil,
            points: [PointDTO]? = nil,
            string: String? = nil,
            style: StyleDTO? = nil,
            textStyle: TextStyleDTO? = nil,
            startCap: Int? = nil,
            endCap: Int? = nil,
            mosaicStyle: MosaicStyleDTO? = nil,
            markerStyle: MarkerStyleDTO? = nil,
            eraserStyle: EraserStyleDTO? = nil,
            stepStyle: StepStyleDTO? = nil,
            number: Int? = nil,
            lensRect: RectDTO? = nil,
            magnifierStyle: MagnifierStyleDTO? = nil
        ) {
            self.id = id
            self.type = type
            self.kind = kind
            self.rect = rect
            self.points = points
            self.string = string
            self.style = style
            self.textStyle = textStyle
            self.startCap = startCap
            self.endCap = endCap
            self.mosaicStyle = mosaicStyle
            self.markerStyle = markerStyle
            self.eraserStyle = eraserStyle
            self.stepStyle = stepStyle
            self.number = number
            self.lensRect = lensRect
            self.magnifierStyle = magnifierStyle
        }
    }

    struct MagnifierStyleDTO: Codable {
        var strokeWidth: Double
        var color: ColorDTO
        var includeAnnotations: Bool
        /// Optional for backward compatibility; missing → derive from lens/source geometry.
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
            return encodeShape(id: annotation.id, kind: kind, rect: rect, style: style)
        case .arrow(let start, let end, let style, let caps):
            return encodeArrow(
                id: annotation.id,
                start: start,
                end: end,
                style: style,
                caps: caps,
                hull: annotation.boundingRect
            )
        case .pencil(let points, let style):
            return encodePencil(id: annotation.id, points: points, style: style, hull: annotation.boundingRect)
        case .marker(let geometry, let style):
            return encodeMarker(id: annotation.id, geometry: geometry, style: style, hull: annotation.boundingRect)
        case .mosaic(let geometry, let style):
            return encodeMosaic(id: annotation.id, geometry: geometry, style: style, hull: annotation.boundingRect)
        case .eraser(let geometry, let style):
            return encodeEraser(id: annotation.id, geometry: geometry, style: style, hull: annotation.boundingRect)
        case .text(let string, let rect, let style):
            return encodeText(id: annotation.id, string: string, rect: rect, style: style)
        case .step(let number, let center, let style):
            return encodeStep(id: annotation.id, number: number, center: center, style: style)
        case .magnifier(let kind, let source, let lens, let style):
            return encodeMagnifier(id: annotation.id, kind: kind, source: source, lens: lens, style: style)
        }
    }

    static func decodeMark(_ dto: MarkDTO) -> Annotation? {
        guard let id = UUID(uuidString: dto.id) else {
            NSLog("SnipHistory: skipping mark with invalid id")
            return nil
        }
        switch dto.type {
        case "shape": return decodeShape(id: id, dto: dto)
        case "arrow": return decodeArrow(id: id, dto: dto)
        case "pencil": return decodePencil(id: id, dto: dto)
        case "marker": return decodeMarker(id: id, dto: dto)
        case "mosaic": return decodeMosaic(id: id, dto: dto)
        case "eraser": return decodeEraser(id: id, dto: dto)
        case "text": return decodeText(id: id, dto: dto)
        case "step": return decodeStep(id: id, dto: dto)
        case "magnifier": return decodeMagnifier(id: id, dto: dto)
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

    // MARK: - Shared

    static func kindString(_ kind: ShapeKind) -> String {
        switch kind {
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        }
    }

    static func kindFromString(_ raw: String?) -> ShapeKind? {
        switch raw {
        case "rectangle": return .rectangle
        case "ellipse": return .ellipse
        default: return nil
        }
    }

    static func decodeBrushGeometry(points: [PointDTO]?, kind: String?, rect: RectDTO?) -> MosaicGeometry? {
        if let points, !points.isEmpty {
            return .stroke(points: points.map(\.cgPoint))
        }
        if let rect = rect?.cgRect {
            let mode: MosaicDrawMode = (kind == "ellipse") ? .ellipse : .rectangle
            return .region(mode, rect: rect)
        }
        return nil
    }

    static func encodeBrushGeometry(_ geometry: MosaicGeometry, hull: CGRect) -> (kind: String?, rect: RectDTO, points: [PointDTO]?) {
        switch geometry {
        case .stroke(let points):
            return (nil, RectDTO(hull), points.map(PointDTO.init))
        case .region(let mode, let rect):
            return (mode == .ellipse ? "ellipse" : "rectangle", RectDTO(rect), nil)
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
