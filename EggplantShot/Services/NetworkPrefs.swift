import Foundation

/// Persisted HTTP proxy settings for the app's outbound requests (currently the update check).
/// Some networks can't reach api.github.com directly, so Preferences → Network lets the user
/// point EggplantShot at a proxy instead of hardcoding one at build time.
enum NetworkPrefs {
    private static let proxyEnabledKey = "network.proxyEnabled"
    private static let proxyHostKey = "network.proxyHost"
    private static let proxyPortKey = "network.proxyPort"

    static let defaultHost = "127.0.0.1"
    static let defaultPort = 7890

    static var proxyEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: proxyEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: proxyEnabledKey) }
    }

    /// Falls back to the default when the user leaves the field blank.
    static var proxyHost: String {
        get {
            let stored = UserDefaults.standard.string(forKey: proxyHostKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? defaultHost : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: proxyHostKey) }
    }

    static var proxyPort: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: proxyPortKey)
            return (1...65535).contains(stored) ? stored : defaultPort
        }
        set { UserDefaults.standard.set(newValue, forKey: proxyPortKey) }
    }

    /// `nil` means "no proxy" — callers should use the plain system network path.
    static var proxyDictionary: [AnyHashable: Any]? {
        guard proxyEnabled else { return nil }
        let host = proxyHost
        let port = proxyPort
        return [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: host,
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: host,
            kCFNetworkProxiesHTTPSPort as String: port,
        ]
    }
}
