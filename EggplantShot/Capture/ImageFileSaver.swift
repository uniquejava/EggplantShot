import AppKit
import UniformTypeIdentifiers

/// Interactive save of a captured bitmap via `NSSavePanel`.
enum ImageFileSaver {
    @MainActor
    static func saveInteractive(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = false
        panel.nameFieldStringValue = defaultFileName(extension: "png")
        panel.title = "Save Screenshot"
        panel.message = "Choose where to save the screenshot."

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try write(image, to: url)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t Save Screenshot"
            alert.runModal()
        }
    }

    static func write(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else {
            throw SaveError.encodeFailed
        }

        let ext = url.pathExtension.lowercased()
        let fileType: NSBitmapImageRep.FileType
        let props: [NSBitmapImageRep.PropertyKey: Any]
        switch ext {
        case "jpg", "jpeg":
            fileType = .jpeg
            props = [.compressionFactor: 0.9]
        default:
            fileType = .png
            props = [:]
        }

        guard let data = rep.representation(using: fileType, properties: props) else {
            throw SaveError.encodeFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private static func defaultFileName(extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())).\(ext)"
    }

    private enum SaveError: LocalizedError {
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .encodeFailed:
                return "Failed to encode the image."
            }
        }
    }
}
