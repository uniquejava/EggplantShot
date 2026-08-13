import AppKit
import Vision

/// OCR for a snip crop via Vision (`VNRecognizeTextRequest`).
enum TextRecognizer {
    /// Recognizes text in reading order (top→bottom, then left→right). Empty if none / failure.
    static func recognize(_ image: NSImage) async -> String {
        guard let cgImage = cgImage(from: image) else { return "" }

        return await Task.detached(priority: .userInitiated) {
            await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                let request = VNRecognizeTextRequest { request, _ in
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let lines = observations
                        .sorted(by: readingOrder)
                        .compactMap { $0.topCandidates(1).first?.string }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                // zh first so mixed Chinese/English screenshots prefer CJK models when available.
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }.value
    }

    /// Vision boxes use bottom-left origin; sort rows then columns.
    private static func readingOrder(
        _ a: VNRecognizedTextObservation,
        _ b: VNRecognizedTextObservation
    ) -> Bool {
        let ay = a.boundingBox.midY
        let by = b.boundingBox.midY
        if abs(ay - by) > 0.02 {
            return ay > by
        }
        return a.boundingBox.minX < b.boundingBox.minX
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var proposed = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }
}
