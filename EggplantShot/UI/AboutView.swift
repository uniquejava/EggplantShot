import AppKit
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            Text(AppAboutInfo.appName)
                .font(.system(size: 20, weight: .semibold))

            Text(AppAboutInfo.versionLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(AppAboutInfo.copyright)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 4) {
                Text(L10n.tr("Author · %@", AppAboutInfo.author))
                    .font(.system(size: 12))

                Link(AppAboutInfo.githubDisplay, destination: AppAboutInfo.githubURL)
                    .font(.system(size: 12))
            }
            .padding(.top, 2)

            Divider()
                .frame(maxWidth: 280)

            VStack(spacing: 4) {
                Text(L10n.tr("Built with"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(AppAboutInfo.techStack)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

enum AppAboutInfo {
    static let author = "uniquejava"
    static let githubURL = URL(string: "https://github.com/uniquejava/EggplantShot")!
    static let githubDisplay = "github.com/uniquejava/EggplantShot"
    static let techStack = """
    SwiftUI + AppKit · CGEvent hotkey tap
    ScreenCaptureKit capture · pin overlays
    macOS 15+
    """

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "EggplantShot"
    }

    static var versionLine: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return L10n.tr("Version %1$@ (%2$@)", short, build)
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026 uniquejava. All rights reserved."
    }
}
