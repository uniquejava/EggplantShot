import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            PermissionsSettingsPane(appState: appState)
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            HotkeysSettingsPane(appState: appState)
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }

            AboutSettingsPane()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 460, height: 260)
        .onAppear {
            appState.refreshPermissions()
        }
    }
}

private struct PermissionsSettingsPane: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            permissionRow(
                title: "Accessibility",
                ok: appState.accessibilityTrusted,
                detail: "Needed for global hotkeys (F1, ⌘F1, ⇧F3)."
            ) {
                appState.requestAccessibility()
            }

            permissionRow(
                title: "Screen Recording",
                ok: appState.screenAccessGranted,
                detail: "Needed to capture the screen. Use Request… — do not add the binary with +."
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
                Text(ok ? "Granted" : "Required")
                    .foregroundStyle(.secondary)
                if !ok {
                    Button("Request...") { request() }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hotkeyRow("Snip", appState.hotkeySettings.snip.displayName)
            hotkeyRow("Snip and copy", appState.hotkeySettings.snipAndCopy.displayName)
            hotkeyRow("Hide/Show images", appState.hotkeySettings.hideShowImages.displayName)

            Divider()

            Toggle("Disable hotkeys", isOn: Binding(
                get: { appState.hotkeySettings.hotkeysDisabled },
                set: { appState.setHotkeysDisabled($0) }
            ))
            .toggleStyle(.checkbox)

            Text("When disabled, menu actions still work; only global shortcuts are paused.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func hotkeyRow(_ title: String, _ shortcut: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "scissors")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("EggplantShot")
                .font(.title2.weight(.semibold))
            Text("Version \(AppInfo.versionLine)")
                .foregroundStyle(.secondary)
            Text("Snipaste-style area capture for macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

enum AppInfo {
    static var versionLine: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
