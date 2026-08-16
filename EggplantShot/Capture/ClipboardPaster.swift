import AppKit
import Foundation
import UniformTypeIdentifiers

/// Converts clipboard content into a pin-ready bitmap (Snipaste-style Paste).
enum ClipboardPaster {
    /// A pin-ready bitmap plus the string it was rendered *from*, when there was one — that is what
    /// the pin’s “Copy plain text” gives back. `nil` for real bitmaps (those OCR instead).
    struct PasteResult {
        let image: NSImage
        let sourceText: String?
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "bmp", "tga", "ico", "tif", "tiff", "gif", "heic", "webp",
    ]

    /// File URLs that were last pasted as images — next Paste of the same set renders paths as text.
    private static var lastPastedImageFileURLs: [URL]?

    /// Best-effort conversion. Returns `nil` when the pasteboard has nothing we can pin.
    static func imageFromPasteboard(_ pasteboard: NSPasteboard = .general) -> PasteResult? {
        // File URLs first so Finder copies keep Snipaste’s “paste again → path text” behaviour
        // even when the pasteboard also carries an image preview.
        if let urls = readFileURLs(from: pasteboard), !urls.isEmpty {
            return imageFromFileURLs(urls)
        }

        if let image = readImage(from: pasteboard) {
            lastPastedImageFileURLs = nil
            return PasteResult(image: image, sourceText: nil)
        }

        if let colorText = readPlainString(from: pasteboard),
           let color = parseColor(from: colorText) {
            lastPastedImageFileURLs = nil
            let label = colorText.trimmingCharacters(in: .whitespacesAndNewlines)
            return PasteResult(image: renderColorCard(color, label: label), sourceText: label)
        }

        if let html = readHTML(from: pasteboard),
           let rendered = renderHTML(html) {
            lastPastedImageFileURLs = nil
            // The readable text, not the markup — that is what pasting the pin back should yield.
            return PasteResult(image: rendered.image, sourceText: rendered.plainText)
        }

        if let text = readPlainString(from: pasteboard),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastPastedImageFileURLs = nil
            return PasteResult(image: renderText(text), sourceText: text)
        }

