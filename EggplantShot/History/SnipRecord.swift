import AppKit
import Foundation

/// Cross-session editable snip unit: unannotated base + selection + annotation document.
struct SnipRecord: Identifiable {
    let id: UUID
    let createdAt: Date
    /// Unannotated crop (points size matches selection).
    var baseImage: NSImage
    /// Selection in Cocoa global screen coordinates (bottom-left origin).
    var selection: CGRect
    var document: AnnotationDocument

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        baseImage: NSImage,
        selection: CGRect,
        document: AnnotationDocument
    ) {
        self.id = id
        self.createdAt = createdAt
        self.baseImage = baseImage
        self.selection = selection
        self.document = document
    }
}
