import AppKit

/// Short UI feedback sounds (OCR success, etc.).
enum FeedbackSound {
    /// Soft double bubble-pop bundled as `ocr-success.wav`.
    static func playOCRSuccess() {
        guard let url = Bundle.main.url(forResource: "ocr-success", withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: true)
        else { return }
        sound.volume = 0.85
        sound.play()
    }
}
