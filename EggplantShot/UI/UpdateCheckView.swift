import AppKit
import SwiftUI

/// UI-facing phase of an in-flight or completed update check.
enum UpdateCheckState {
    case checking
    case upToDate
    case updateAvailable(UpdateChecker.Release)
    case failed
}

struct UpdateCheckView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            switch appState.updateCheckState {
            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text(L10n.tr("Checking for updates…"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

            case .upToDate:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                Text(L10n.tr("You're Up to Date"))
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.tr("EggplantShot %@ is the latest version.", UpdateChecker.currentVersion))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button(L10n.tr("OK")) { dismiss() }
                    .keyboardShortcut(.defaultAction)

            case .updateAvailable(let release):
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                Text(L10n.tr("Update Available"))
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.tr("EggplantShot %1$@ is available. You're on %2$@.", release.version, UpdateChecker.currentVersion))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Button(L10n.tr("Later")) { dismiss() }
                    Button(L10n.tr("View on GitHub")) {
                        NSWorkspace.shared.open(release.htmlURL)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }

            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text(L10n.tr("Couldn't Check for Updates"))
                    .font(.system(size: 14, weight: .semibold))
                Text(L10n.tr("Please check your internet connection and try again."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Button(L10n.tr("Close")) { dismiss() }
                    Button(L10n.tr("Retry")) { appState.checkForUpdates() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 300)
        .fixedSize()
    }
}
