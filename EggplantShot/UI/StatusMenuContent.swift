import AppKit
import SwiftUI

struct StatusMenuContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button(L10n.tr("Capture")) {
            appState.snip(mode: .pin)
        }
        .keyboardShortcut(.f1, modifiers: [])

        Button(L10n.tr("Capture and copy")) {
            appState.snip(mode: .copy)
        }
        .keyboardShortcut(.f1, modifiers: [.command])

        Button(L10n.tr("Paste")) {
            appState.pasteFromClipboard()
        }
        .keyboardShortcut(.f3, modifiers: [])

        Button(appState.snipController.pinBoard.imagesHidden
               ? L10n.tr("Show all images")
               : L10n.tr("Hide all images")) {
            appState.toggleHideShowImages()
        }
        .keyboardShortcut(.f3, modifiers: [.shift])
        .disabled(appState.snipController.pinBoard.items.isEmpty)

        Button(L10n.tr("Switch to another image group")) {
            // Stub
        }
        .keyboardShortcut(.f3, modifiers: [.command])
        .disabled(true)

        Divider()

        Button(appState.hotkeySettings.hotkeysDisabled
               ? L10n.tr("Enable hotkeys")
               : L10n.tr("Disable hotkeys")) {
            appState.toggleHotkeysDisabled()
        }

        Divider()

        Menu(L10n.tr("Images")) {
            if appState.snipController.pinBoard.items.isEmpty {
                Text(L10n.tr("No images"))
                    .disabled(true)
            } else {
                ForEach(appState.snipController.pinBoard.items.reversed()) { item in
                    Button(item.title) {
                        appState.snipController.pinBoard.bringToFront(item.id)
                    }
                }
                Divider()
                Button(L10n.tr("Close All")) {
                    appState.snipController.pinBoard.closeAll()
                }
            }
        }

        Menu(L10n.tr("Language")) {
            ForEach(AppLanguagePreference.allCases) { preference in
                Button {
                    AppLanguage.setPreferenceAndRelaunch(preference)
                } label: {
                    Text(preference == AppLanguage.preference
                         ? "✓ \(preference.menuTitle)"
                         : preference.menuTitle)
                }
            }
        }

        Divider()

        SettingsLink {
            Text(L10n.tr("Preferences..."))
        }
        .keyboardShortcut(",", modifiers: [.command])
        .simultaneousGesture(TapGesture().onEnded {
            NSApp.activate(ignoringOtherApps: true)
        })

        Button(L10n.tr("Help")) {
            // Stub
        }
        .disabled(true)

        Button(L10n.tr("Check for updates...")) {
            // Stub
        }
        .disabled(true)

        Divider()

        Button(L10n.tr("Quit")) {
            appState.quit()
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}

private extension KeyEquivalent {
    static let f1 = KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey)!))
    static let f3 = KeyEquivalent(Character(UnicodeScalar(NSF3FunctionKey)!))
}
