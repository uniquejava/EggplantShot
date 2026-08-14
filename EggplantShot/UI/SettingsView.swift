import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem {
                    Label(L10n.tr("General"), systemImage: "gearshape")
                }

            PermissionsSettingsPane(appState: appState)
                .tabItem {
                    Label(L10n.tr("Permissions"), systemImage: "lock.shield")
                }

            HotkeysSettingsPane(appState: appState)
                .tabItem {
                    Label(L10n.tr("Hotkeys"), systemImage: "keyboard")
                }

            AboutView()
                .tabItem {
                    Label(L10n.tr("About"), systemImage: "info.circle")
                }
        }
        .frame(width: 460, height: 400)
        .onAppear {
            appState.refreshPermissions()
        }
    }
}

private struct GeneralSettingsPane: View {
    @State private var selectedLanguage = AppLanguage.preference
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("Startup"))
                    .font(.headline)

                Toggle(L10n.tr("Launch EggplantShot at login"), isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        do {
                            launchAtLoginEnabled = try LaunchAtLogin.setEnabled(newValue)
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                            launchAtLoginEnabled = LaunchAtLogin.isEnabled
                        }
                    }
                ))
                .toggleStyle(.checkbox)

                Text(L10n.tr("EggplantShot stays in the menu bar after login. Quitting the app does not turn this off."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("App language"))
                    .font(.headline)

                Picker("", selection: $selectedLanguage) {
                    ForEach(AppLanguagePreference.allCases) { preference in
                        Text(preference.menuTitle).tag(preference)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                .onChange(of: selectedLanguage) { _, newValue in
                    AppLanguage.setPreferenceAndRelaunch(newValue)
                }

                Text(L10n.tr("Language changes take effect after EggplantShot restarts."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
        }
    }
}

private struct PermissionsSettingsPane: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            permissionRow(
                title: L10n.tr("Accessibility"),
                ok: appState.accessibilityTrusted,
                detail: L10n.tr("Needed for global hotkeys.")
            ) {
                appState.requestAccessibility()
            }

            permissionRow(
                title: L10n.tr("Screen Recording"),
                ok: appState.screenAccessGranted,
                detail: L10n.tr("Needed to capture the screen. Use Request… — do not add the binary with +.")
            ) {
                appState.requestScreenAccess()
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.refreshPermissions()
        }
    }

    private func permissionRow(
        title: String,
        ok: Bool,
        detail: String,
        request: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(ok ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.headline)
                Spacer()
                Text(ok ? L10n.tr("Granted") : L10n.tr("Required"))
                    .foregroundStyle(.secondary)
                if !ok {
                    Button(L10n.tr("Request...")) { request() }
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HotkeysSettingsPane: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settings: HotkeySettings

    init(appState: AppState) {
        self.appState = appState
        _settings = ObservedObject(wrappedValue: appState.hotkeySettings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                hotkeyRow(action)
            }

            HStack {
                Spacer()
                Button(L10n.tr("Reset to Defaults")) {
                    appState.resetHotkeysToDefaults()
                }
            }

            Divider()

            Toggle(L10n.tr("Disable hotkeys"), isOn: Binding(
                get: { settings.hotkeysDisabled },
                set: { appState.setHotkeysDisabled($0) }
            ))
            .toggleStyle(.checkbox)

            Text(L10n.tr("Click a shortcut field, then press a new key combo. F-keys may stand alone; other keys need ⌘/⌥/⌃/⇧. Esc or click away to finish. When disabled, menu actions still work."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear {
            // Never leave the global tap paused if a recorder was focused.
            appState.hotkeyMonitor.setPaused(settings.hotkeysDisabled)
        }
    }

    private func hotkeyRow(_ action: HotkeyAction) -> some View {
        HStack {
            Text(action.settingsTitle)
            Spacer()
            HotkeyRecorderRepresentable(
                binding: settings.binding(for: action),
                onBindingChange: { appState.applyHotkey($0, for: action) },
                onRecordingChange: { recording in
                    if recording {
                        appState.hotkeyMonitor.setPaused(true)
                    } else {
                        appState.hotkeyMonitor.setPaused(settings.hotkeysDisabled)
                    }
                }
            )
            .frame(width: 140, height: 28)
        }
    }
}

// MARK: - AppKit hotkey recorder

private struct HotkeyRecorderRepresentable: NSViewRepresentable {
    let binding: HotkeyBinding
    let onBindingChange: (HotkeyBinding) -> Void
    let onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.binding = binding
        view.onBindingChange = onBindingChange
        view.onRecordingChange = onRecordingChange
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        nsView.binding = binding
        nsView.onBindingChange = onBindingChange
        nsView.onRecordingChange = onRecordingChange
        nsView.refreshDisplay()
    }
}

final class HotkeyRecorderView: NSView {
    var binding = HotkeyBinding(keyCode: HotkeyBinding.f1, modifiers: 0)
    var onBindingChange: ((HotkeyBinding) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private var isRecording = false
    private let accent = NSColor.controlAccentColor
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        label.alignment = .center
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        refreshDisplay()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { beginRecording() }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Esc ends recording without changing the binding.
        if event.keyCode == 53 {
            endRecording()
            window?.makeFirstResponder(nil)
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let next = HotkeyBinding(keyCode: event.keyCode, modifiers: modifiers.rawValue)
        guard next.isValidAssignable else { return }

        commit(next)
    }

    func refreshDisplay() {
        layer?.borderColor = isRecording ? accent.cgColor : NSColor.separatorColor.cgColor
        layer?.backgroundColor = isRecording
            ? accent.withAlphaComponent(0.12).cgColor
            : NSColor.controlBackgroundColor.cgColor

        if isRecording {
            label.stringValue = L10n.tr("Type shortcut")
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = binding.displayName
            label.textColor = .labelColor
        }
    }

    private func beginRecording() {
        guard !isRecording else {
            refreshDisplay()
            return
        }
        isRecording = true
        onRecordingChange?(true)
        refreshDisplay()
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        onRecordingChange?(false)
        refreshDisplay()
    }

    private func commit(_ next: HotkeyBinding) {
        binding = next
        isRecording = false
        onRecordingChange?(false)
        refreshDisplay()
        onBindingChange?(next)
        window?.makeFirstResponder(nil)
    }
}