        return nil
    }

    // MARK: - Pasteboard readers

    private static func readImage(from pasteboard: NSPasteboard) -> NSImage? {
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           image.size.width > 0, image.size.height > 0 {
            return image
        }
        // Some apps only put TIFF / PNG data.
        for type in [NSPasteboard.PasteboardType.tiff, .png] {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data),
               image.size.width > 0, image.size.height > 0 {
                return image
            }
        }
        return nil
    }

    private static func readPlainString(from pasteboard: NSPasteboard) -> String? {
        pasteboard.string(forType: .string)
    }

    private static func readHTML(from pasteboard: NSPasteboard) -> String? {
        if let data = pasteboard.data(forType: .html),
           let html = String(data: data, encoding: .utf8) {
            return html
        }
        // Some apps expose HTML as a string type.
        if let html = pasteboard.string(forType: .html) {
            return html
        }
        return nil
    }

    private static func readFileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !urls.isEmpty {
            return urls
        }
        // Fallback: Finder sometimes only writes `public.file-url` / filenames.
        if let items = pasteboard.pasteboardItems {
            var urls: [URL] = []
            for item in items {
                if let str = item.string(forType: .fileURL),
                   let url = URL(string: str), url.isFileURL {
                    urls.append(url)
                }
            }
            if !urls.isEmpty { return urls }
        }
        return nil
    }

    private static func imageFromFileURLs(_ urls: [URL]) -> PasteResult? {
        let normalized = urls.map { $0.standardizedFileURL }
        if let last = lastPastedImageFileURLs,
           last == normalized {
            // Second paste of the same image file(s) → path text (Snipaste parity).
            lastPastedImageFileURLs = nil
            let paths = normalized.map(\.path).joined(separator: "\n")
            return PasteResult(image: renderText(paths), sourceText: paths)
        }

        let imageURLs = normalized.filter { isImageFile($0) }
        if let first = imageURLs.first,
           let image = NSImage(contentsOf: first),
           image.size.width > 0, image.size.height > 0 {
            lastPastedImageFileURLs = normalized
            return PasteResult(image: image, sourceText: nil)
        }

        // Non-image file(s) → path as text image.
        lastPastedImageFileURLs = nil
        let paths = normalized.map(\.path).joined(separator: "\n")
        return PasteResult(image: renderText(paths), sourceText: paths)
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return true }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
            return true
        }
        return false
    }

    // MARK: - Color parsing (Snipaste: HEX #… / three 0–255 ints / three 0–1 floats)

    static func parseColor(from raw: String) -> NSColor? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("\n") else { return nil }

        if text.hasPrefix("#") {
            return parseHexColor(text)
        }

        // Strip optional `rgb(...)` / `rgba(...)` wrappers.
        var body = text
        let lower = text.lowercased()
        if lower.hasPrefix("rgb(") || lower.hasPrefix("rgba("),
           text.hasSuffix(")"),
           let open = text.firstIndex(of: "(") {
            let innerStart = text.index(after: open)
            let innerEnd = text.index(before: text.endIndex)
            body = String(text[innerStart..<innerEnd])
        }

        let parts = body
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard parts.count == 3 || parts.count == 4 else { return nil }

        let nums = parts.prefix(3).compactMap { Double($0) }
        guard nums.count == 3 else { return nil }

        // Prefer 0–255 integers when all look like channel bytes.
        let looksByte = nums.allSatisfy { $0 >= 0 && $0 <= 255 && $0 == $0.rounded() }
        let looksUnit = nums.allSatisfy { $0 >= 0 && $0 <= 1 }

        if looksByte {
            return NSColor(
                calibratedRed: nums[0] / 255,
                green: nums[1] / 255,
                blue: nums[2] / 255,
                alpha: 1
            )
        }
        if looksUnit {
            return NSColor(
                calibratedRed: nums[0],
                green: nums[1],
                blue: nums[2],
                alpha: 1
            )
        }
        return nil
    }

    private static func parseHexColor(_ text: String) -> NSColor? {
        var hex = text.dropFirst().uppercased()
        // Allow optional alpha (#RRGGBBAA / #RGBA).
        switch hex.count {
        case 3, 4:
            hex = hex.map { "\($0)\($0)" }.joined()
        case 6, 8:
            break
        default:
            return nil
        }
        guard hex.allSatisfy(\.isHexDigit) else { return nil }

        func channel(_ start: Int) -> CGFloat {
            let i = hex.index(hex.startIndex, offsetBy: start)
            let j = hex.index(i, offsetBy: 2)
            return CGFloat(Int(hex[i..<j], radix: 16) ?? 0) / 255
        }

        let a: CGFloat = hex.count == 8 ? channel(6) : 1
        return NSColor(calibratedRed: channel(0), green: channel(2), blue: channel(4), alpha: a)
    }

    // MARK: - Renderers

    private static func renderColorCard(_ color: NSColor, label: String) -> NSImage {
        let swatchSize = CGSize(width: 160, height: 96)
        let pad: CGFloat = 12
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        let labelSize = (label as NSString).size(withAttributes: attrs)
        let width = max(swatchSize.width, labelSize.width) + pad * 2
        let height = swatchSize.height + pad * 3 + ceil(labelSize.height)
        let size = CGSize(width: width, height: height)

        return drawImage(size: size) { _ in
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 8, yRadius: 8).fill()

            let swatch = CGRect(
                x: (width - swatchSize.width) / 2,
                y: height - pad - swatchSize.height,
                width: swatchSize.width,
                height: swatchSize.height
            )
            let swatchPath = NSBezierPath(roundedRect: swatch, xRadius: 6, yRadius: 6)
            NSGraphicsContext.saveGraphicsState()
            swatchPath.addClip()
            drawCheckerboard(in: swatch, cell: 8)
            color.setFill()
            swatchPath.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor.separatorColor.setStroke()
            let border = NSBezierPath(roundedRect: swatch.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            border.lineWidth = 1
            border.stroke()

            let labelOrigin = CGPoint(x: (width - labelSize.width) / 2, y: pad)
            (label as NSString).draw(at: labelOrigin, withAttributes: attrs)
        }
    }

    private static func drawCheckerboard(in rect: CGRect, cell: CGFloat) {
        let light = NSColor(calibratedWhite: 0.92, alpha: 1)
        let dark = NSColor(calibratedWhite: 0.78, alpha: 1)
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX
            var col = 0
            let h = min(cell, rect.maxY - y)
            while x < rect.maxX {
                let w = min(cell, rect.maxX - x)
                ((row + col).isMultiple(of: 2) ? light : dark).setFill()
                NSBezierPath(rect: CGRect(x: x, y: y, width: w, height: h)).fill()
                x += cell
                col += 1
            }
            y += cell
            row += 1
        }
    }

    private static func renderText(_ text: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 14)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        return renderAttributedText(NSAttributedString(string: text, attributes: attrs))
    }

    private static func renderHTML(_ html: String) -> (image: NSImage, plainText: String)? {
        let data = Data(html.utf8)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil),
              attributed.length > 0
        else { return nil }
        // If HTML is empty of visible text, skip so plain-text / files can try.
        let plain = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }
        return (renderAttributedText(attributed), plain)
    }

    private static func renderAttributedText(_ attributed: NSAttributedString) -> NSImage {
        let maxWidth: CGFloat = 480
        let pad: CGFloat = 14
        let constraint = CGSize(width: maxWidth - pad * 2, height: 10_000)
        let bounds = attributed.boundingRect(
            with: constraint,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textSize = CGSize(
            width: min(max(ceil(bounds.width), 40), maxWidth - pad * 2),
            height: max(ceil(bounds.height), 18)
        )
        let size = CGSize(width: textSize.width + pad * 2, height: textSize.height + pad * 2)

        return drawImage(size: size) { _ in
            NSColor.textBackgroundColor.setFill()
            NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 6, yRadius: 6).fill()

            let drawRect = CGRect(x: pad, y: pad, width: textSize.width, height: textSize.height)
            attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    private static func drawImage(size: CGSize, body: (CGRect) -> Void) -> NSImage {
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 1)
        let pixels = NSSize(width: size.width * scale, height: size.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixels.width.rounded()),
            pixelsHigh: Int(pixels.height.rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        body(CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
