import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let openAppPreferences = Notification.Name("EggplantShot.openAppPreferences")
}

@main
struct EggplantShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            StatusMenuContent(appState: appState)
        } label: {
            Image(systemName: "scissors")
                .symbolRenderingMode(.hierarchical)
                .background(PreferencesEnvironmentBridge())
        }

        Settings {
            SettingsView(appState: appState)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
    }
}

/// Bridges AppKit status menus → SwiftUI `openSettings`.
private struct PreferencesEnvironmentBridge: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                OpenSettingsGateway.shared.open = { [openSettings] in
                    openSettings()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAppPreferences)) { _ in
                OpenSettingsGateway.shared.open?()
                NSApp.activate(ignoringOtherApps: true)
                NSApp.setActivationPolicy(.regular)
            }
    }
}

@MainActor
enum OpenSettingsGateway {
    static let shared = Gateway()
    final class Gateway {
        var open: (() -> Void)?
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppState.shared.ensureHotkeyMonitorRunning()
        AppState.shared.refreshPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let snipController = SnipController()
    let hotkeyMonitor = HotkeyMonitor()
    let hotkeySettings = HotkeySettings()

    @Published var accessibilityTrusted = false
    @Published var screenAccessGranted = false

    private var accessibilityPollTimer: Timer?
    private var pinBoardCancellable: AnyCancellable?

    private init() {
        // Forward pin-board changes so the status menu refreshes.
        pinBoardCancellable = snipController.pinBoard.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func start() {
        refreshPermissions()
        hotkeyMonitor.onAction = { [weak self] action in
            self?.handleHotkey(action)
        }
        applyHotkeyBindings()
        hotkeyMonitor.setPaused(hotkeySettings.hotkeysDisabled)
        hotkeyMonitor.start()
        startAccessibilityPollingIfNeeded()

        // Register with Screen Recording TCC immediately. The app only appears in
        // System Settings → Screen Recording *after* this API runs — not when
        // the binary is merely present on disk. Do not wait for Accessibility.
        if !screenAccessGranted {
            _ = ScreenPermissions.requestScreenAccess()
            refreshPermissions()
        }

        if !accessibilityTrusted || !screenAccessGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.promptPermissionsIfNeeded()
            }
        }
    }

    func stop() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        hotkeyMonitor.stop()
    }

    func snip(mode: SnipMode) {
        snipController.snip(mode: mode)
    }

    func toggleHideShowImages() {
        snipController.toggleHideShowImages()
        objectWillChange.send()
    }

    func toggleHotkeysDisabled() {
        setHotkeysDisabled(!hotkeySettings.hotkeysDisabled)
    }

    func setHotkeysDisabled(_ disabled: Bool) {
        hotkeySettings.hotkeysDisabled = disabled
        hotkeyMonitor.setPaused(disabled)
        objectWillChange.send()
    }

    func applyHotkey(_ binding: HotkeyBinding, for action: HotkeyAction) {
        hotkeySettings.setBinding(binding, for: action)
        applyHotkeyBindings()
        hotkeyMonitor.setPaused(hotkeySettings.hotkeysDisabled)
        if !hotkeyMonitor.isRunning {
            ensureHotkeyMonitorRunning()
        }
        objectWillChange.send()
    }

    func resetHotkeysToDefaults() {
        hotkeySettings.resetToDefaults()
        applyHotkeyBindings()
        objectWillChange.send()
    }

    func refreshPermissions() {
        accessibilityTrusted = ScreenPermissions.accessibilityTrusted
        screenAccessGranted = ScreenPermissions.hasScreenAccess
    }

    func requestAccessibility() {
        _ = ScreenPermissions.requestAccessibility(prompt: true)
        refreshPermissions()
        ensureHotkeyMonitorRunning()
        if !accessibilityTrusted {
            ScreenPermissions.openAccessibilitySettings()
        }
    }

    func requestScreenAccess() {
        // Must call the TCC API so EggplantShot shows up in the Screen Recording list.
        // Opening Settings alone never adds the app — do not use the + button manually.
        _ = ScreenPermissions.requestScreenAccess()
        refreshPermissions()
        if !screenAccessGranted {
            ScreenPermissions.openScreenCaptureSettings()
        }
    }

    func ensureHotkeyMonitorRunning() {
        let wasTrusted = accessibilityTrusted
        refreshPermissions()
        if accessibilityTrusted {
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
            if !wasTrusted || !hotkeyMonitor.isRunning {
                hotkeyMonitor.restart()
            }
            hotkeyMonitor.setPaused(hotkeySettings.hotkeysDisabled)
        } else {
            startAccessibilityPollingIfNeeded()
        }

        // After returning from System Settings, re-request so the app stays listed
        // and we pick up a newly granted toggle without requiring a full relaunch dance.
        if !screenAccessGranted {
            _ = ScreenPermissions.requestScreenAccess()
            refreshPermissions()
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func handleHotkey(_ action: HotkeyAction) {
        switch action {
        case .snip:
            snip(mode: .pin)
        case .snipAndCopy:
            snip(mode: .copy)
        case .hideShowImages:
            toggleHideShowImages()
        }
    }

    private func applyHotkeyBindings() {
        hotkeyMonitor.updateBindings(hotkeySettings.allBindings)
    }

    private func startAccessibilityPollingIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        guard accessibilityPollTimer == nil else { return }
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.ensureHotkeyMonitorRunning()
            }
        }
    }

    private func promptPermissionsIfNeeded() {
        refreshPermissions()

        if !accessibilityTrusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Needed"
            alert.informativeText = """
            EggplantShot needs Accessibility to listen for F1 and other global hotkeys.

            If the app is already checked but hotkeys still fail:
            1. Quit EggplantShot
            2. Run: tccutil reset Accessibility click.yinsb.EggplantShot
            3. Reopen and enable again when prompted
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                requestAccessibility()
            }
        }

        refreshPermissions()
        // Independent of Accessibility — Screen Recording TCC entry is created only
        // when CGRequestScreenCaptureAccess() runs.
        if !screenAccessGranted {
            let alert = NSAlert()
            alert.messageText = "Screen Recording Access Needed"
            alert.informativeText = """
            EggplantShot needs Screen Recording to capture the screen.

            Click Open System Settings, then enable EggplantShot in the list.
            (It appears after the app requests access — you do not need the + button.)

            After enabling, quit and reopen EggplantShot once.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                requestScreenAccess()
            }
        }
    }
}
