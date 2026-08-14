import AppKit

extension Annotation {
    /// Convenience for the pencil tool.
    init(id: UUID = UUID(), points: [CGPoint], style: AnnotationStyle) {
        self.id = id
        self.payload = .pencil(points: points, style: style)
    }
}
