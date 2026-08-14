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

        // Menu-bar (accessory) apps need a Dock presence for the save field to take focus.
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        // Pin panels use `.statusBar`, which sits above the default modal level and
        // otherwise covers the dialog. Drop them for the duration of the sheet.
        let pinLevels: [(PinPanel, NSWindow.Level)] = NSApp.windows.compactMap { window in
            guard let pin = window as? PinPanel, pin.isVisible else { return nil }
            return (pin, pin.level)
        }
        for (pin, _) in pinLevels {
            pin.level = .normal
        }

        let abovePins = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.level = abovePins
        // `runModal` can reset the panel level; re-apply once the modal window exists.
        DispatchQueue.main.async {
            NSApp.modalWindow?.level = abovePins
        }

        defer {
            for (pin, level) in pinLevels {
                pin.level = level
            }
            if previousPolicy != .regular {
                NSApp.setActivationPolicy(previousPolicy)
            }
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try write(image, to: url)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t Save Screenshot"
            DispatchQueue.main.async {
                NSApp.modalWindow?.level = abovePins
            }
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
