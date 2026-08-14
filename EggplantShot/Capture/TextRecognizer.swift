import AppKit
import Vision

/// Extract clipboard-ready content from a snip crop: QR / 2D codes first, then OCR text.
enum TextRecognizer {
    /// Prefers barcode payloads when present; otherwise Vision OCR in reading order.
    /// Empty if nothing recognized / failure.
    static func recognize(_ image: NSImage) async -> String {
        guard let cgImage = cgImage(from: image) else { return "" }

        if let code = await detectBarcodes(cgImage), !code.isEmpty {
            return code
        }
        return await recognizeText(cgImage)
    }

    // MARK: - QR / barcodes

    private static func detectBarcodes(_ cgImage: CGImage) async -> String? {
        await Task.detached(priority: .userInitiated) {
            await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                let request = VNDetectBarcodesRequest { request, _ in
                    let observations = (request.results as? [VNBarcodeObservation]) ?? []
                    let payloads = observations
                        .sorted(by: barcodePriority)
                        .compactMap { $0.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    continuation.resume(returning: payloads.isEmpty ? nil : payloads.joined(separator: "\n"))
                }
                // 2D machine-readable codes only — 1D barcodes often sit next to text the user wants via OCR.
                request.symbologies = [.qr, .aztec, .dataMatrix, .pdf417]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }.value
    }

    /// Larger / more central codes first; stable enough when several are in one crop.
    private static func barcodePriority(_ a: VNBarcodeObservation, _ b: VNBarcodeObservation) -> Bool {
        let areaA = a.boundingBox.width * a.boundingBox.height
        let areaB = b.boundingBox.width * b.boundingBox.height
        if abs(areaA - areaB) > 0.01 {
            return areaA > areaB
        }
        return a.boundingBox.minX < b.boundingBox.minX
    }

    // MARK: - OCR

    private static func recognizeText(_ cgImage: CGImage) async -> String {
        await Task.detached(priority: .userInitiated) {
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
