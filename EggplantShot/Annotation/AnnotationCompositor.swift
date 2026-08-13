import AppKit

enum AnnotationCompositor {
    /// Draws annotations (selection-local points) onto a captured image and returns a new image.
    static func composite(_ annotations: [Annotation], onto image: NSImage) -> NSImage {
        guard !annotations.isEmpty else { return image }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let sample = AnnotationDrawing.MosaicSampleContext(
            image: image,
            selectionOriginInImage: .zero
        )
        return NSImage(size: size, flipped: false) { _ in
            image.draw(
                in: CGRect(origin: .zero, size: size),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
            // Marks (incl. eraser destinationOut) on a separate layer so base pixels stay intact.
            if let layer = AnnotationDrawing.renderMarksLayer(
                annotations,
                size: size,
                origin: .zero,
                sample: sample,
                // Match idle overlay: hide nested sources when ≥2 magnifiers (no hover on bake).
                hiddenMagnifierSourceIDs: AnnotationDrawing.nestedMagnifierSourceIDsToHide(
                    in: annotations
                )
            ) {
                layer.draw(
                    in: CGRect(origin: .zero, size: size),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            } else {
                for annotation in annotations {
                    AnnotationDrawing.draw(annotation, origin: .zero, sample: sample)
                }
            }
            return true
        }
    }
}
