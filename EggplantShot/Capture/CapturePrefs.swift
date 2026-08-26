import Foundation

/// Persisted capture-time options. The status menu and Preferences → General both drive these,
/// so the value lives here rather than on either view's state.
enum CapturePrefs {
    private static let includesCursorKey = "capture.includesCursor"

    /// Bake the mouse pointer into the freeze, where it sat when the hotkey fired.
    /// Off by default (Snipaste parity).
    ///
    /// The freeze is the single source for pin / copy / save / OCR / history, so flipping this
    /// puts the pointer in every one of them — and, because the frozen backdrop is what the user
    /// selects over, they can see where it will land before confirming.
    static var includesCursor: Bool {
        get { UserDefaults.standard.bool(forKey: includesCursorKey) }
        set { UserDefaults.standard.set(newValue, forKey: includesCursorKey) }
    }
}
