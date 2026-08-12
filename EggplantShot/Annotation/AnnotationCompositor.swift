import AppKit

enum AnnotationCompositor {
    /// Draws annotations (selection-local points) onto a captured image and returns a new image.
    static func composite(_ annotations: [Annotation], onto image: NSImage) -> NSImage {
        guard !annotations.isEmpty else { return image }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        return NSImage(size: size, flipped: false) { _ in
            image.draw(
                in: CGRect(origin: .zero, size: size),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
            for annotation in annotations {
                switch annotation.kind {
                case .rectangle:
                    AnnotationDrawing.stroke(annotation, in: annotation.rect)
                }
            }
            return true
        }
    }
}
