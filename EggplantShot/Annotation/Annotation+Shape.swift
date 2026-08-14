import AppKit

extension Annotation {
    /// Convenience for the shape tool.
    init(id: UUID = UUID(), kind: ShapeKind = .rectangle, rect: CGRect, style: AnnotationStyle) {
        self.id = id
        self.payload = .shape(kind, rect: rect, style: style)
    }
}
