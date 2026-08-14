import AppKit
import SwiftUI

struct StatusMenuContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button("Capture") {
            appState.snip(mode: .pin)
        }
        .keyboardShortcut(.f1, modifiers: [])

        Button("Capture and copy") {
            appState.snip(mode: .copy)
        }
        .keyboardShortcut(.f1, modifiers: [.command])

        Button("Custom capture") {
            // Stub — future: remembered / fixed region.
        }
        .keyboardShortcut(.f1, modifiers: [.shift])
        .disabled(true)

        Button("Paste") {
            // Stub — future: pin clipboard image.
        }
        .keyboardShortcut(.f3, modifiers: [])
        .disabled(true)

        Button(appState.snipController.pinBoard.imagesHidden ? "Show all images" : "Hide all images") {
            appState.toggleHideShowImages()
        }
        .keyboardShortcut(.f3, modifiers: [.shift])
        .disabled(appState.snipController.pinBoard.items.isEmpty)

        Button("Switch to another image group") {
            // Stub
        }
        .keyboardShortcut(.f3, modifiers: [.command])
        .disabled(true)

        Divider()

        Button(appState.hotkeySettings.hotkeysDisabled ? "Enable hotkeys" : "Disable hotkeys") {
            appState.toggleHotkeysDisabled()
        }

        Divider()

        Menu("Images") {
            if appState.snipController.pinBoard.items.isEmpty {
                Text("No images")
                    .disabled(true)
            } else {
                ForEach(appState.snipController.pinBoard.items.reversed()) { item in
                    Button(item.title) {
                        appState.snipController.pinBoard.bringToFront(item.id)
                    }
                }
                Divider()
                Button("Close All") {
                    appState.snipController.pinBoard.closeAll()
                }
            }
        }

        Divider()

        SettingsLink {
            Text("Preferences...")
        }
        .keyboardShortcut(",", modifiers: [.command])
        .simultaneousGesture(TapGesture().onEnded {
            NSApp.activate(ignoringOtherApps: true)
        })

        Button("Help") {
            // Stub
        }
        .disabled(true)

        Button("Check for updates...") {
            // Stub
        }
        .disabled(true)

        Divider()

        Button("Quit") {
            appState.quit()
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}

private extension KeyEquivalent {
    static let f1 = KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey)!))
    static let f3 = KeyEquivalent(Character(UnicodeScalar(NSF3FunctionKey)!))
}
