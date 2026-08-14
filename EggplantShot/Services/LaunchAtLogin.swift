import AppKit
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> Bool {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return isEnabled
    }

    /// True when this process was started by Login Items (not a user open from Finder).
    /// Prefer the Apple Event flag; fall back to “login item + just after boot” for SMAppService.
    static var wasLaunchedAtLogin: Bool {
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventClass == AEEventClass(kCoreEventClass),
           event.eventID == AEEventID(kAEOpenApplication),
           let code = event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue,
           code == keyAELaunchedAsLogInItem || code == keyAELaunchedAsServiceItem {
            return true
        }
        // SMAppService sometimes omits the prop; avoid popping UI at every login.
        if isEnabled, ProcessInfo.processInfo.systemUptime < 120 {
            return true
        }
        return false
    }
}

/// `keyAELaunchedAsLogInItem` / `keyAELaunchedAsServiceItem` (Carbon) as FourCharCodes.
private let keyAELaunchedAsLogInItem: OSType = 0x6C6F6769 // 'logi'
private let keyAELaunchedAsServiceItem: OSType = 0x73766369 // 'svci'
